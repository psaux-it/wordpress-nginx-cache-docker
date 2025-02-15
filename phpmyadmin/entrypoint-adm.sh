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

# Check if required environment variables are set
for var in \
    WORDPRESS_DB_USER \
    WORDPRESS_DB_PASSWORD \
    WORDPRESS_DB_NAME; do
    if [[ -z "${!var:-}" ]]; then
        echo -e "${COLOR_RED}${COLOR_BOLD}NPP-WP-FATAL:${COLOR_RESET} Missing required environment variable(s): ${COLOR_LIGHT_CYAN}${var}${COLOR_RESET} - ${COLOR_RED}Exiting...${COLOR_RESET}"
        exit 1
    fi
done

# Wait for the 'wordpress-db' to be ready
until mysql -h wordpress-db -u"${WORDPRESS_DB_USER}" -p"${WORDPRESS_DB_PASSWORD}" "${WORDPRESS_DB_NAME}" -e "SELECT 1" > /dev/null 2>&1; do
    echo -e "${COLOR_YELLOW}${COLOR_BOLD}NPP-ADM:${COLOR_RESET} The ${COLOR_LIGHT_CYAN}MySQL database${COLOR_RESET} is not available yet. Retrying..."
    sleep 6
done
echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-ADM:${COLOR_RESET} The ${COLOR_LIGHT_CYAN}MySQL database${COLOR_RESET} is ready! Proceeding..."

# Start Apache
exec /docker-entrypoint.sh "$@"
