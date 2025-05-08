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

# ───── Root-Check ─────
if [[ "$EUID" -ne 0 ]]; then
  echo "Bitte führe dieses Skript als root aus (sudo)."
  exit 1
fi

# ───── Docker Compose-Check ─────
if ! docker compose version &> /dev/null; then
  echo "Docker Compose ist nicht installiert. Bitte installieren Sie Docker Compose und führen Sie das Skript erneut aus."
  exit 1
else
  echo "Docker Compose ist installiert."
fi

# ───── Erstellen des Verzeichnisses und Zertifikats ─────
CERT_DIR="./certificates"
mkdir -p "$CERT_DIR"
DOMAIN="localhost"  # Verwende die IP-Adresse oder Domain, je nach Bedarf

echo "Erstelle ein selbstsigniertes Zertifikat für $DOMAIN..."
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout "$CERT_DIR/private.key" -out "$CERT_DIR/certificate.crt" -subj "/C=DE/ST=Berlin/L=Berlin/O=Nextcloud/OU=IT/CN=$DOMAIN"

# ───── Zugangsdaten generieren ─────
MYSQL_PASSWORD=$(openssl rand -base64 32)
MYSQL_USER="nextcloud_user"
MYSQL_DATABASE="nextcloud_db"
NEXTCLOUD_ADMIN_USER="admin"
NEXTCLOUD_ADMIN_PASSWORD=$(openssl rand -base64 32)
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)

# ───── Docker-Umgebungsdatei erstellen ─────
echo "Erstelle die .env Datei mit Zugangsdaten..."
cat <<EOF > .env
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
MYSQL_PASSWORD=$MYSQL_PASSWORD
MYSQL_USER=$MYSQL_USER
MYSQL_DATABASE=$MYSQL_DATABASE
NEXTCLOUD_ADMIN_USER=$NEXTCLOUD_ADMIN_USER
NEXTCLOUD_ADMIN_PASSWORD=$NEXTCLOUD_ADMIN_PASSWORD
EOF

# ───── Erstellen der docker-compose.yml ─────
echo "Erstelle docker-compose.yml..."
cat <<EOF > docker-compose.yml
version: '3.9'

services:
  nextcloud:
    image: nextcloud:latest
    container_name: nextcloud
    restart: unless-stopped
    ports:
      - "443:443"
    volumes:
      - ./nextcloud_data:/var/www/html
      - ./certificates:/etc/ssl/certs
    environment:
      - MYSQL_PASSWORD=\${MYSQL_PASSWORD}
      - MYSQL_DATABASE=\${MYSQL_DATABASE}
      - MYSQL_USER=\${MYSQL_USER}
      - MYSQL_HOST=db
      - NEXTCLOUD_ADMIN_USER=\${NEXTCLOUD_ADMIN_USER}
      - NEXTCLOUD_ADMIN_PASSWORD=\${NEXTCLOUD_ADMIN_PASSWORD}
    depends_on:
      - db
      - redis
    networks:
      - nextcloud

  db:
    image: mariadb:latest
    container_name: nextcloud_db
    restart: unless-stopped
    environment:
      - MYSQL_ROOT_PASSWORD=\${MYSQL_ROOT_PASSWORD}
      - MYSQL_PASSWORD=\${MYSQL_PASSWORD}
      - MYSQL_DATABASE=\${MYSQL_DATABASE}
      - MYSQL_USER=\${MYSQL_USER}
    volumes:
      - ./mariadb_data:/var/lib/mysql
    networks:
      - nextcloud

  redis:
    image: redis:alpine
    container_name: nextcloud_redis
    restart: unless-stopped
    networks:
      - nextcloud

  nginx:
    image: nginx:latest
    container_name: nextcloud_nginx
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./certificates:/etc/ssl/certs
    ports:
      - "80:80"
      - "443:443"
    networks:
      - nextcloud

networks:
  nextcloud:
    driver: bridge
EOF

# ───── Erstellen der nginx.conf ─────
echo "Erstelle nginx.conf..."
cat <<EOF > nginx.conf
server {
    listen 80;
    server_name localhost;

    return 301 https://$DOMAIN\$request_uri;
}

server {
    listen 443 ssl;
    server_name localhost;

    ssl_certificate /etc/ssl/certs/certificate.crt;
    ssl_certificate_key /etc/ssl/certs/private.key;

    location / {
        proxy_pass http://nextcloud:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

#
