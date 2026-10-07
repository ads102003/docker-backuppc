#!/bin/bash
set -euo pipefail

CONFIG_PATH=${CONFIG_PATH:-/etc/backuppc}
DATA_PATH=${DATA_PATH:-/var/lib/backuppc}
LOG_PATH=${LOG_PATH:-/www/logs}
SSH_KEYS_PATH=${SSH_KEYS_PATH:-/home/backuppc/.ssh}
USER_BACKUPPC=${USER_BACKUPPC:-1000}
GROUP_BACKUPPC=${GROUP_BACKUPPC:-1000}

log() { echo "[backuppc] $*"; }

# Match the backuppc uid/gid to the owner of existing data so old pools stay readable
if [ "$(id -g backuppc)" != "${GROUP_BACKUPPC}" ]; then
    log "Setting backuppc gid to ${GROUP_BACKUPPC}"
    groupmod -o -g "${GROUP_BACKUPPC}" backuppc
fi
if [ "$(id -u backuppc)" != "${USER_BACKUPPC}" ]; then
    log "Setting backuppc uid to ${USER_BACKUPPC}"
    usermod -o -u "${USER_BACKUPPC}" backuppc
fi

mkdir -p "${CONFIG_PATH}" "${DATA_PATH}" "${LOG_PATH}" "${SSH_KEYS_PATH}" /home/backuppc /run/nginx
# Only chown top-level directories; recursively chowning a large pool would take forever
chown backuppc:backuppc /home/backuppc "${DATA_PATH}" "${LOG_PATH}"
chown -R backuppc:backuppc "${CONFIG_PATH}" "${SSH_KEYS_PATH}"
chmod 700 "${SSH_KEYS_PATH}"
if [ ! -e /home/backuppc/.ssh ]; then
    ln -sf "${SSH_KEYS_PATH}" /home/backuppc/.ssh
fi

if [ ! -f "${SSH_KEYS_PATH}/id_rsa" ]; then
    log "Creating RSA SSH key"
    su-exec backuppc ssh-keygen -q -t rsa -b 4096 -N '' -f "${SSH_KEYS_PATH}/id_rsa"
fi
if [ ! -f "${SSH_KEYS_PATH}/id_ed25519" ]; then
    log "Creating ed25519 SSH key"
    su-exec backuppc ssh-keygen -q -t ed25519 -o -a 100 -N '' -f "${SSH_KEYS_PATH}/id_ed25519"
fi

if [ -f "${CONFIG_PATH}/config.pl" ]; then
    log "Existing configuration found in ${CONFIG_PATH}, upgrading in place"
else
    log "No configuration found, generating defaults in ${CONFIG_PATH}"
fi
(
    cd /assets/install
    perl configure.pl \
        --batch \
        --config-dir "${CONFIG_PATH}" \
        --cgi-dir /www/cgi-bin/BackupPC \
        --data-dir "${DATA_PATH}" \
        --hostname localhost \
        --html-dir /www/html/BackupPC \
        --html-dir-url /BackupPC \
        --install-dir /usr/local/BackupPC \
        --log-dir "${LOG_PATH}"
)
chown -R backuppc:backuppc "${CONFIG_PATH}"

# The web UI always runs as the "backuppc" user, so make sure it is an admin
sed -i "s/^\$Conf{CgiAdminUsers}\s*=\s*'[^']*'/\$Conf{CgiAdminUsers} = 'backuppc'/" "${CONFIG_PATH}/config.pl"

# Optional HTTP basic auth (same variable names as the original image)
rm -f /etc/nginx/backuppc-auth.conf /etc/nginx/backuppc.htpasswd
touch /etc/nginx/backuppc-auth.conf
if [ "${NGINX_AUTHENTICATION_TYPE:-NONE}" = "BASIC" ]; then
    : > /etc/nginx/backuppc.htpasswd
    i=1
    while true; do
        user_var="NGINX_AUTHENTICATION_BASIC_USER${i}"
        pass_var="NGINX_AUTHENTICATION_BASIC_PASS${i}"
        [ -n "${!user_var:-}" ] || break
        printf '%s:%s\n' "${!user_var}" "$(openssl passwd -apr1 "${!pass_var:-}")" >> /etc/nginx/backuppc.htpasswd
        i=$((i + 1))
    done
    if [ -s /etc/nginx/backuppc.htpasswd ]; then
        log "Enabling HTTP basic authentication"
        chown root:backuppc /etc/nginx/backuppc.htpasswd
        chmod 640 /etc/nginx/backuppc.htpasswd
        cat > /etc/nginx/backuppc-auth.conf <<EOF
auth_basic "${NGINX_AUTHENTICATION_TITLE:-Please login}";
auth_basic_user_file /etc/nginx/backuppc.htpasswd;
EOF
    fi
fi

rm -f /run/fcgiwrap.sock
log "Starting fcgiwrap"
spawn-fcgi -n -s /run/fcgiwrap.sock -u backuppc -g backuppc -U backuppc -G backuppc -M 660 -- /usr/bin/fcgiwrap &

log "Starting nginx on port 80"
nginx -g 'daemon off;' &

log "Starting BackupPC ${BACKUPPC_VERSION}"
su-exec backuppc /usr/local/BackupPC/bin/BackupPC &

# Exit (and let docker restart us) if any of the services dies
wait -n
log "A service exited, shutting down"
exit 1
