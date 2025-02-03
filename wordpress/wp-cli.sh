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
    local wait_time=5

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
echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} ${COLOR_CYAN}${COLOR_BOLD}[POST-START]:${COLOR_RESET} Initialization of ${COLOR_CYAN}WordPress${COLOR_RESET} has started.."

# Check if required environment variables are set
for var in \
    NPP_USER \
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

echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} Initiating WordPress installation and configuration..."
# Install WordPress in the background after the container starts
if ! wp core is-installed --allow-root >/dev/null 2>&1; then
    if wp core install --url="${WORDPRESS_SITE_URL}" \
                       --title="${WORDPRESS_SITE_TITLE}" \
                       --admin_user="${WORDPRESS_ADMIN_USER}" \
                       --admin_password="${WORDPRESS_ADMIN_PASSWORD}" \
                       --admin_email="${WORDPRESS_ADMIN_EMAIL}" \
                       --allow-root >/dev/null 2>&1; then
        echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} WordPress has been successfully installed."
    else
        echo -e "${COLOR_RED}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} WordPress installation failed. Please check the logs for more details."
    fi
else
    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} WordPress is already installed. Skipping installation." >/tmp/wp_cli.log 2>&1
fi

# Trim spaces around commas and the entire string
NPP_PLUGINS_CLEANED=$(echo "${NPP_PLUGINS}" | sed -E 's/[[:space:]]*,[[:space:]]*/,/g' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
NPP_THEMES_CLEANED=$(echo "${NPP_THEMES}" | sed -E 's/[[:space:]]*,[[:space:]]*/,/g' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')

# Convert the cleaned string into an array
IFS=',' read -r -a NPP_PLUGINS <<< "${NPP_PLUGINS_CLEANED}"
IFS=',' read -r -a NPP_THEMES <<< "${NPP_THEMES_CLEANED}"

# Install Plugins
if [[ "${#NPP_PLUGINS[@]}" -gt 0 ]]; then
    for plugin in "${NPP_PLUGINS[@]}"; do
        if ! wp plugin is-installed "${plugin}" --allow-root >/dev/null 2>&1; then
            if wp plugin install "${plugin}" --activate --allow-root >/dev/null 2>&1; then
                echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} Plugin ${COLOR_CYAN}${plugin}${COLOR_RESET} has been installed and activated."
            else
                echo -e "${COLOR_RED}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} Plugin ${COLOR_CYAN}${plugin}${COLOR_RESET} installation failed. Please check the logs for more details."
            fi
        else
            echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} Plugin ${COLOR_CYAN}${plugin}${COLOR_RESET} is already installed." >/tmp/wp_cli.log 2>&1
        fi
    done
else
    echo -e "${COLOR_YELLOW}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} No plugins to install." > /tmp/wp_cli.log 2>&1
fi

# Install Themes
if [[ "${#NPP_THEMES[@]}" -gt 0 ]]; then
    for theme in "${NPP_THEMES[@]}"; do
        if ! wp theme is-installed "${theme}" --allow-root >/dev/null 2>&1; then
            if wp theme install "${theme}" --activate --allow-root >/dev/null 2>&1; then
                echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} Theme ${COLOR_CYAN}${theme}${COLOR_RESET} has been installed and activated."
            else
                echo -e "${COLOR_RED}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} Theme ${COLOR_CYAN}${theme}${COLOR_RESET} installation failed. Please check the logs for more details."
            fi
        else
            echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} Theme ${COLOR_CYAN}${theme}${COLOR_RESET} is already installed." >/tmp/wp_cli.log 2>&1
        fi
    done
else
    echo -e "${COLOR_YELLOW}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} No themes to install." >/tmp/wp_cli.log 2>&1
fi

# Start to listen dummy port
echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} Starting to listen on dummy port ${COLOR_CYAN}9999${COLOR_RESET}..."
nc -lk -p 9999 > /dev/null 2>&1 &
