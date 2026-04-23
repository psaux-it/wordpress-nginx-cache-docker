# Dockerfile for NPP-Optimized WordPress Setup                                     #
# ----------------------------------------------------------------------------     #
# Author: [Hasan ÇALIŞIR]                                                          #
# Purpose: Full-stack Dockerized environment for NPP WordPress plugin, including   #
#          WordPress, PHP-FPM, Nginx, MySQL, WP-CLI, and necessary PHP extensions. #
# ----------------------------------------------------------------------------     #

# Here the magic, the rest of it is ordinary
FROM mysql:9.7.0

# Install necessary packages
RUN microdnf install -y procps-ng && \
    microdnf clean all

# Copy the entrypoint script into the container
COPY mysql/entrypoint-sql.sh /entrypoint-sql.sh

# Make sure the entrypoint script is executable
RUN chmod +x /entrypoint-sql.sh

# CMD
CMD ["/entrypoint-sql.sh", "mysqld"]
