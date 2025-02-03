# WordPress (6.7.1) with PHP-FPM (8.2)
FROM wordpress:6.7.1-php8.2-fpm

# Install dependencies for NPP core
RUN apt-get update && apt-get install -y \
    procps \
    gawk \
    grep \
    sed \
    coreutils \
    curl \
    wget \
    cpulimit

# Install dependencies for container management
RUN apt-get install -y \    
    mariadb-client \
    netcat-traditional

# Install dependencies for 'bindfs'
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=1084458
RUN apt-get install -y \
    build-essential \
    automake \
    libtool \
    pkg-config \
    fuse3 \
    libfuse3-dev \
    git

# Install WP-CLI
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

# WP-CLI --allow-root
ENV WP_CLI_ALLOW_ROOT=1

# Install wide range of PHP extensions
ADD --chmod=0755 https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN install-php-extensions \
    bz2 calendar ctype curl dom iconv json mbstring pdo_pgsql readline simplexml \
    soap sockets sodium xml xsl openssl exif zip intl event memcached yaml \
    xdebug apcu zlib session redis uuid brotli http mailparse ssh2 xattr \
    xdiff filter igbinary opcache timezonedb bcmath shmop pcre geos

# Compile and Install latest 'bindfs (1.17.7)' from source code
RUN git clone https://github.com/mpartel/bindfs.git /npp-wp/bindfs
RUN /bin/bash -c "cd /npp-wp/bindfs && ./autogen.sh"
RUN /bin/bash -c "cd /npp-wp/bindfs && ./configure && make && make install"
RUN rm -rf /npp-wp/bindfs

# Copy the scripts into the container
COPY wordpress/entrypoint-wp.sh /entrypoint-wp.sh
COPY wordpress/wp-cli.sh /scripts/wp-cli.sh

# Make sure scripts are executable
RUN chmod +x /entrypoint-wp.sh
RUN chmod +x /scripts/wp-cli.sh

# Default command
CMD ["/bin/bash", "/entrypoint-wp.sh", "php-fpm"]
