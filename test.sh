#!/bin/bash
#
# Maintainer: @knilix
# Version: 1.0.1
#
# Faulty: 403 Forbidden nginx
#
# Script to install Nextcloud with Nginx, MariaDB and Redis using Docker Compose
# Compatible with Debian and Ubuntu systems
# Script nur einmalig ausführen - - Abfrage einer vorhandenen Nextcloud-Datenbank noch nicht implementiert!
# -----------------------------------------------------------------------------------------------------------------------------
# download and unzip: wget -q -P /opt/ https://github.com/knilix/testarea/archive/refs/heads/main.zip && unzip /opt/main.zip -d /opt/scriptfiles && chmod 700 /opt/scriptfiles/testarea-main/test.sh
# execute (unique): cd /opt/scriptfiles/testarea-main && ./test.sh
# in case of problems: rm -rf /opt/scriptfiles/testarea-main /opt/main.zip 2>/dev/null || true
# -----------------------------------------------------------------------------------------------------------------------------
# Exit on error
set -e

# Check if script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# Check if system is Debian or Ubuntu
if ! (grep -E "^(ID=debian|ID=ubuntu)" /etc/os-release >/dev/null); then
    echo "This script only supports Debian or Ubuntu"
    exit 1
fi

# Get system IP address
IP_ADDRESS=$(ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1 | head -1)

# Generate passwords
DB_ROOT_PASSWORD=$(openssl rand -base64 32)
DB_PASSWORD=$(openssl rand -base64 32)
NEXTCLOUD_ADMIN_PASSWORD=$(openssl rand -base64 32)

# Install prerequisites
apt-get update
apt-get install -y curl openssl ca-certificates

# Install Docker if not present
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    newgrp docker
    usermod -aG docker $USER
    rm get-docker.sh
fi

# Create directories
mkdir -p /opt/nextcloud-docker/{nginx,db,redis,nextcloud_data,ssl,certs,logs}

# Generate self-signed certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /opt/nextcloud-docker/ssl/selfsigned.key \
    -out /opt/nextcloud-docker/ssl/selfsigned.crt \
    -subj "/C=DE/ST=State/L=City/O=Organization/OU=Unit/CN=$IP_ADDRESS"

# Create docker-compose.yml
cat > /opt/nextcloud-docker/docker-compose.yml << EOF
version: '3'

services:
  db:
    image: mariadb:latest
    container_name: nextcloud_db
    volumes:
      - /opt/nextcloud-docker/db:/var/lib/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=$DB_ROOT_PASSWORD
      - MYSQL_PASSWORD=$DB_PASSWORD
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
    restart: unless-stopped

  redis:
    image: redis:latest
    container_name: nextcloud_redis
    volumes:
      - /opt/nextcloud-docker/redis:/data
    restart: unless-stopped

  nextcloud:
    image: nextcloud:latest
    container_name: nextcloud
    volumes:
      - /opt/nextcloud-docker/nextcloud_data:/var/www/html
      - /opt/nextcloud-docker/certs:/var/www/html/certs
    environment:
      - MYSQL_HOST=db
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
      - MYSQL_PASSWORD=$DB_PASSWORD
      - REDIS_HOST=redis
      - NEXTCLOUD_ADMIN_USER=admin
      - NEXTCLOUD_ADMIN_PASSWORD=$NEXTCLOUD_ADMIN_PASSWORD
      - NEXTCLOUD_TRUSTED_DOMAINS=$IP_ADDRESS
    depends_on:
      - db
      - redis
    restart: unless-stopped

  nginx:
    image: nginx:latest
    container_name: nextcloud_nginx
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /opt/nextcloud-docker/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - /opt/nextcloud-docker/ssl:/etc/nginx/ssl:ro
      - /opt/nextcloud-docker/nextcloud_data:/var/www/html:ro
      - /opt/nextcloud-docker/logs:/var/log/nginx
    depends_on:
      - nextcloud
    restart: unless-stopped
EOF

# Create nginx configuration with improved settings
cat > /opt/nextcloud-docker/nginx/nginx.conf << EOF
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;
    proxy_buffer_size 128k;
    proxy_buffers 4 256k;
    proxy_busy_buffers_size 256k;

    server {
        listen 80;
        server_name $IP_ADDRESS;
        return 301 https://\$server_name\$request_uri;
    }

    server {
        listen 443 ssl;
        server_name $IP_ADDRESS;

        ssl_certificate /etc/nginx/ssl/selfsigned.crt;
        ssl_certificate_key /etc/nginx/ssl/selfsigned.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;

        root /var/www/html;
        index index.php index.html;

        access_log /var/log/nginx/access.log;
        error_log /var/log/nginx/error.log warn;

        location / {
            proxy_pass http://nextcloud;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_read_timeout 3600;
            proxy_connect_timeout 3600;
        }

        location ~ \.php$ {
            fastcgi_pass nextcloud:9000;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            fastcgi_read_timeout 3600;
            include fastcgi_params;
        }
    }
}
EOF

# Create custom php.ini
cat > /opt/nextcloud-docker/certs/custom.ini << EOF
memory_limit = 512M
upload_max_filesize = 20G
post_max_size = 500M
max_execution_time = 300
date.timezone = Europe/Berlin
opcache.enable=1
opcache.interned_strings_buffer=32
opcache.max_accelerated_files=10000
opcache.memory_consumption=128
opcache.save_comments=1
opcache.revalidate_freq=1
EOF

# Create credentials file (root only)
cat > /opt/nextcloud-docker/credentials.txt << EOF
Nextcloud Installation Credentials
================================
IP Address: $IP_ADDRESS
Nextcloud URL: https://$IP_ADDRESS
Admin Username: admin
Admin Password: $NEXTCLOUD_ADMIN_PASSWORD
Database Root Password: $DB_ROOT_PASSWORD
Database User: nextcloud
Database Password: $DB_PASSWORD
Database Name: nextcloud
================================
Note: This file is only readable by root
EOF
chmod 600 /opt/nextcloud-docker/credentials.txt

# Start containers
cd /opt/nextcloud-docker
docker compose up -d

# Wait for Nextcloud to be ready
echo "Waiting for services to initialize..."
sleep 30

# Check if containers are running
if ! docker ps | grep -q nextcloud_nginx; then
    echo "Error: Nginx container is not running. Checking logs..."
    docker logs nextcloud_nginx
    exit 1
fi
if ! docker ps | grep -q nextcloud; then
    echo "Error: Nextcloud container is not running. Checking logs..."
    docker logs nextcloud
    exit 1
fi

# Verify PHP-FPM is running in Nextcloud container
if ! docker exec nextcloud ps aux | grep -q php-fpm; then
    echo "Error: PHP-FPM is not running in Nextcloud container. Checking logs..."
    docker logs nextcloud
    exit 1
fi

# Modify config.php
CONFIG_FILE="/opt/nextcloud-docker/nextcloud_data/config/config.php"
if [ -f "$CONFIG_FILE" ]; then
    TMP_FILE=$(mktemp)
    awk '
        /^\);$/ {
            print "  '\''trusted_domains'\'' => array (";
            print "    0 => '\''$IP_ADDRESS'\'',";
            print "  ),";
            print "  '\''default_phone_region'\'' => '\''DE'\'',";
            print "  '\''enable_previews'\'' => true,";
            print "  '\''enabledPreviewProviders'\'' => array (";
            print "    0 => '\''OC\\\\Preview\\\\PNG'\'',";
            print "    1 => '\''OC\\\\Preview\\\\JPEG'\'',";
            print "    2 => '\''OC\\\\Preview\\\\GIF'\'',";
            print "    3 => '\''OC\\\\Preview\\\\BMP'\'',";
            print "    4 => '\''OC\\\\Preview\\\\XBitmap'\'',";
            print "    5 => '\''OC\\\\Preview\\\\MP3'\'',";
            print "    6 => '\''OC\\\\Preview\\\\TXT'\'',";
            print "    7 => '\''OC\\\\Preview\\\\MarkDown'\'',";
            print "    8 => '\''OC\\\\Preview\\\\OpenDocument'\'',";
            print "    9 => '\''OC\\\\Preview\\\\Krita'\'',";
            print "    10 => '\''OC\\\\Preview\\\\HEIC'\'',";
            print "  ),";
            print "  '\''maintenance_window_start'\'' => 1,";
        }
        { print }
    ' "$CONFIG_FILE" > "$TMP_FILE"
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    cp "$TMP_FILE" "$CONFIG_FILE"
    rm "$TMP_FILE"
fi

# Cleanup
rm -rf /opt/scriptfiles/testarea-main /opt/main.zip 2>/dev/null || true

# Display credentials
echo -e "\nNextcloud Installation Completed!"
echo "================================="
echo "Access Nextcloud at: https://$IP_ADDRESS"
echo "Admin Username: admin"
echo "Admin Password: $NEXTCLOUD_ADMIN_PASSWORD"
echo "Database credentials are stored in /opt/nextcloud-docker/credentials.txt (root only)"
echo "Nginx logs are stored in /opt/nextcloud-docker/logs/"
echo "================================="
echo "Note: You may need to accept the self-signed certificate in your browser"
echo "If you encounter a 502 Bad Gateway error, check logs in /opt/nextcloud-docker/logs/error.log"
echo "Please log out and log back in for Docker group changes to take effect"
