# Dockerfile for NPP-Optimized WordPress Setup                                     #
# ----------------------------------------------------------------------------     #
# Author: [Hasan ÇALIŞIR]                                                          #
# Purpose: Full-stack Dockerized environment for NPP WordPress plugin, including   #
#          WordPress, PHP-FPM, Nginx, MySQL, WP-CLI, and necessary PHP extensions. #
# ----------------------------------------------------------------------------     #

# Here the magic, the rest of it is ordinary
FROM mysql:8.0.44-bookworm

# Install necessary packages
RUN apt-get update && apt-get install -y \
    procps

# Copy the entrypoint script into the container
COPY mysql/entrypoint-sql.sh /entrypoint-sql.sh

# Make sure the entrypoint script is executable
RUN chmod +x /entrypoint-sql.sh

# CMD
CMD ["/entrypoint-sql.sh", "mysqld"]
