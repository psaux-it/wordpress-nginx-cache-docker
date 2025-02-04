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

# Function to wait for a service to be available
wait_for_service() {
    local host="$1"
    local port="$2"
    local retries=30
    local wait_time=15

    while ! nc -z "${host}" "${port}"; do
        if [[ "${retries}" -le 0 ]]; then
            echo -e "${COLOR_RED}${COLOR_BOLD}NPP-WP-CLI-FATAL:${COLOR_RESET} ${COLOR_CYAN}${host}:${port}${COLOR_RESET} is not responding. Exiting..."
            exit 1
        fi
        echo -e "${COLOR_YELLOW}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} Waiting for ${COLOR_CYAN}${host}:${port}${COLOR_RESET} to become available..."
        sleep "$wait_time"
        retries=$((retries - 1))
    done

    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} ${COLOR_CYAN}${host}:${port}${COLOR_RESET} is now available! Proceeding..."
}

# Display pre-entrypoint start message
echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} ${COLOR_CYAN}${COLOR_BOLD}[POST-START]:${COLOR_RESET} Initialization of ${COLOR_CYAN}Core WordPress${COLOR_RESET} has started.."

# Check if required environment variables are set
for var in \
    NPP_USER \
    NPP_UID \
    NPP_GID \
    WORDPRESS_DB_USER \
    WORDPRESS_DB_PASSWORD \
    WORDPRESS_DB_NAME \
    NPP_WEB_ROOT \
    WORDPRESS_SITE_URL \
    WORDPRESS_SITE_TITLE \
    WORDPRESS_ADMIN_USER \
    WORDPRESS_ADMIN_PASSWORD \
    WORDPRESS_ADMIN_EMAIL; do
    if [[ -z "${!var:-}" ]]; then
        echo -e "${COLOR_RED}${COLOR_BOLD}NPP-WP-CLI-FATAL:${COLOR_RESET} Missing required environment variable: ${COLOR_LIGHT_CYAN}${var}${COLOR_RESET}. ${COLOR_RED}Exiting...${COLOR_RESET}"
        exit 1
    fi
done

# Wait for 'wordpress-fpm' container with 'fpm' up
# We need to sure '/var/www/html' exists for 'wp-cli'
wait_for_service "wordpress" 9001

# Check ownership of webroot for consistency
check_ownership() {
    while IFS=" " read -r owner group file; do
        if [[ "${owner}" != "${NPP_USER}" || "$group" != "${NPP_USER}" ]]; then
            return 1
        fi
    done < <(find "${NPP_WEB_ROOT}" -printf "%u %g %p\n" 2>/dev/null)
    return 0
}

# Check permissions of webroot to ensure proper isolation for 'others'
check_permissions() {
    while IFS=" " read -r perms file; do
        others_perm="${perms:8:1}${perms:9:1}${perms:10:1}"
        if [[ "${others_perm}" != "---" ]]; then
            return 1
        fi
    done < <(find "${NPP_WEB_ROOT}" -exec ls -ld {} + 2>/dev/null)
    return 0
}

# Own website with Isolated PHP process owner user 'npp'
if ! check_ownership; then
    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} Setting ownership of ${COLOR_LIGHT_CYAN}${NPP_WEB_ROOT}${COLOR_RESET} to user/group ${COLOR_LIGHT_CYAN}${NPP_USER}${COLOR_RESET} with UID ${COLOR_CYAN}${NPP_UID}${COLOR_RESET} and GID ${COLOR_CYAN}${NPP_GID}${COLOR_RESET}."
    chown -R "${NPP_UID}":"${NPP_GID}" "${NPP_WEB_ROOT}"
else
    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} Ownership of ${COLOR_LIGHT_CYAN}${NPP_WEB_ROOT}${COLOR_RESET} is already properly set."
fi

# Set proper permission to restrict environment for 'others'
if ! check_permissions; then
    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} Setting permissions for ${COLOR_LIGHT_CYAN}${NPP_WEB_ROOT}${COLOR_RESET} to completely isolate the environment."
    chmod -R u=rwX,g=rX,o= "${NPP_WEB_ROOT}"
else
    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} Permission for ${COLOR_LIGHT_CYAN}${NPP_WEB_ROOT}${COLOR_RESET} is already properly set."
fi

# Install core WordPress
echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} Initiating Core WordPress installation and configuration..."

# Set the WP_CLI_CACHE_DIR before calling su
export WP_CLI_CACHE_DIR="${NPP_WEB_ROOT}/.wp-cli/cache"

# Check if core WordPress is already installed
if ! su -m -c "wp core is-installed" ${NPP_USER} >/dev/null 2>&1; then
    # Install WordPress if not installed
    if su -m -c "wp core install --url=\"${WORDPRESS_SITE_URL}\" \
                                 --title=\"${WORDPRESS_SITE_TITLE}\" \
                                 --admin_user=\"${WORDPRESS_ADMIN_USER}\" \
                                 --admin_password=\"${WORDPRESS_ADMIN_PASSWORD}\" \
                                 --admin_email=\"${WORDPRESS_ADMIN_EMAIL}\"" ${NPP_USER} >/dev/null 2>&1; then
        echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} ${COLOR_CYAN}WordPress core${COLOR_RESET} has been successfully installed."
    else
        echo -e "${COLOR_RED}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} ${COLOR_CYAN}WordPress core${COLOR_RESET} installation failed. Please check the logs for more details."
    fi
else
    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} ${COLOR_CYAN}WordPress core${COLOR_RESET} is already installed. Skipping..."
fi

# Normalize user input (Trim spaces around commas and the entire string)
NPP_PLUGINS_CLEANED=$(echo "${NPP_PLUGINS}" | sed -E 's/[[:space:]]*,[[:space:]]*/,/g' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
NPP_THEMES_CLEANED=$(echo "${NPP_THEMES}" | sed -E 's/[[:space:]]*,[[:space:]]*/,/g' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')

# Convert the cleaned string into an array
IFS=',' read -r -a NPP_PLUGINS <<< "${NPP_PLUGINS_CLEANED}"
IFS=',' read -r -a NPP_THEMES <<< "${NPP_THEMES_CLEANED}"

# Install Plugins
if [[ "${#NPP_PLUGINS[@]}" -gt 0 ]]; then
    for plugin in "${NPP_PLUGINS[@]}"; do
        if ! su -m -c "wp plugin is-installed \"${plugin}\"" ${NPP_USER} >/dev/null 2>&1; then
            if su -m -c "wp plugin install \"${plugin}\" --activate" ${NPP_USER} >/dev/null 2>&1; then
                echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} Plugin ${COLOR_CYAN}${plugin}${COLOR_RESET} has been installed and activated."
            else
                echo -e "${COLOR_RED}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} Plugin ${COLOR_CYAN}${plugin}${COLOR_RESET} installation failed. Please check the logs for more details."
            fi
        else
            echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} Plugin ${COLOR_CYAN}${plugin}${COLOR_RESET} is already installed."
        fi
    done
else
    echo -e "${COLOR_YELLOW}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} ${COLOR_CYAN}No plugins${COLOR_RESET} to install."
fi

# Install Themes
if [[ "${#NPP_THEMES[@]}" -gt 0 ]]; then
    for theme in "${NPP_THEMES[@]}"; do
        if ! su -m -c "wp theme is-installed \"${theme}\"" ${NPP_USER} >/dev/null 2>&1; then
            if su -m -c "wp theme install \"${theme}\" --activate" ${NPP_USER} >/dev/null 2>&1; then
                echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} Theme ${COLOR_CYAN}${theme}${COLOR_RESET} has been installed and activated."
            else
                echo -e "${COLOR_RED}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} Theme ${COLOR_CYAN}${theme}${COLOR_RESET} installation failed. Please check the logs for more details."
            fi
        else
            echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} Theme ${COLOR_CYAN}${theme}${COLOR_RESET} is already installed."
        fi
    done
else
    echo -e "${COLOR_YELLOW}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} ${COLOR_CYAN}No themes${COLOR_RESET} to install."
fi

# Listen on dummy port for 'nginx' container health check
echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} Starting to listen on dummy port ${COLOR_CYAN}9999${COLOR_RESET}..."
if ! nc -zv 127.0.0.1 9999 2>/dev/null; then
    nc -lk -p 9999 >/dev/null 2>&1 &
fi
