# 🐳 NPP Dockerized  [![Docker Build](https://github.com/psaux-it/wordpress-nginx-cache-docker/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/psaux-it/wordpress-nginx-cache-docker/actions/workflows/docker-publish.yml)

Welcome to the Docker project optimized for the **[(NPP) WordPress Plugin](https://wordpress.org/plugins/fastcgi-cache-purge-and-preload-nginx/)**! 🎉 This full-stack Dockerized environment is designed for **NPP** usage, including **WordPress**, **PHP-FPM**, **Nginx**, **MySQL**, **FastCGI cache**, **WP-CLI**, and necessary **PHP extensions**. It's tailored for easy deployment and efficient use of the **NPP plugin**, providing a comprehensive solution for **Nginx Cache** management on wordpress.

Explore the **[NPP Main GitHub Repository](https://github.com/psaux-it/nginx-fastcgi-cache-purge-and-preload)** to access the heart of the plugin development.

## 🔧 Features

- ✅ **WordPress** (6.7.1) with **PHP-FPM** (8.2)
- ✅ **MySQL** (8) for database management
- ✅ **FastCGI** cache ready with **Nginx** (1.27.3)
- ✅ **WP-CLI** ready for plugin and theme installations (safe without --allow-root)
- ✅ Includes all dependencies required for the **NPP plugin**
- ✅ Isolated and secure **PHP process owner** for enhanced security and performance
- ✅ Built with **bindfs** (1.17.7) + **fuse3** (1.16.2) for FUSE-based mounting of **Nginx Cache Path**
- ✅ Supports a wide range of **PHP extensions**
- ✅ Easily switch between the **stable** release and the **bleeding-edge dev** version of the **NPP**
- ✅ All containers powered by **Debian 12** for a stable, consistent environment

## 🔑 Environment Variables

Please check the **.env** file for the environment variables used by the project.

Some variables can be directly modified by the user to customize the setup easily, while others are hard depend to the project's core configuration. Modifying these core variables for a production environment may require adjustments in other parts of the project to ensure proper integration and workflow. Feel free to customize it to meet your full-stack WordPress **production** needs!

#### Use the Bleeding-Edge Version of NPP or Contribute to Development  

If you want to use the **latest bleeding-edge version** of the NPP plugin or set up a **development/test environment**, simply set the following environment variable:  

```bash
NPP_DEV_ENABLED=1
```

🔄 This will sync the plugin with the latest development branch commit from GitHub, ensuring you always have access to the newest features and improvements.

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
  - 🔒 [https://172.19.0.3](https://172.19.0.3)
  - 🌐 [http://172.19.0.3](http://172.19.0.3)

- Default WordPress **wp-admin** login credentials:
  - **Username**: `npp`
  - **Password**: `npp`

### 🔧 **Nginx Cache Path Configuration**
- Users can use the FUSE mount path **`/var/cache/nginx-npp`** as the Nginx cache path in the NPP plugin settings page.

---
#### ⚠️ Important Notices
🚨 **The included SSL certificates are dummy, strictly for local usage** and **must not be used in production environments**.<br>
📦 This project leverages the fantastic **work** by **[Michele Locati](https://github.com/mlocati/docker-php-extension-installer)** to streamline the installation of required PHP extensions.
