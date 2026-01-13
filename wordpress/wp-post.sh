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
            echo -e "${COLOR_RED}${COLOR_BOLD}NPP-WP-FATAL:${COLOR_RESET} ${COLOR_CYAN}${host}:${port}${COLOR_RESET} is not responding. Exiting..."
            exit 1
        fi
        echo -e "${COLOR_YELLOW}${COLOR_BOLD}NPP-WP:${COLOR_RESET} Waiting for ${COLOR_CYAN}${host}:${port}${COLOR_RESET} to become available..."
        sleep "$wait_time"
        retries=$((retries - 1))
    done

    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP:${COLOR_RESET} ${COLOR_CYAN}${host}:${port}${COLOR_RESET} is now available! Proceeding..."
}

# Display pre-entrypoint start message
echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP:${COLOR_RESET} ${COLOR_CYAN}${COLOR_BOLD}[POST-START]:${COLOR_RESET} Starting post-start operations for ${COLOR_CYAN}NPP Dockerized${COLOR_RESET}..."

# Check if required environment variables are set
for var in \
    NPP_USER \
    NPP_UID \
    NPP_GID \
    NPP_EDGE \
    NPP_HTTP_HOST \
    NPP_HACK_HOST \
    NPP_WEB_ROOT \
    NPP_DEV_PLUGIN_NAME \
    NPP_DEV_PLUGIN_DIR \
    NPP_DEV_TMP_CLONE_DIR \
    NPP_DEV_PLUGIN_FILE \
    NPP_DEV_GITHUB_REPO \
    WORDPRESS_DB_USER \
    WORDPRESS_DB_PASSWORD \
    WORDPRESS_DB_NAME \
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

# Resolve host
resolve_host() {
    local host="$1"
    local ipv4=""
    local ip_fallback=""
    local result=()

    # Try to get IPv4 address
    ipv4="$(ping -4 -c 1 "$host" | grep -oP '(?<=\()[^)]+' | head -n 1)"

    # Fallback to find IP
    ip_fallback="$(getent hosts "${host}" | awk '{ print $1 }')"

    # No IP found
    if [[ -z "${ipv4}" && -z "${ip_fallback}" ]]; then
        return 1
    # If both IPv4 and fallback IP are found
    elif [[ -n "${ipv4}" && -n "${ip_fallback}" ]]; then
        if [[ "${ipv4}" == "${ip_fallback}" ]]; then
            # If both IPs are equal, return only one
            result+=("${ipv4}")
        else
            # If both IPs are different, return both
            result+=("${ipv4}")
            result+=("${ip_fallback}")
        fi
    # If only one IP is found
    elif [[ -n "${ipv4}" ]]; then
        result+=("${ipv4}")
    else
        result+=("${ip_fallback}")
    fi

    printf "%s\n" "${result[@]}"
}

# To enable NPP Plugin Nginx Cache Preload action:
# ##################################################################################################################
# The NPP WordPress plugin uses "wget" with "WP_SITEURL" from inside the WordPress container to Preload Nginx Cache.
# This means that if "WP_SITEURL" is set to "localhost", wget will attempt to fetch URLs from
# the containers own loopback interface rather than reaching the Nginx server that handles
# Cache Preload requests.
#
# To handle that;
#
# Development Environments:
#   - During "wp core install", the "--url" parameter is hardcoded as "https://localhost",
#     so WP_SITEURL ends up being "https://localhost" within the container.
#   - In this scenario, Nginx Cache Preload requests will try to access "https://localhost", which
#     incorrectly refers to the wordpress container itself.
#   - To work around this, we update the wordpress containers "/etc/hosts" file to remap "localhost" to either
#     "host.docker.internal" or the actual "Nginx container IP". This forces to retrieve resources
#     from the correct endpoint, enabling the Nginx Cache Preload action during development.
#   - Keep in mind! Below settings will not work in dev environment because of the priority issue in /etc/hosts
#     extra_hosts:
#       - "localhost:Nginx_LAN_IP"
#
# Production Environment:
#   - WP_SITEURL is typically set to an FQDN (example.com) pointing to Nginx.
#   - If the WordPress container has WAN access, can resolve external domains, and allows outgoing traffic,
#     Cache Preload requests will correctly reach Nginx over the WAN route.
#   - If the wordpress container lacks WAN access, external DNS resolution, or outgoing traffic:
#     - WP_SITEURL (example.com) must resolve internally to Nginx LAN IP. (Nginx can sits on host or as a container)
#     - Solutions:
#       1. Internal DNS resolver mapping WP_SITEURL to Nginx's LAN IP.
#       2. Manually adding WP_SITEURL to /etc/hosts inside the wordpress container.
#       3. Recommended docker way, edit wordpress service in docker-compose.yml,
#          extra_hosts:
#            - "example.com:Nginx_LAN_IP"
###################################################################################################################
if [[ "${NPP_HACK_HOST}" -eq 1 ]]; then
    # Create array
    mapfile -t ip_array < <(resolve_host host.docker.internal)

    # Create temporary file
    TEMP_HOSTS="$(mktemp /tmp/hosts.XXXXXX)"
    HOSTS="/etc/hosts"

    # Hack /etc/hosts kindly, not make container upset
    # Map to host.docker.internal
    if (( ${#ip_array[@]} )); then
        for IP in "${ip_array[@]}"; do
            echo "${IP} ${NPP_HTTP_HOST}" >> "${TEMP_HOSTS}"
        done

        cat "${HOSTS}" >> "${TEMP_HOSTS}"
        cat "${TEMP_HOSTS}" > "${HOSTS}"
        echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP:${COLOR_RESET} ${COLOR_RED}Hacked!${COLOR_RESET} Mapped ${COLOR_LIGHT_CYAN}${NPP_HTTP_HOST}${COLOR_RESET} to host.docker.internal ${COLOR_LIGHT_CYAN}${ip_array[@]}${COLOR_RESET} in ${COLOR_LIGHT_CYAN}${HOSTS}${COLOR_RESET}."
    fi
fi
####################################################################################################################

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
    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP:${COLOR_RESET} Setting ownership of ${COLOR_LIGHT_CYAN}${NPP_WEB_ROOT}${COLOR_RESET} to user/group ${COLOR_LIGHT_CYAN}${NPP_USER}${COLOR_RESET} with UID ${COLOR_CYAN}${NPP_UID}${COLOR_RESET} and GID ${COLOR_CYAN}${NPP_GID}${COLOR_RESET}."
    chown -R "${NPP_UID}":"${NPP_GID}" "${NPP_WEB_ROOT}"
else
    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP:${COLOR_RESET} Ownership of ${COLOR_LIGHT_CYAN}${NPP_WEB_ROOT}${COLOR_RESET} is already properly set."
fi

# Set proper permission to restrict environment for 'others'
if ! check_permissions; then
    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP:${COLOR_RESET} Setting permissions for ${COLOR_LIGHT_CYAN}${NPP_WEB_ROOT}${COLOR_RESET} to completely isolate the environment."
    chmod -R u=rwX,g=rX,o= "${NPP_WEB_ROOT}"
else
    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP:${COLOR_RESET} Permission for ${COLOR_LIGHT_CYAN}${NPP_WEB_ROOT}${COLOR_RESET} is already properly set."
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
            echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} Plugin ${COLOR_CYAN}${plugin}${COLOR_RESET} is already installed. Skipping..."
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
            echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} Theme ${COLOR_CYAN}${theme}${COLOR_RESET} is already installed. Skipping..."
        fi
    done
else
    echo -e "${COLOR_YELLOW}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} ${COLOR_CYAN}No themes${COLOR_RESET} to install."
fi

# Check if the current permalink structure is already set
CURRENT_PERMALINK=$(su -m -c "wp option get permalink_structure" "${NPP_USER}")
if [[ -z "$CURRENT_PERMALINK" || "$CURRENT_PERMALINK" == "/index.php/%pagename%/" ]]; then
    # Apply the new permalink structure
    if su -m -c "wp rewrite structure '/%postname%/' --hard" "${NPP_USER}" >/dev/null 2>&1; then
        echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} ${COLOR_CYAN}Permalink structure${COLOR_RESET} has been successfully updated."
    else
        echo -e "${COLOR_RED}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} ${COLOR_CYAN}Failed to update${COLOR_RESET} permalink structure. Please check logs for more details."
    fi
else
    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP-CLI:${COLOR_RESET} ${COLOR_CYAN}Permalink structure${COLOR_RESET} is already properly set. Skipping..."
fi

# Deploy bleeding edge NPP
if [[ "${NPP_EDGE}" -eq 1 ]]; then
    # Set variables
    PLUGIN_NAME="${NPP_DEV_PLUGIN_NAME}"
    PLUGIN_DIR="${NPP_DEV_PLUGIN_DIR}"
    TMP_CLONE_DIR="${NPP_DEV_TMP_CLONE_DIR}"
    PLUGIN_FILE="${NPP_DEV_PLUGIN_FILE}"
    GITHUB_REPO="${NPP_DEV_GITHUB_REPO}"

    # -----------------------------------------------------------------------------
    # 1. Fetch latest development branch details from GitHub
    # -----------------------------------------------------------------------------
    TARGET_BRANCH=$(git ls-remote --heads "${GITHUB_REPO}" \
        | awk '{print $2}' \
        | sed 's#refs/heads/##' \
        | grep '^v[0-9]' \
        | sort -V \
        | tail -n1 \
        | awk '{$1=$1;print}')

    LATEST_VERSION="${TARGET_BRANCH#v}"
    REMOTE_COMMIT_HASH=$(git ls-remote --heads "${GITHUB_REPO}" "refs/heads/${TARGET_BRANCH}" \
      | awk '{print substr($1,1,7)}' | awk '{$1=$1;print}')

    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-EDGE:${COLOR_RESET} ${COLOR_LIGHT_CYAN}######################${COLOR_RESET}"
    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-EDGE:${COLOR_RESET} Latest branch: ${COLOR_CYAN}${TARGET_BRANCH}${COLOR_RESET}"
    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-EDGE:${COLOR_RESET} Latest dev version: ${COLOR_CYAN}${LATEST_VERSION}${COLOR_RESET}"
    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-EDGE:${COLOR_RESET} Remote commit: ${COLOR_CYAN}${REMOTE_COMMIT_HASH}${COLOR_RESET}"
    echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-EDGE:${COLOR_RESET} ${COLOR_LIGHT_CYAN}######################${COLOR_RESET}"

    # -----------------------------------------------------------------------------
    # 2. Retrieve the installed plugin version and commit hash
    # -----------------------------------------------------------------------------
    CURRENT_VERSION="0.0.0"
    INSTALLED_COMMIT_HASH=""

    if [[ -f "${PLUGIN_FILE}" ]]; then
        CURRENT_VERSION=$(grep -i "Version:" "${PLUGIN_FILE}" | head -n1 | awk '{print $NF}' | awk '{$1=$1;print}')
        echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-EDGE:${COLOR_RESET} Local version: ${COLOR_CYAN}${CURRENT_VERSION}${COLOR_RESET}"
        if grep -qi "Latest Commit:" "${PLUGIN_FILE}"; then
            INSTALLED_COMMIT_HASH=$(grep -i "Latest Commit:" "${PLUGIN_FILE}" | head -n1 | awk '{print $NF}' | awk '{$1=$1;print}')
            echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-EDGE:${COLOR_RESET} Local commit: ${COLOR_CYAN}${INSTALLED_COMMIT_HASH}${COLOR_RESET}"
        else
            echo -e "${COLOR_YELLOW}${COLOR_BOLD}NPP-EDGE:${COLOR_RESET} ${COLOR_CYAN}No commit history${COLOR_RESET} in plugin header."
        fi
    else
        echo -e "${COLOR_YELLOW}${COLOR_BOLD}NPP-EDGE:${COLOR_RESET} Plugin not installed; proceeding with fresh deployment."
    fi

    # -----------------------------------------------------------------------------
    # 3. Determine if an update is required
    # -----------------------------------------------------------------------------
    need_update=0

    if [[ -f "${PLUGIN_FILE}" ]]; then
        # Check for version mismatch (installed version is older than latest)
        if [[ "${CURRENT_VERSION}" != "${LATEST_VERSION}" && \
              "$(echo -e "${CURRENT_VERSION}\n${LATEST_VERSION}" | sort -V | head -n1)" != "${LATEST_VERSION}" ]]; then
            echo -e "${COLOR_YELLOW}${COLOR_BOLD}NPP-EDGE:${COLOR_RESET} Version discrepancy found..."
            need_update=1
        fi

        # Check for commit hash mismatch
        if [[ "${INSTALLED_COMMIT_HASH}" != "${REMOTE_COMMIT_HASH}" ]]; then
            echo -e "${COLOR_YELLOW}${COLOR_BOLD}NPP-EDGE:${COLOR_RESET} Commit hash discrepancy found..."
            need_update=1
        fi
    else
        need_update=1
    fi

    # -----------------------------------------------------------------------------
    # 4. Deploy/update the plugin if required
    # -----------------------------------------------------------------------------
    if [[ "${need_update}" -eq 1 ]]; then
        echo -e "${COLOR_YELLOW}${COLOR_BOLD}NPP-EDGE:${COLOR_RESET} Deploying development build ${COLOR_CYAN}${LATEST_VERSION}${COLOR_RESET}..."

        # Remove the current plugin directory (if it exists)
        rm -rf "${PLUGIN_DIR:?}"

        # Clone the target branch into a temporary directory
        mkdir -p "${TMP_CLONE_DIR:?}" && cd "${TMP_CLONE_DIR:?}"
        git clone --branch "${TARGET_BRANCH:?}" "${GITHUB_REPO:?}" . >/dev/null 2>&1

        # Fix line-ending issues
        find "${TMP_CLONE_DIR:?}" -type f -exec dos2unix {} + >/dev/null 2>&1

        # Retrieve the commit hash from the clone
        CLONED_COMMIT_HASH=$(git rev-parse --short HEAD)

        # Move the cloned files to the plugin directory and clean up
        mv "${TMP_CLONE_DIR:?}" "${PLUGIN_DIR:?}"
        rm -rf "${TMP_CLONE_DIR:?}" >/dev/null 2>&1
        rm -rf "${PLUGIN_DIR:?}/.git" >/dev/null 2>&1
        rm -f "${PLUGIN_DIR:?}/README.md" "${PLUGIN_DIR:?}/version" >/dev/null 2>&1

        # Update the plugin header: Version and Latest Commit
        if [[ -f "${PLUGIN_FILE}" ]]; then
            sed -i "s/^\(\s*\*\s*Version:\s*\).*$/\1${LATEST_VERSION}/" "${PLUGIN_FILE}"
            if grep -qi "Latest Commit:" "${PLUGIN_FILE}"; then
                sed -i "s/^\(\s*\*\s*Latest Commit:\s*\).*$/\1${CLONED_COMMIT_HASH}/" "${PLUGIN_FILE}"
                echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-EDGE:${COLOR_RESET} Updated plugin header commit hash to ${COLOR_CYAN}${CLONED_COMMIT_HASH}${COLOR_RESET}"
            else
                sed -i "/Version:/a \ * Latest Commit:     ${CLONED_COMMIT_HASH}" "${PLUGIN_FILE}"
                echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-EDGE:${COLOR_RESET} Added commit hash ${COLOR_CYAN}${CLONED_COMMIT_HASH}${COLOR_RESET} to plugin header."
            fi
        fi

        # Adjust ownership (ensure NPP_USER is set in the environment)
        chown -R "${NPP_USER}":"${NPP_USER}" "${PLUGIN_DIR}"
        echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-EDGE:${COLOR_RESET} Deployed build ${COLOR_CYAN}${TARGET_BRANCH}${COLOR_RESET} with (commit ${COLOR_CYAN}${CLONED_COMMIT_HASH}${COLOR_RESET})."
        echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-EDGE:${COLOR_RESET} ${COLOR_LIGHT_CYAN}######################${COLOR_RESET}"
    else
        echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-EDGE:${COLOR_RESET} Plugin is up-to-date with commit ${COLOR_CYAN}${REMOTE_COMMIT_HASH}${COLOR_RESET}."
        echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-EDGE:${COLOR_RESET} ${COLOR_LIGHT_CYAN}######################${COLOR_RESET}"
    fi
fi

# Listen on dummy port for 'nginx' container health check
echo -e "${COLOR_GREEN}${COLOR_BOLD}NPP-WP:${COLOR_RESET} Starting to listen on dummy port ${COLOR_CYAN}9999${COLOR_RESET}..."
if ! nc -zv 127.0.0.1 9999 2>/dev/null; then
    nohup nc -l -p 9999 >/dev/null 2>&1 &
fi
