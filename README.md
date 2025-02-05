# 🐳 NPP Dockerized  [![Docker Build](https://github.com/psaux-it/wordpress-nginx-cache-docker/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/psaux-it/wordpress-nginx-cache-docker/actions/workflows/docker-publish.yml)

Welcome to the Docker project optimized for the **[(NPP) WordPress Plugin](https://wordpress.org/plugins/fastcgi-cache-purge-and-preload-nginx/)**! 🎉 This is a full-stack Dockerized environment designed for **optimized use of the NPP plugin**, including **WordPress**, **PHP-FPM**, **Nginx**, **FastCGI cache**, **WP-CLI**, and necessary PHP extensions. It’s tailored to run the **NPP plugin** efficiently, providing a complete solution for **Nginx Cache** management on wordpress.

Explore the **[NPP Main GitHub Repository](https://github.com/psaux-it/nginx-fastcgi-cache-purge-and-preload)** to access the heart of the plugin development.

## 🔧 Features

- ✅ **WordPress** (6.7.1) with **PHP-FPM** (8.2)
- ✅ **MySQL** (8) for database management
- ✅ **FastCGI cache** setup ready with **Nginx** (1.27.3)
- ✅ **WP-CLI** ready for plugin and theme installations
- ✅ Includes all dependencies required for the **NPP plugin**
- ✅ Isolated and secure **PHP process owner** for enhanced security and performance
- ✅ Built with **bindfs** (1.17.7) for FUSE-based mounting of **Nginx Cache Path**
- ✅ Supports a wide range of **PHP extensions**

## 🔑 Environment Variables

Please check the **.env** file for the environment variables used by the project.

Some variables can be directly modified by the user to customize the setup, while others are integral to the project's core configuration. Changing these core variables may require adjustments in other parts of the project to maintain proper integration and workflow.

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
🚨 **The included SSL certificates are dummy, strictly for local usage** and **must not be used in production environments**.<br>
📦 This project leverages the fantastic **work** by **[Michele Locati](https://github.com/mlocati/docker-php-extension-installer)** to streamline the installation of required PHP extensions.
