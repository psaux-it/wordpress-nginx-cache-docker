# 🐳 NPP Dockerized  [![Docker Build](https://github.com/psaux-it/wordpress-nginx-cache-docker/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/psaux-it/wordpress-nginx-cache-docker/actions/workflows/docker-publish.yml)

Welcome to the Docker project optimized for the **[(NPP) WordPress Plugin](https://wordpress.org/plugins/fastcgi-cache-purge-and-preload-nginx/)**! 🎉 This full-stack Dockerized environment is designed for **NPP**, including **WordPress** with **FPM**, **Nginx**, **MySQL**, **FastCGI**, **WP-CLI**, **phpMyAdmin**, and necessary **PHP extensions**. It's tailored for easy deployment and efficient use of the **NPP plugin**

Explore the **[NPP Main GitHub Repository](https://github.com/psaux-it/nginx-fastcgi-cache-purge-and-preload)** to access the heart of the plugin development.

https://github.com/user-attachments/assets/5a946953-c7f1-4d44-a8ac-3487018d7114

🔊™️ In The Silence - Giuseppe Ottaviani


## ✨ Features

- ✅ **WordPress** (6.7.2) with **PHP-FPM** (8.2)
- ✅ **MySQL** (8) for database management
- ✅ **FastCGI** cache ready with **Nginx** (1.27.4)
- ✅ **WP-CLI** ready for plugin and theme installations (check **.env**)
- ✅ **phpMyAdmin** (5.2.2) ready
- ✅ Includes all dependencies required for the **NPP plugin**
- ✅ Isolated and secure **PHP process owner** for enhanced security and performance
- ✅ Built with **bindfs** (1.17.7) + **fuse3** (1.16.2) for FUSE-based mounting of **Nginx Cache Path**
- ✅ Installed a wide range of **PHP extensions**
- ✅ Easily switch between the **stable** release and the **bleeding-edge** version of the **NPP**
- ✅ All containers powered by **Debian 12** for a stable, consistent environment
- ✅ Compatible with both Windows **WSL** and Linux Hosts

## 🔑 Environment Variables

**This repository was primarily created for testing and developing the NPP plugin on local.** However, with minor adjustments, It can also be used as a **production** environment.

Please check the **.env** file for the environment variables used in the project. Some variables can be directly modified by the user for easy customization, while others are derived from the **original Dockerfiles of core services**. Changing these **core variables** for a production environment may require adjustments in other parts of the project to maintain seamless integration and workflow. Feel free to customize it to suit your full-stack WordPress **production** needs!

### Use the Bleeding-Edge Version of NPP (Default)

If you want to use the latest **bleeding-edge version** of the NPP plugin simply set the following environment variable:  

```bash
NPP_EDGE=1
```

🔄 This will sync the plugin with the latest development branch commit from GitHub, ensuring you always have access to the newest features and improvements.

### ⚠️ In Production

To enable **Nginx Cache Preload** in a **localhost** development environment, a small host configuration adjustment is **always** required. In **production**, this may or may not be required depending on your Docker architecture. If you encounter a **Cache Preload** issue in production, try enabling the below setting in **.env**, otherwise, you can disable it entirely.

```bash
NPP_HACK_HOST=1
```

For a full explanation and to adjust your environment, please read the complete story here:

https://github.com/psaux-it/wordpress-nginx-cache-docker/blob/1c8043a0bc6e2014b55ae6f7259eba134e3f3698/wordpress/wp-post.sh#L129

## ⚙️️ Instant Deployment

### 1. Clone the repository

Start by cloning the repository to your local machine:

```bash
git clone https://github.com/psaux-it/wordpress-nginx-cache-docker.git
cd wordpress-nginx-cache-docker
```

### 2. Run the Services

Run the following command to build and start the container:

- **Using pre-built images:**  

```bash
docker compose up
```

- **Building locally:**

```bash
docker compose up --build
```

### 🚀 **Post-Container Startup Access**
- The WordPress site can be accessed at the host machine:
  - 🔒 [https://localhost](https://localhost)
  - 🌐 [http://localhost](http://localhost)

- Default WordPress **wp-admin** login credentials:
  - **Username**: `npp`
  - **Password**: `npp`

- You can also access **phpMyAdmin** at:
  - https://localhost/phpmyadmin

- Default FUSE mount path:
  - **`/var/cache/nginx-npp`**
  - Use the FUSE mount path as the Nginx cache path in the NPP plugin settings page.

---
#### ⚠️ Important Notices
🚨 **The included SSL certificates are dummy, strictly for local usage** and **must not be used in production environments**.<br>
📦 This project leverages the fantastic **work** by **[Michele Locati](https://github.com/mlocati/docker-php-extension-installer)** to streamline the installation of required PHP extensions.
