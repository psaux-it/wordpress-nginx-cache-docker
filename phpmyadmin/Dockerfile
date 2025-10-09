# Dockerfile for NPP-Optimized WordPress Setup                                     #
# ----------------------------------------------------------------------------     #
# Author: [Hasan ÇALIŞIR]                                                          #
# Purpose: Full-stack Dockerized environment for NPP WordPress plugin, including   #
#          WordPress, PHP-FPM, Nginx, MySQL, WP-CLI, and necessary PHP extensions. #
# ----------------------------------------------------------------------------     #

# Here the magic, the rest of it is ordinary
FROM phpmyadmin:5.2.3-apache

# Install necessary packages
RUN apt-get update && apt-get install -y \
    procps \
    mariadb-client

# Copy the entrypoint script into the container
COPY phpmyadmin/entrypoint-pma.sh /entrypoint-pma.sh

# Make sure the entrypoint script is executable
RUN chmod +x /entrypoint-pma.sh

# CMD
CMD ["/entrypoint-pma.sh", "apache2-foreground"]
