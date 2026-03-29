# Dockerfile for NPP-Optimized WordPress Setup                                     #
# ----------------------------------------------------------------------------     #
# Author: [Hasan ÇALIŞIR]                                                          #
# Purpose: Full-stack Dockerized environment for NPP WordPress plugin, including   #
#          WordPress, PHP-FPM, Nginx, MySQL, WP-CLI, and necessary PHP extensions. #
# ----------------------------------------------------------------------------     #

# Here the magic, the rest of it is ordinary
FROM wordpress:6.9.4-php8.4-fpm

# Set some ugly stuff
ENV LANG=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive

# Set package versions
ENV LIBFUSE_VERSION=3.18.2 \
    BINDFS_VERSION=1.18.4 \
    SAFEXEC_VERSION=1.9.5-1 \
    SAFEXEC_RELEASE_TAG=v2.1.4

# Set package URL's
ENV FUSE_URL="https://github.com/libfuse/libfuse/releases/download/fuse-${LIBFUSE_VERSION}/fuse-${LIBFUSE_VERSION}.tar.gz" \
    FUSE_SIG_URL="https://github.com/libfuse/libfuse/releases/download/fuse-${LIBFUSE_VERSION}/fuse-${LIBFUSE_VERSION}.tar.gz.sig" \
    BINDFS_URL="https://github.com/mpartel/bindfs/archive/refs/tags/${BINDFS_VERSION}.tar.gz" \
    WP_CLI_URL="https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar" \
    PHP_EXT_URL="https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions" \
    SAFEXEC_RELEASE_URL="https://github.com/psaux-it/nginx-fastcgi-cache-purge-and-preload/releases/download"

# Set PHP extensions
ENV PHP_EXTENSIONS="bz2 calendar ctype curl dom iconv json mbstring pdo_pgsql readline simplexml \
    soap sockets sodium xml xsl openssl exif zip intl event memcached yaml \
    xdebug apcu zlib session redis uuid brotli http mailparse ssh2 xattr \
    xdiff filter igbinary opcache timezonedb bcmath shmop pcre geos"

# Install dependencies
# Build time dependencies will purged soon
RUN apt-get update && apt-get install -y \
    # Install runtime dependencies for NPP core
    procps \
    gawk \
    grep \
    sed \
    coreutils \
    wget \
    cpulimit \
    ripgrep \
    # Install dependencies for service health checks
    mariadb-client \
    netcat-traditional \
    iputils-ping \
    # Install common dependencies
    curl \
    # Install dev deploy dependencies
    git \
    dos2unix \
    rsync \
    # Install build time dependencies for 'bindfs' 
    build-essential \
    automake \
    libtool \
    pkg-config \
    # Install build time dependencies for 'fuse3, libfuse3'
    meson \
    ninja-build \
    signify-openbsd

# Get WP-CLI
RUN curl -LO ${WP_CLI_URL} \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

# Debian ships with old 'fuse' unfortunately
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=1084458

# 1) First compile and install 'bindfs' dependencies
RUN cd /tmp && \
    curl -LO ${FUSE_URL} && \
    curl -LO ${FUSE_SIG_URL} && \
    tar xzf fuse-${LIBFUSE_VERSION}.tar.gz && \
    signify-openbsd -V -m fuse-${LIBFUSE_VERSION}.tar.gz -p fuse-${LIBFUSE_VERSION}/signify/fuse-3.18.pub && \
    cd fuse-${LIBFUSE_VERSION} && \
    mkdir build && cd build && \
    meson setup .. && \
    meson configure -D disable-mtab=true \
    -D initscriptdir="" \
    -D udevrulesdir="" \
    -D utils=true \
    -D examples=false \
    -D useroot=false \
    -D tests=false && \
    meson setup --reconfigure ../ && \
    ninja && \
    ninja install && \
    cd /tmp && \
    rm -rf fuse-${LIBFUSE_VERSION} fuse-${LIBFUSE_VERSION}.tar.gz fuse-${LIBFUSE_VERSION}.tar.gz.sig

# 2) Now compile and Install 'bindfs'
RUN cd /tmp && \
    curl -LO ${BINDFS_URL} && \
    tar xzf ${BINDFS_VERSION}.tar.gz && \
    cd bindfs-${BINDFS_VERSION} && \
    ./autogen.sh && \
    ./configure && \
    make && \
    make install && \
    cd /tmp && \
    rm -rf bindfs-${BINDFS_VERSION} ${BINDFS_VERSION}.tar.gz

# Install PHP extensions
ADD --chmod=0755 ${PHP_EXT_URL} /usr/local/bin/
RUN install-php-extensions ${PHP_EXTENSIONS}

# Install safexec
ARG INSTALL_SAFEXEC=true
RUN if [ "${INSTALL_SAFEXEC}" = "true" ]; then \
        ARCH=$(dpkg --print-architecture) && \
        BASE_URL="${SAFEXEC_RELEASE_URL}/${SAFEXEC_RELEASE_TAG}" && \
        DEB="safexec_${SAFEXEC_VERSION}_${ARCH}.deb" && \
        wget -q "${BASE_URL}/SHA256SUMS"    -O /tmp/safexec-SHA256SUMS && \
        wget -q "${BASE_URL}/${DEB}"        -O "/tmp/${DEB}" && \
        cd /tmp && sha256sum -c safexec-SHA256SUMS --ignore-missing && \
        apt-get install -y "/tmp/${DEB}" && \
        rm -f "/tmp/${DEB}" /tmp/safexec-SHA256SUMS && \
        echo "safexec $(safexec --version 2>&1 || true) installed successfully"; \
    else \
        echo "INSTALL_SAFEXEC=false — skipping safexec installation"; \
    fi

# Copy the scripts into the container
COPY wordpress/entrypoint-wp.sh /entrypoint-wp.sh
COPY wordpress/wp-post.sh /scripts/wp-post.sh

# Normalize line endings
RUN dos2unix /entrypoint-wp.sh /scripts/wp-post.sh

# Make sure scripts are executable
RUN chmod +x /entrypoint-wp.sh
RUN chmod +x /scripts/wp-post.sh

# Remove build time dependencies to keep image consistent
RUN apt-get purge -y \
    build-essential \
    automake \
    libtool \
    pkg-config \
    meson \
    ninja-build \
    signify-openbsd && \
    apt-get autoremove -y && \
    apt-get clean

# CMD
CMD ["/entrypoint-wp.sh", "php-fpm"]
