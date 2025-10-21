# Bashscript-for-automation-and-deployment
A robust, production-grade Bash script that automates the setup, deployment, and configuration of a Dockerized application on a remote Linux server.
# Bash Automation & Deployment Script

Automates the deployment of Dockerized applications to a remote server with Nginx as a reverse proxy.  

---

## Features

- Clone or update a Git repository (HTTPS + Personal Access Token support)
- Supports Dockerfile or Docker Compose deployments
- Transfers project files to a remote server using `rsync`
- Builds and runs Docker containers on the remote host
- Configures Nginx to reverse proxy traffic to the container
- Validates deployment (container status, Nginx response, external HTTP test)
- Optional cleanup of containers, Nginx configs, and project files
- Robust error handling with logging

---

## Prerequisites

- Local:
  - Bash (Linux/macOS/WSL)
  - `ssh` and `scp`
  - `rsync`
  - `curl` or `wget`
- Remote server:
  - Ubuntu/Debian or CentOS/RHEL
  - Sudo privileges for installing Docker, Docker Compose, and Nginx

---

## Usage

```bash
./deploy.sh [--cleanup]
