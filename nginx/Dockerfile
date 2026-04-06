# Dockerfile for NPP-Optimized WordPress Setup                                     #
# ----------------------------------------------------------------------------     #
# Author: [Hasan ÇALIŞIR]                                                          #
# Purpose: Full-stack Dockerized environment for NPP WordPress plugin, including   #
#          WordPress, PHP-FPM, Nginx, MySQL, WP-CLI, and necessary PHP extensions. #
# ----------------------------------------------------------------------------     #

# ── Stage 1: Build ngx_cache_purge .deb via official pkg-oss / build_module.sh ──
ARG NGINX_FROM_IMAGE=nginx:1.29.7-trixie
FROM ${NGINX_FROM_IMAGE} AS builder

ARG NGX_CACHE_PURGE_VERSION=2.5.6

SHELL ["/bin/bash", "-exo", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install -y --no-install-suggests --no-install-recommends \
        patch make wget git devscripts debhelper dpkg-dev \
        quilt lsb-release build-essential libxml2-utils xsltproc \
        equivs g++ libparse-recdescent-perl \
    && rm -rf /var/lib/apt/lists/*

RUN XSLSCRIPT_SHA512="f7194c5198daeab9b3b0c3aebf006922c7df1d345d454bd8474489ff2eb6b4bf8e2ffe442489a45d1aab80da6ecebe0097759a1e12cc26b5f0613d05b7c09ffa *stdin" \
    && wget -O /tmp/xslscript.pl \
        https://raw.githubusercontent.com/nginx/xslscript/9204424259c343ca08a18a78915f40f28025e093/xslscript.pl \
    && if [ "$(cat /tmp/xslscript.pl | openssl sha512 -r)" = "$XSLSCRIPT_SHA512" ]; then \
        echo "XSLScript checksum OK"; \
        chmod +x /tmp/xslscript.pl; \
        mv /tmp/xslscript.pl /usr/local/bin/; \
    else \
        echo "XSLScript checksum FAILED"; exit 1; \
    fi

RUN git clone -b ${NGINX_VERSION}-${PKG_RELEASE%%~*} \
        https://github.com/nginx/pkg-oss/ /pkg-oss

RUN mkdir /tmp/packages \
    && /pkg-oss/build_module.sh \
        -v "${NGINX_VERSION}" \
        -f -y \
        -o /tmp/packages \
        -n cachepurge \
        "https://github.com/nginx-modules/ngx_cache_purge/archive/refs/tags/${NGX_CACHE_PURGE_VERSION}.tar.gz" \
    && echo 'BUILT_MODULES="cachepurge"' > /tmp/packages/modules.env

# ── Stage 2: Final image ─────────────────────────────────────────────────────────
FROM ${NGINX_FROM_IMAGE}

RUN --mount=type=bind,target=/tmp/packages/,source=/tmp/packages/,from=builder \
    apt-get update \
    && . /tmp/packages/modules.env \
    && for module in $BUILT_MODULES; do \
           apt-get install --no-install-suggests --no-install-recommends -y \
               /tmp/packages/nginx-module-${module}_${NGINX_VERSION}*.deb; \
       done \
    && rm -rf /var/lib/apt/lists/*

# Install necessary packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    netcat-traditional \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Copy the entrypoint script into the container
COPY nginx/entrypoint-nginx.sh /entrypoint-nginx.sh

# Make sure the entrypoint script is executable
RUN chmod +x /entrypoint-nginx.sh

# CMD
CMD ["/entrypoint-nginx.sh", "nginx", "-g", "daemon off;"]
