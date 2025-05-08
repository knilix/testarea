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

#!/bin/bash

set -e

# ───── OS-Check ─────
if ! grep -qiE 'debian|ubuntu' /etc/os-release; then
  echo "Dieses Skript unterstützt nur Debian oder Ubuntu."
  exit 1
fi

# ───── Root-Check ─────
if [[ "$EUID" -ne 0 ]]; then
  echo "Bitte führe dieses Skript als root aus (sudo)."
  exit 1
fi

# ───── Abhängigkeiten installieren ─────
apt-get update
apt-get install -y curl openssl gawk docker.io

# ───── Docker installieren, falls nicht vorhanden ─────
if ! command -v docker &> /dev/null; then
  echo "Docker ist nicht installiert. Installiere Docker..."

  # Docker-Installationsscript herunterladen und ausführen
  curl -fsSL https://get.docker.com -o get-docker.sh
  sudo sh get-docker.sh

  # Docker-Gruppe für den aktuellen Benutzer anlegen und Benutzer hinzufügen
  sudo newgrp docker
  sudo usermod -aG docker $USER
else
  echo "Docker ist bereits installiert."
fi

# ───── Docker Compose installieren, falls nicht vorhanden ─────
if ! command -v docker-compose &> /dev/null; then
  echo "Docker Compose ist nicht installiert. Installiere Docker Compose..."

  # Die neueste Version von Docker Compose installieren
  curl -L "https://github.com/docker/compose/releases/download/v2.17.3/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
else
  echo "Docker Compose ist bereits installiert."
fi

# ───── Docker-Dienst starten und aktivieren ─────
echo "Starte Docker-Dienst..."
systemctl start docker
systemctl enable docker

# ───── Docker-Dienststatus prüfen ─────
systemctl status docker

echo "Docker und Docker Compose wurden erfolgreich installiert!"

# ───── Docker Compose installieren ─────
if ! command -v docker compose &> /dev/null; then
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  usermod -aG docker "$SUDO_USER"
  newgrp docker
fi

# ───── Verzeichnisse vorbereiten ─────
mkdir -p /opt/nextcloud-docker/nginx/ssl
cd /opt/nextcloud-docker

# ───── Passwörter generieren und speichern ─────
DB_ROOT_PASSWORD=$(openssl rand -base64 32)
MYSQL_PASSWORD=$(openssl rand -base64 32)
NC_ADMIN_USER="admin"
NC_ADMIN_PASS=$(openssl rand -base64 32)

CRED_FILE="/root/nextcloud-credentials.txt"
cat <<EOF > "$CRED_FILE"
Datenbank Root Passwort: $DB_ROOT_PASSWORD
Nextcloud DB Benutzer: nextcloud
Nextcloud DB Passwort: $MYSQL_PASSWORD
Nextcloud Admin Benutzer: $NC_ADMIN_USER
Nextcloud Admin Passwort: $NC_ADMIN_PASS
Zugriff: https://$(hostname -I | awk '{print $1}')
EOF
chmod 600 "$CRED_FILE"

# ───── .env-Datei erstellen ─────
cat <<EOF > .env
DB_ROOT_PASSWORD=$DB_ROOT_PASSWORD
MYSQL_PASSWORD=$MYSQL_PASSWORD
NC_ADMIN_USER=$NC_ADMIN_USER
NC_ADMIN_PASS=$NC_ADMIN_PASS
EOF

# ───── Selbstsigniertes Zertifikat ─────
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout nginx/ssl/selfsigned.key \
  -out nginx/ssl/selfsigned.crt \
  -days 365 \
  -subj "/CN=$(hostname -I | awk '{print $1}')"

# ───── docker-compose.yml ─────
cat <<'EOF' > docker-compose.yml
services:
  nextcloud:
    image: nextcloud:latest
    container_name: nextcloud_app
    restart: unless-stopped
    volumes:
      - nextcloud_data:/var/www/html
      - ./nginx/ssl:/etc/ssl/nginx:ro
    environment:
      MYSQL_PASSWORD: "${MYSQL_PASSWORD}"
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_HOST: db
      REDIS_HOST: redis
      NEXTCLOUD_ADMIN_USER: "${NC_ADMIN_USER}"
      NEXTCLOUD_ADMIN_PASSWORD: "${NC_ADMIN_PASS}"
    depends_on:
      - db
      - redis

  db:
    image: mariadb:10.11
    container_name: nextcloud_db
    restart: unless-stopped
    volumes:
      - db_data:/var/lib/mysql
    environment:
      MYSQL_ROOT_PASSWORD: "${DB_ROOT_PASSWORD}"
      MYSQL_PASSWORD: "${MYSQL_PASSWORD}"
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud

  redis:
    image: redis:alpine
    container_name: nextcloud_redis
    restart: unless-stopped

  nginx:
    image: nginx:stable-alpine
    container_name: nextcloud_nginx
    restart: unless-stopped
    ports:
      - "443:443"
    volumes:
      - ./nginx/ssl:/etc/ssl/nginx:ro
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - nextcloud_data:/var/www/html:ro
    depends_on:
      - nextcloud

volumes:
  nextcloud_data:
  db_data:
EOF

# ───── nginx.conf ─────
cat <<'EOF' > nginx/nginx.conf
events {}
http {
  server {
    listen 443 ssl;
    server_name _;

    ssl_certificate     /etc/ssl/nginx/selfsigned.crt;
    ssl_certificate_key /etc/ssl/nginx/selfsigned.key;

    location / {
      proxy_pass http://nextcloud:80;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto https;
    }
  }
}
EOF

# ───── Docker Compose starten ─────
docker compose up -d

# ───── Warten, bis Nextcloud bereit ist ─────
echo "Warte auf Nextcloud Initialisierung..."
sleep 30

# ───── PHP-Konfiguration in Container anpassen ─────
CONTAINER_ID=$(docker ps -qf "name=nextcloud_app")
PHP_INI=$(docker exec "$CONTAINER_ID" php --ini | awk -F': ' '/Loaded Configuration/{print $2}')

docker exec -i "$CONTAINER_ID" bash -c "cat >> '$PHP_INI'" <<'EOCONFIG'
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
EOCONFIG

# ───── config.php erweitern ─────
CONFIG_FILE="/opt/nextcloud-docker/nextcloud_data/config/config.php"
if [ -f "$CONFIG_FILE" ]; then
  TMP_FILE=$(mktemp)
  awk '
    /^\);$/ {
      print "  '\''trusted_domains'\'' => array ( 0 => '\''" ENVIRON["IP"] "'\'', ),";
      print "  '\''default_phone_region'\'' => '\''DE'\'',";
      print "  '\''enable_previews'\'' => true,";
      print "  '\''enabledPreviewProviders'\'' => array (";
      print "    0 => '\''OC\\\\\\\\Preview\\\\\\\\PNG'\'',";
      print "    1 => '\''OC\\\\\\\\Preview\\\\\\\\JPEG'\'',";
      print "    2 => '\''OC\\\\\\\\Preview\\\\\\\\GIF'\'',";
      print "    3 => '\''OC\\\\\\\\Preview\\\\\\\\BMP'\'',";
      print "    4 => '\''OC\\\\\\\\Preview\\\\\\\\XBitmap'\'',";
      print "    5 => '\''OC\\\\\\\\Preview\\\\\\\\MP3'\'',";
      print "    6 => '\''OC\\\\\\\\Preview\\\\\\\\TXT'\'',";
      print "    7 => '\''OC\\\\\\\\Preview\\\\\\\\MarkDown'\'',";
      print "    8 => '\''OC\\\\\\\\Preview\\\\\\\\OpenDocument'\'',";
      print "    9 => '\''OC\\\\\\\\Preview\\\\\\\\Krita'\'',";
      print "    10 => '\''OC\\\\\\\\Preview\\\\\\\\HEIC'\'',";
      print "  ),";
      print "  '\''maintenance_window_start'\'' => 1,";
    }
    { print }
  ' IP="$(hostname -I | awk '{print $1}')" "$CONFIG_FILE" > "$TMP_FILE"
  cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
  mv "$TMP_FILE" "$CONFIG_FILE"
fi

# ───── Ausgabe ─────
echo "Installation abgeschlossen."
echo "Zugangsdaten (auch gespeichert in $CRED_FILE):"
cat "$CRED_FILE"

# ───── Bereinigung ─────
rm -rf /opt/scriptfiles/testarea-main /opt/main.zip 2>/dev/null || true
