# 🐋 NPP Dockerized 

Welcome to the Docker project for **testing** the **[FastCGI Cache Purge and Preload for Nginx (NPP) WordPress Plugin](https://wordpress.org/plugins/fastcgi-cache-purge-and-preload-nginx/)**! 🎉 This Dockerized environment is designed exclusively for **testing and development purposes** and **is not intended for production deployment**. Below you will find everything you need to get started with testing the plugin in a containerized environment.

## 🔧 Features

- ✅ WordPress **(6.7.1)** with PHP-FPM **(8.2)**
- ✅ **FastCGI** cache setup ready with **Nginx (1.27.3)**
- ✅ Includes all dependencies required for the **NPP** plugin
- ✅ Isolated and secure **PHP process owner** for enhanced security and performance
- ✅ Built with **bindfs (1.17.7)** for FUSE-based mounting of **Nginx Cache Path** 
- ✅ Supports a wide range of PHP extensions

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
git clone https://github.com/psaux-it/npp-wordpress.git
cd npp-wordpress
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
- Users can use the FUSE mount path **`/var/cache/nginx-mnt`** as the Nginx cache path in the NPP plugin settings page.
- The WordPress site can be accessed at host machine:
  - 🔒 [https://localhost:8443/](https://localhost:8443/)
  - 🌐 [http://localhost:8080/](http://localhost:8080/)
