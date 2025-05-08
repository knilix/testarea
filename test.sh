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
set -e

GREEN="\033[1;32m"
RED="\033[1;31m"
NC="\033[0m"

read -rp "Möchtest du den Nextcloud-Stack mit Docker installieren? (ja/nein): " CONFIRM
if [[ "$CONFIRM" != "ja" ]]; then
  echo -e "${RED}Installation abgebrochen.${NC}"
  exit 1
fi

# curl installieren (wenn nicht vorhanden)
if ! command -v curl &>/dev/null; then
  echo -e "${GREEN}Installiere curl...${NC}"
  apt update && apt install -y curl
fi

# Docker installieren, falls nicht vorhanden
if ! command -v docker &>/dev/null; then
  echo -e "${GREEN}Installiere Docker...${NC}"
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  rm get-docker.sh
  usermod -aG docker "$USER"
  echo -e "${GREEN}Bitte abmelden und wieder anmelden, damit die Docker-Gruppe aktiv wird.${NC}"
fi

# Docker Compose Plugin prüfen
if ! docker compose version &>/dev/null; then
  echo -e "${GREEN}Installiere Docker Compose Plugin...${NC}"
  apt install -y docker-compose-plugin
fi

systemctl enable --now docker

INSTALL_DIR="/opt/nextcloud-docker"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

DB_USER="ncuser"
DB_PASS="$(openssl rand -hex 12)"
DB_NAME="nextcloud"
NEXTCLOUD_ADMIN="admin"
NEXTCLOUD_PASS="$(openssl rand -hex 12)"
DOMAIN_NAME="localhost"
EMAIL="admin@example.com"

SSL_DIR="$INSTALL_DIR/certs"
mkdir -p "$SSL_DIR"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$SSL_DIR/selfsigned.key" \
  -out "$SSL_DIR/selfsigned.crt" \
  -subj "/C=DE/ST=State/L=City/O=Organization/OU=Unit/CN=$DOMAIN_NAME"

cat > docker-compose.yml <<EOF
version: '3'

services:
  mariadb:
    image: mariadb:10.11
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: $DB_PASS
      MYSQL_DATABASE: $DB_NAME
      MYSQL_USER: $DB_USER
      MYSQL_PASSWORD: $DB_PASS
    volumes:
      - db_data:/var/lib/mysql

  redis:
    image: redis:alpine
    restart: always

  nextcloud:
    image: nextcloud
    restart: always
    ports:
      - 8080:80
    environment:
      MYSQL_PASSWORD: $DB_PASS
      MYSQL_DATABASE: $DB_NAME
      MYSQL_USER: $DB_USER
      MYSQL_HOST: mariadb
      REDIS_HOST: redis
      NEXTCLOUD_ADMIN_USER: $NEXTCLOUD_ADMIN
      NEXTCLOUD_ADMIN_PASSWORD: $NEXTCLOUD_PASS
    volumes:
      - nextcloud_data:/var/www/html
    depends_on:
      - mariadb
      - redis

  nginx:
    image: nginx:alpine
    restart: always
    ports:
      - 443:443
      - 80:80
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./certs:/etc/nginx/certs:ro
    depends_on:
      - nextcloud

  watchtower:
    image: containrrr/watchtower
    restart: always
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --cleanup --interval 86400

volumes:
  db_data:
  nextcloud_data:
EOF

cat > nginx.conf <<EOF
events {}

http {
  server {
    listen 80;
    server_name $DOMAIN_NAME;
    return 301 https://\$host\$request_uri;
  }

  server {
    listen 443 ssl;
    server_name $DOMAIN_NAME;

    ssl_certificate /etc/nginx/certs/selfsigned.crt;
    ssl_certificate_key /etc/nginx/certs/selfsigned.key;

    location / {
      proxy_pass http://nextcloud:80;
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto https;
    }
  }
}
EOF

echo -e "${GREEN}Starte Docker-Container...${NC}"
docker compose up -d

# Warten bis Nextcloud verfügbar ist
echo -e "${GREEN}Warte auf Nextcloud Initialisierung... (30s)${NC}"
sleep 30

# config.php automatisch anpassen, falls vorhanden
CONFIG_FILE="/opt/nextcloud-docker/nextcloud_data/config/config.php"
if [ -f "$CONFIG_FILE" ]; then
  TMP_FILE=$(mktemp)
  awk '
    /^\);$/ {
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
  ' "$CONFIG_FILE" > "$TMP_FILE"
  cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
  cp "$TMP_FILE" "$CONFIG_FILE"
  rm "$TMP_FILE"
fi

# Zugangsdaten-Datei nur für root lesbar
CREDENTIALS_FILE="$INSTALL_DIR/credentials.txt"
cat > "$CREDENTIALS_FILE" <<EOF
Nextcloud Zugangsdaten
=======================
URL: https://$DOMAIN_NAME
Port: 443
Benutzer: $NEXTCLOUD_ADMIN
Passwort: $NEXTCLOUD_PASS

MariaDB Zugangsdaten
=====================
Benutzer: $DB_USER
Passwort: $DB_PASS
Datenbank: $DB_NAME

SSL-Zertifikat:
  Zertifikat: $SSL_DIR/selfsigned.crt
  Schlüssel:   $SSL_DIR/selfsigned.key

Automatische Updates:
  Watchtower prüft alle 24 Stunden auf neue Images.

Standort: $INSTALL_DIR
EOF

chmod 600 "$CREDENTIALS_FILE"
chown root:root "$CREDENTIALS_FILE"

# Bereinigung
rm -rf /opt/scriptfiles/testarea-main /opt/main.zip 2>/dev/null || true

echo -e "${GREEN}Installation abgeschlossen.${NC}"
echo
echo -e "${GREEN}Zugangsdaten (auch in ${CREDENTIALS_FILE}):${NC}"
cat "$CREDENTIALS_FILE"
