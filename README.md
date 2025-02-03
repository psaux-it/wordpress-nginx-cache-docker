# 🐋 NPP Dockerized  [![Docker Build](https://github.com/psaux-it/wordpress-nginx-cache-docker/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/psaux-it/wordpress-nginx-cache-docker/actions/workflows/docker-publish.yml)

Welcome to the Docker project optimized for the **[(NPP) WordPress Plugin](https://wordpress.org/plugins/fastcgi-cache-purge-and-preload-nginx/)**! 🎉 This is a full-stack Dockerized environment designed for **optimized use of the NPP plugin**, including **WordPress**, **PHP-FPM**, **Nginx**, **FastCGI cache**, **WP-CLI**, and necessary PHP extensions. It’s tailored to run the **NPP plugin** efficiently, providing a complete solution for **Nginx Cache** management on wordpress.

## 🔧 Features

- ✅ **WordPress** (6.7.1) with **PHP-FPM** (8.2)
- ✅ **MySQL** (9) included for database management
- ✅ **FastCGI cache** setup ready with **Nginx** (1.27.3)
- ✅ **WP-CLI** ready for plugin and theme installations
- ✅ Includes all dependencies required for the **NPP plugin**
- ✅ Isolated and secure PHP process owner for enhanced security and performance
- ✅ Built with **bindfs** (1.17.7) for FUSE-based mounting of **Nginx Cache Path**
- ✅ Supports a wide range of **PHP extensions**

## 🔑 Environment Variables

Here’s a list of the required environment variables for the setup:

### 🔒 Default Variables

These have default values and should not be changed. If you need to modify them, you must adjust other configurations accordingly.

- **NGINX_WEB_USER**: Name of the Nginx web user (default: `nginx`)
- **NGINX_WEB_UID**: UID for the Nginx web user (default: `101`)
- **NGINX_WEB_GID**: GID for the Nginx web group (default: `101`)
- **NPP_NGINX_CACHE_PATH**: Path to Nginx cache directory (default: `/var/cache/nginx`)
- **NPP_WEB_ROOT**: Web root directory (default: `/var/www/html`)

### 🛠️ User-Settable Variables

These can be changed by the user:

- **NPP_USER**: Name of the Isolated PHP process owner user (default: `npp`)
- **NPP_UID**: UID for the Isolated PHP process owner user (default: `18978`)
- **NPP_GID**: GID for the Isolated PHP process owner group (default: `33749`)

> **Note:** Ensure these variables are set before running the container. The entrypoint script will fail if any of them are missing.

## ⚙️️ Setup Instructions

### 1. Clone the repository

Start by cloning the repository to your local machine:

```bash
git clone https://github.com/psaux-it/wordpress-nginx-cache-docker.git
cd wordpress-nginx-cache-docker
```

### 2. Run the Services

Run the following command to build and start the container in detached mode:

- **Using pre-built images:**  

```bash
docker compose up -d
```

- **Building locally:**

```bash
docker compose up -d --build
```

### 🚀 **Post-Container Startup Access**
- The WordPress site can be accessed at the host machine:
  - 🔒 [https://localhost](https://localhost)
  - 🌐 [http://localhost](http://localhost)

- Default WordPress **wp-admin** login credentials:
  - **Username**: `npp`
  - **Password**: `npp`

### 🔧 **Nginx Cache Path Configuration**
- Users can use the FUSE mount path **`/var/cache/nginx-npp`** as the Nginx cache path in the NPP plugin settings page.

---
#### ⚠️ Important Notices
🚨 **The included SSL certificates are dummy, strictly for local testing** and **must not be used in production environments**.<br>
📦 This project leverages the fantastic **work** by **[Michele Locati](https://github.com/mlocati/docker-php-extension-installer)** to streamline the installation of required PHP extensions.
