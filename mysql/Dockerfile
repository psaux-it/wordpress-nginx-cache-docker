# Custom Dockerfile for mysql
FROM mysql:8.0.41-bookworm

# Install necessary packages
RUN apt-get update && apt-get install -y \
    procps

# Copy the entrypoint script into the container
COPY mysql/entrypoint-sql.sh /entrypoint-sql.sh

# Make sure the entrypoint script is executable
RUN chmod +x /entrypoint-sql.sh

# CMD
CMD ["/entrypoint-sql.sh", "mysqld"]
