# Custom Dockerfile for Nginx
FROM nginx:latest

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
