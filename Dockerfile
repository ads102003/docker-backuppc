ARG ALPINE_VERSION="3.19"

FROM docker.io/library/alpine:${ALPINE_VERSION}

LABEL org.opencontainers.image.title="BackupPC" \
      org.opencontainers.image.description="BackupPC on Alpine with nginx + fcgiwrap" \
      org.opencontainers.image.licenses="MIT"

ARG BACKUPPC_VERSION="4.4.0"
ARG BACKUPPC_XS_VERSION="0.62"
ARG PAR2_VERSION="v0.8.0"
ARG RSYNC_BPC_VERSION="3.1.3.0"
ARG PBZIP2_VERSION="1.1.13"

ENV BACKUPPC_VERSION=${BACKUPPC_VERSION} \
    USER_BACKUPPC=1000 \
    GROUP_BACKUPPC=1000

COPY patches/ /tmp/patches/

RUN set -ex && \
    apk upgrade --no-cache && \
    apk add --no-cache --virtual .backuppc-build-deps \
                acl-dev \
                autoconf \
                automake \
                build-base \
                bzip2-dev \
                curl \
                expat-dev \
                git \
                patch \
                perl-app-cpanminus \
                perl-dev \
                && \
    apk add --no-cache \
                bash \
                bzip2 \
                ca-certificates \
                expat \
                fcgiwrap \
                gzip \
                iputils \
                libgomp \
                nginx \
                openssh-client \
                openssl \
                perl \
                perl-archive-zip \
                perl-cgi \
                perl-file-listing \
                perl-json-xs \
                perl-time-parsedate \
                perl-xml-rss \
                pigz \
                rrdtool \
                rsync \
                samba-client \
                shadow \
                spawn-fcgi \
                su-exec \
                tini \
                ttf-dejavu \
                tzdata \
                && \
    \
    addgroup -S -g ${GROUP_BACKUPPC} backuppc && \
    adduser -D -S -h /home/backuppc -s /bin/sh -G backuppc -g backuppc -u ${USER_BACKUPPC} backuppc && \
    addgroup nginx backuppc && \
    \
    cpanm --notest -M https://cpan.metacpan.org Net::FTP Net::FTP::AutoReconnect && \
    \
    mkdir -p /usr/src/pbzip2 && \
    curl -fsSL https://launchpad.net/pbzip2/1.1/${PBZIP2_VERSION}/+download/pbzip2-${PBZIP2_VERSION}.tar.gz | tar xzf - --strip-components=1 -C /usr/src/pbzip2 && \
    make -C /usr/src/pbzip2 -j$(nproc) && \
    make -C /usr/src/pbzip2 install && \
    \
    git clone --depth 1 --branch ${BACKUPPC_XS_VERSION} https://github.com/backuppc/backuppc-xs.git /usr/src/backuppc-xs && \
    cd /usr/src/backuppc-xs && \
    perl Makefile.PL && \
    make -j$(nproc) && \
    make test && \
    make install && \
    \
    git clone --depth 1 --branch ${RSYNC_BPC_VERSION} https://github.com/backuppc/rsync-bpc.git /usr/src/rsync-bpc && \
    cd /usr/src/rsync-bpc && \
    ./configure && \
    make reconfigure && \
    make -j$(nproc) && \
    make install && \
    \
    git clone --depth 1 --branch ${PAR2_VERSION} https://github.com/Parchive/par2cmdline.git /usr/src/par2cmdline && \
    cd /usr/src/par2cmdline && \
    ./automake.sh && \
    ./configure && \
    make -j$(nproc) && \
    make install && \
    \
    mkdir -p /assets/install && \
    curl -fsSL https://github.com/backuppc/backuppc/releases/download/${BACKUPPC_VERSION}/BackupPC-${BACKUPPC_VERSION}.tar.gz | tar xzf - --strip-components=1 -C /assets/install && \
    cd /assets/install && \
    for p in /tmp/patches/*.patch; do patch -p1 < "$p" || exit 1; done && \
    perl configure.pl \
        --batch \
        --backuppc-user backuppc \
        --config-dir /etc/backuppc \
        --cgi-dir /www/cgi-bin/BackupPC \
        --data-dir /var/lib/backuppc \
        --hostname localhost \
        --html-dir /www/html/BackupPC \
        --html-dir-url /BackupPC \
        --install-dir /usr/local/BackupPC \
        --log-dir /www/logs \
        && \
    mkdir -p /assets/conf-default && \
    mv /etc/backuppc/* /assets/conf-default/ && \
    sed -i "s/^\$Conf{CgiAdminUsers}\s*=.*/\$Conf{CgiAdminUsers} = 'backuppc';/" /assets/conf-default/config.pl && \
    cd / && \
    rm -rf /assets/install && \
    \
    apk del .backuppc-build-deps && \
    rm -rf /root/.cpanm /tmp/* /usr/src/* /etc/nginx/http.d/default.conf

COPY install/ /

EXPOSE 80

VOLUME ["/etc/backuppc", "/home/backuppc", "/var/lib/backuppc", "/www/logs"]

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
