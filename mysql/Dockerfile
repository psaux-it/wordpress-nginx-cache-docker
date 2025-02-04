# Custom Dockerfile for mysql
FROM mysql:latest

# Install necessary packages
RUN apt-get update && apt-get install -y \
    procps

# Copy the entrypoint script into the container
COPY mysql/entrypoint-sql.sh /entrypoint-sql.sh

# Make sure the entrypoint script is executable
RUN chmod +x /entrypoint-sql.sh

# Default command
CMD ["/bin/bash", "/entrypoint-sql.sh", "mysqld"]
