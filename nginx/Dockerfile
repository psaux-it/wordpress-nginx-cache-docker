# Dockerfile for NPP-Optimized WordPress Setup                                     #
# ----------------------------------------------------------------------------     #
# Author: [Hasan ÇALIŞIR]                                                          #
# Purpose: Full-stack Dockerized environment for NPP WordPress plugin, including   #
#          WordPress, PHP-FPM, Nginx, MySQL, WP-CLI, and necessary PHP extensions. #
# ----------------------------------------------------------------------------     #

# Here the magic, the rest of it is ordinary
FROM nginx:1.29.1-bookworm

# Install necessary packages
RUN apt-get update && apt-get install -y \
    netcat-traditional \
    procps

# Copy the entrypoint script into the container
COPY nginx/entrypoint-nginx.sh /entrypoint-nginx.sh

# Make sure the entrypoint script is executable
RUN chmod +x /entrypoint-nginx.sh

# CMD
CMD ["/entrypoint-nginx.sh", "nginx", "-g", "daemon off;"]
