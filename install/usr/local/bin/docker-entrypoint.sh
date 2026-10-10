#!/bin/bash
set -euo pipefail

# These paths are baked into the BackupPC install at image build time
CONFIG_PATH=/etc/backuppc
DATA_PATH=/var/lib/backuppc
LOG_PATH=/www/logs
SSH_KEYS_PATH=/home/backuppc/.ssh
USER_BACKUPPC=${USER_BACKUPPC:-1000}
GROUP_BACKUPPC=${GROUP_BACKUPPC:-1000}

log() { echo "[backuppc] $*"; }
warn() { echo "[backuppc] WARNING: $*" >&2; }

# Match the backuppc uid/gid to the owner of existing data so old pools stay readable
if [ "$(id -g backuppc)" != "${GROUP_BACKUPPC}" ]; then
    log "Setting backuppc gid to ${GROUP_BACKUPPC}"
    groupmod -o -g "${GROUP_BACKUPPC}" backuppc
fi
if [ "$(id -u backuppc)" != "${USER_BACKUPPC}" ]; then
    log "Setting backuppc uid to ${USER_BACKUPPC}"
    usermod -o -u "${USER_BACKUPPC}" backuppc
fi

# Files that live inside the image follow the (possibly remapped) backuppc user
mkdir -p /var/run/BackupPC /run/nginx
chown -R backuppc:backuppc /usr/local/BackupPC /www/cgi-bin/BackupPC /www/html/BackupPC /var/run/BackupPC

# Mounted volumes may be read-only or on filesystems that refuse chown (NFS, unRAID shares),
# so nothing below is allowed to stop the container. Only top-level directories of the pool
# are touched; recursively chowning a large pool would take forever.
for dir in "${CONFIG_PATH}" "${DATA_PATH}" "${LOG_PATH}" /home/backuppc; do
    mkdir -p "${dir}" 2>/dev/null || warn "cannot create ${dir}"
    if [ -d "${dir}" ] && [ "$(stat -c '%u' "${dir}")" != "${USER_BACKUPPC}" ]; then
        chown backuppc:backuppc "${dir}" 2>/dev/null || warn "cannot chown ${dir}; it is owned by uid $(stat -c '%u' "${dir}")"
    fi
done

if [ -f "${CONFIG_PATH}/config.pl" ]; then
    log "Using existing configuration in ${CONFIG_PATH} (left unchanged)"
else
    log "No configuration found, writing defaults to ${CONFIG_PATH}"
    cp -n /assets/conf-default/* "${CONFIG_PATH}/"
    chown -R backuppc:backuppc "${CONFIG_PATH}"
fi

if mkdir -p "${SSH_KEYS_PATH}" 2>/dev/null; then
    if [ ! -L /home/backuppc/.ssh ] && [ "$(stat -c '%u' "${SSH_KEYS_PATH}")" != "${USER_BACKUPPC}" ]; then
        chown -R backuppc:backuppc "${SSH_KEYS_PATH}" 2>/dev/null || warn "cannot chown ${SSH_KEYS_PATH}"
    fi
    chmod 700 "${SSH_KEYS_PATH}" 2>/dev/null || true
    if [ ! -f "${SSH_KEYS_PATH}/id_rsa" ]; then
        log "Creating RSA SSH key"
        su-exec backuppc ssh-keygen -q -t rsa -b 4096 -N '' -f "${SSH_KEYS_PATH}/id_rsa" || warn "could not create RSA SSH key"
    fi
    if [ ! -f "${SSH_KEYS_PATH}/id_ed25519" ]; then
        log "Creating ed25519 SSH key"
        su-exec backuppc ssh-keygen -q -t ed25519 -o -a 100 -N '' -f "${SSH_KEYS_PATH}/id_ed25519" || warn "could not create ed25519 SSH key"
    fi
else
    warn "cannot create ${SSH_KEYS_PATH}; skipping SSH key setup"
fi

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
wait -n || status=$?
log "A service exited (status ${status:-0}), shutting down"
exit 1
