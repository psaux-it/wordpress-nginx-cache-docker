#!/usr/bin/env bash
#
# Copyright (C) 2024 Hasan CALISIR <hasan.calisir@psauxit.com>
# Distributed under the GNU General Public License, version 2.0.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# SCRIPT DESCRIPTION:
# -------------------
# NPP (Nginx Cache Purge & Preload for WordPress) Dockerized WordPress entrypoint
# https://github.com/psaux-it/nginx-fastcgi-cache-purge-and-preload
# https://wordpress.org/plugins/fastcgi-cache-purge-and-preload-nginx/

set -Eeuo pipefail

# Define color codes
COLOR_RESET='\033[0m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_RED='\033[0;31m'
COLOR_CYAN='\033[0;36m'
COLOR_BOLD='\033[1m'
COLOR_WHITE='\033[0;97m'
COLOR_BLACK='\033[0;30m'
COLOR_LIGHT_CYAN='\033[0;96m'

# Display pre-entrypoint start message
echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP:${COLOR_RESET} ${COLOR_CYAN}${COLOR_BOLD}[Pre-Entrypoint]:${COLOR_RESET} Preparing environment before starting the ${COLOR_LIGHT_CYAN}WordPress${COLOR_RESET} service..."

# Check if required environment variables are set
for var in \
    NPP_UID \
    NPP_GID \
    NPP_NGINX_CACHE_PATH \
    NPP_USER \
    MOUNT_DIR; do
    if [[ -z "${!var:-}" ]]; then
        echo -e "${COLOR_RED}${COLOR_BOLD}NPP-WP-FATAL:${COLOR_RESET} Missing required environment variable(s): ${COLOR_LIGHT_CYAN}${var}${COLOR_RESET} - ${COLOR_RED}Exiting...${COLOR_RESET}"
        exit 1
    fi
done

# Create Isolated PHP process owner user and group 'npp' on 'wordpress-fpm' container
echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP:${COLOR_RESET} Checking PHP process owner user and group with UID ${COLOR_CYAN}${NPP_UID}${COLOR_RESET} and GID ${COLOR_CYAN}${NPP_GID}${COLOR_RESET}"
if ! getent passwd "${NPP_USER}" >/dev/null 2>&1; then
    groupadd --gid "${NPP_GID}" "${NPP_USER}"  && \
    useradd --gid "${NPP_USER}" --no-create-home --home /nonexistent --comment "Isolated PHP Process owner" --shell /bin/bash --uid "${NPP_UID}" "${NPP_USER}"
    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP:${COLOR_RESET} PHP process owner user ${COLOR_LIGHT_CYAN}${NPP_USER}${COLOR_RESET} is created! Proceeding..."
else
    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP:${COLOR_RESET} PHP process owner user ${COLOR_LIGHT_CYAN}${NPP_USER}${COLOR_RESET} is already exists! Skipping..."
fi

# Configure safexec based on SAFEXEC_ENABLED env var (default: 1)
# Set SAFEXEC_ENABLED=0 in .env to disable safexec at runtime without rebuilding
_safexec_enabled="${SAFEXEC_ENABLED:-1}"
_safexec_bin="$(command -v safexec 2>/dev/null || true)"
 
echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP:${COLOR_RESET} Configuring ${COLOR_LIGHT_CYAN}safexec${COLOR_RESET} (SAFEXEC_ENABLED=${_safexec_enabled})..."
 
if [[ -z "${_safexec_bin}" ]]; then
    echo -e "${COLOR_YELLOW}${COLOR_BOLD}NPP-WP:${COLOR_RESET} ${COLOR_LIGHT_CYAN}safexec${COLOR_RESET} is not installed — skipping safexec configuration."
elif [[ "${_safexec_enabled}" == "1" ]]; then
    chmod +x "${_safexec_bin}"
    # Ensure safexec is owned by root and has the setuid bit so the npp user can invoke it
    chown root:root "${_safexec_bin}"
    chmod u+s    "${_safexec_bin}"
    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP:${COLOR_RESET} ${COLOR_LIGHT_CYAN}safexec${COLOR_RESET} is ${COLOR_GREEN}enabled${COLOR_RESET} at ${COLOR_CYAN}${_safexec_bin}${COLOR_RESET} (setuid root, executable)."
else
    # Remove the executable bit so PHP-FPM/NPP cannot invoke safexec,
    # while keeping the binary present for a quick re-enable via restart
    chmod -x "${_safexec_bin}"
    echo -e "${COLOR_YELLOW}${COLOR_BOLD}NPP-WP:${COLOR_RESET} ${COLOR_LIGHT_CYAN}safexec${COLOR_RESET} is ${COLOR_YELLOW}disabled${COLOR_RESET} — binary present but not executable."
fi
unset _safexec_enabled _safexec_bin

# Ensure the mount directory for bindfs exists
if [[ ! -d "${MOUNT_DIR}" ]]; then
    mkdir -p "${MOUNT_DIR}"
    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP:${COLOR_RESET} Nginx cache FUSE mount directory: ${COLOR_LIGHT_CYAN}${MOUNT_DIR}${COLOR_RESET} is created! Proceeding..."
else
    echo -e "${COLOR_YELLOW}${COLOR_BOLD}NPP-WP:${COLOR_RESET} Nginx cache FUSE mount directory: ${COLOR_LIGHT_CYAN}${MOUNT_DIR}${COLOR_RESET} is already exists! Skipping..."
fi

# Wait until the Nginx Cache Path exists
while [[ ! -d "${NPP_NGINX_CACHE_PATH}" ]]; do
    echo -e "${COLOR_YELLOW}${COLOR_BOLD}NPP-WP:${COLOR_RESET} Nginx Cache Path: ${COLOR_LIGHT_CYAN}${NPP_NGINX_CACHE_PATH}${COLOR_RESET} is not ready. Retrying..."
    sleep 2
done
echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP:${COLOR_RESET} Nginx Cache Path: ${COLOR_LIGHT_CYAN}${NPP_NGINX_CACHE_PATH}${COLOR_RESET} is ready! Proceeding..."

# Mount Nginx cache path with 'bindfs' to grant PHP process owner the necessary permissions
if ! bindfs -u "${NPP_UID}" -g "${NPP_GID}" --perms=u=rwx:g=rx:o= "${NPP_NGINX_CACHE_PATH}" "${MOUNT_DIR}"; then
    echo -e "${COLOR_RED}${COLOR_BOLD}NPP-WP-FATAL:${COLOR_RESET} Mounting with ${COLOR_LIGHT_CYAN}bindfs${COLOR_RESET} failed! ${COLOR_RED}Continuing despite the error...${COLOR_RESET}"
fi

# Log that the bindfs mount was successful
echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP:${COLOR_RESET} The Nginx Cache Path: ${COLOR_LIGHT_CYAN}${NPP_NGINX_CACHE_PATH}${COLOR_RESET} has been successfully mounted to ${COLOR_LIGHT_CYAN}${MOUNT_DIR}${COLOR_RESET} with ${COLOR_CYAN}UID:${NPP_UID}${COLOR_RESET} and ${COLOR_CYAN}GID:${NPP_GID}${COLOR_RESET}."

# Fix permissions for consistency
chown -R root:root \
    /etc/nginx \
    /usr/local/etc/php-fpm.d \
    /usr/local/etc/php/conf.d &&
echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP:${COLOR_RESET} Permissions fixed successfully!" ||
echo -e "${COLOR_RED}${COLOR_BOLD}NPP-WP:${COLOR_RESET} Failed to fix permissions!"

# Wait for the 'wordpress-db' to be ready
until mysql --skip-ssl -h wordpress-db -u"${WORDPRESS_DB_USER}" -p"${WORDPRESS_DB_PASSWORD}" "${WORDPRESS_DB_NAME}" -e "SELECT 1" > /dev/null 2>&1; do
    echo -e "${COLOR_YELLOW}${COLOR_BOLD}NPP-WP:${COLOR_RESET} The ${COLOR_LIGHT_CYAN}MySQL database${COLOR_RESET} is not available yet. Retrying..."
    sleep 6
done
echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP:${COLOR_RESET} The ${COLOR_LIGHT_CYAN}MySQL database${COLOR_RESET} is ready! Proceeding..."

# Wait for Redis to be ready
_redis_host="${REDIS_HOST:-redis}"
_redis_port="${REDIS_PORT:-6379}"
echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP:${COLOR_RESET} Waiting for ${COLOR_LIGHT_CYAN}Redis${COLOR_RESET} at ${COLOR_CYAN}${_redis_host}:${_redis_port}${COLOR_RESET}..."
until nc -z "${_redis_host}" "${_redis_port}" 2>/dev/null; do
    echo -e "${COLOR_YELLOW}${COLOR_BOLD}NPP-WP:${COLOR_RESET} ${COLOR_LIGHT_CYAN}Redis${COLOR_RESET} is not available yet. Retrying..."
    sleep 3
done
echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP:${COLOR_RESET} ${COLOR_LIGHT_CYAN}Redis${COLOR_RESET} is ready! Proceeding..."
unset _redis_host _redis_port

# Start php-fpm
exec /usr/local/bin/docker-entrypoint.sh "$@"
