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
# NPP (Nginx Cache Purge & Preload for WordPress) Dockerized entrypoint
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

# Function to wait for a service to be available
wait_for_service() {
    local host="$1"
    local port="$2"
    local retries=30
    local wait_time=5

    while ! nc -z "${host}" "${port}"; do
        if [[ "${retries}" -le 0 ]]; then
            echo -e "${COLOR_RED}${COLOR_BOLD}NPP-NGINX-FATAL:${COLOR_RESET} ${COLOR_CYAN}${host}:${port}${COLOR_RESET} is not responding. Exiting..."
            exit 1
        fi
        echo -e "${COLOR_YELLOW}${COLOR_BOLD}NPP-NGINX:${COLOR_RESET} Waiting for ${COLOR_CYAN}${host}:${port}${COLOR_RESET} to become available..."
        sleep "${wait_time}"
        retries=$((retries - 1))
    done

    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-NGINX:${COLOR_RESET} ${COLOR_CYAN}${host}:${port}${COLOR_RESET} is now available! Proceeding..."
}

# Display pre-entrypoint start message
echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-NGINX:${COLOR_RESET} ${COLOR_CYAN}${COLOR_BOLD}[Pre-Entrypoint]:${COLOR_RESET} Preparing environment before starting the ${COLOR_LIGHT_CYAN}Nginx${COLOR_RESET} service..."

# Wait for 'php-fpm' to be up
wait_for_service "wordpress" 9001

# Wait for Wordpress core Initialization to complete
wait_for_service "wordpress" 9999

# Check if required environment variables are set
for var in \
    NPP_UID \
    NPP_GID \
    NPP_USER \
    NPP_WEB_ROOT \
    NGINX_WEB_USER \
    MOUNT_DIR \
    NPP_HTTP_HOST; do
    if [[ -z "${!var:-}" ]]; then
        echo -e "${COLOR_RED}${COLOR_BOLD}NPP-NGINX-FATAL:${COLOR_RESET} Missing required environment variable: ${COLOR_LIGHT_CYAN}${var}${COLOR_RESET} - ${COLOR_RED}Exiting...${COLOR_RESET}"
        exit 1
    fi
done

# Create Isolated PHP process owner user and group on Nginx container
echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-NGINX:${COLOR_RESET} Checking PHP process owner user and group with UID ${COLOR_CYAN}${NPP_UID}${COLOR_RESET} and GID ${COLOR_CYAN}${NPP_GID}${COLOR_RESET}"
if ! getent passwd "${NPP_USER}" >/dev/null 2>&1; then
    groupadd --gid "${NPP_GID}" "${NPP_USER}"  && \
    useradd --gid "${NPP_USER}" --no-create-home --home /nonexistent --comment "Isolated PHP Process owner" --shell /bin/bash --uid "${NPP_UID}" "${NPP_USER}"
    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-NGINX:${COLOR_RESET} User ${COLOR_LIGHT_CYAN}${NPP_USER}${COLOR_RESET} created! Proceeding..."
else
    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-NGINX:${COLOR_RESET} User ${COLOR_LIGHT_CYAN}${NPP_USER}${COLOR_RESET} already exists! Proceeding..."
fi

# Add webserver-user to PHP process owner group
if ! id -nG "${NGINX_WEB_USER}" | grep -qw "${NPP_USER}"; then
    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-NGINX:${COLOR_RESET} Adding webserver-user ${COLOR_LIGHT_CYAN}${NGINX_WEB_USER}${COLOR_RESET} to PHP process owner group ${COLOR_LIGHT_CYAN}${NPP_USER}${COLOR_RESET} to give required read permissions."
    usermod -aG "${NPP_USER}" "${NGINX_WEB_USER}"
else
    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-NGINX:${COLOR_RESET} User ${COLOR_LIGHT_CYAN}${NGINX_WEB_USER}${COLOR_RESET} is already in group ${COLOR_LIGHT_CYAN}${NPP_USER}${COLOR_RESET} Skipping.."
fi

# Fix permissions for consistency
chown -R root:root /etc/nginx &&
echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-NGINX:${COLOR_RESET} Permissions fixed successfully!" ||
echo -e "${COLOR_RED}${COLOR_BOLD}NPP-NGINX:${COLOR_RESET} Failed to fix permissions!"

sleep 3

# Congratulatory Header
echo -e "\n${COLOR_YELLOW}${COLOR_BOLD}🎉 CONGRATULATIONS! 🎉${COLOR_RESET}"
echo -e "${COLOR_GREEN}${COLOR_BOLD}Unlocked Ultra-Performance with NPP${COLOR_RESET}"

# Clean separator
echo -e "\n${COLOR_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

# URL Access Information
echo -e "\n${COLOR_GREEN}${COLOR_BOLD}🔑 Access WordPress:${COLOR_RESET}"
echo -e "${COLOR_LIGHT_CYAN}URL: ${COLOR_RESET}${COLOR_BOLD}https://${NPP_HTTP_HOST}/wp-admin${COLOR_RESET}"

# Separator for credentials
echo -e "\n${COLOR_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

# Default credentials
echo -e "\n${COLOR_GREEN}${COLOR_BOLD}📝 Default Credentials:${COLOR_RESET}"
echo -e "${COLOR_LIGHT_CYAN}Username: ${COLOR_RESET}${COLOR_BOLD}${NPP_USER}${COLOR_RESET}"
echo -e "${COLOR_LIGHT_CYAN}Password: ${COLOR_RESET}${COLOR_BOLD}${NPP_USER}${COLOR_RESET}"

# Separator for cache path
echo -e "\n${COLOR_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

# Default Nginx cache path
echo -e "\n${COLOR_GREEN}${COLOR_BOLD}💾 Nginx Cache Path:${COLOR_RESET}"
echo -e "${COLOR_LIGHT_CYAN}Path: ${COLOR_RESET}${COLOR_BOLD}${MOUNT_DIR}${COLOR_RESET}"

# Separator for author message
echo -e "\n${COLOR_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

# Universal Author messaege
echo -e "\n${COLOR_RED}${COLOR_BOLD}☪︎${COLOR_RESET} ${COLOR_GREEN}${COLOR_BOLD}Author Message:${COLOR_RESET}"
echo -e "${COLOR_LIGHT_CYAN}Message: ${COLOR_RESET}${COLOR_BOLD}1.f3 e5 2.g4 Qh4# ~checkmate${COLOR_RESET}"

# Final separator
echo -e "\n${COLOR_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

# Start nginx
exec /docker-entrypoint.sh "$@"
