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

### Variablen ###
NEXTCLOUD_DIR="/opt/nextcloud-docker"
DB_PASSWORD=$(openssl rand -base64 32)
NEXTCLOUD_ADMIN_USER="admin"
NEXTCLOUD_ADMIN_PASSWORD=$(openssl rand -base64 32)
CREDENTIAL_FILE="/root/nextcloud_credentials.txt"
CERT_DIR="$NEXTCLOUD_DIR/certs"
CONFIG_PHP="$NEXTCLOUD_DIR/nextcloud_data/config/config.php"
SERVER_IP=$(hostname -I | awk '{print $1}')

### OS-Erkennung ###
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Betriebssystem nicht erkannt."
    exit 1
fi

if [ "$OS" != "debian" ] && [ "$OS" != "ubuntu" ]; then
    echo "Dieses Skript unterstützt nur Debian und Ubuntu."
    exit 1
fi

### Notwendige Pakete installieren ###
echo "Benötigte Pakete werden installiert..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y curl openssl gawk coreutils

### Docker installieren, falls nicht vorhanden ###
if ! command -v docker &> /dev/null; then
    echo "Docker wird installiert..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    newgrp docker
    usermod -aG docker "$USER"
fi

### Docker Compose CLI installieren ###
if ! command -v docker compose &> /dev/null; then
    echo "Docker Compose CLI wird eingerichtet (ab Docker 20.10+ integriert)..."
    DOCKER_CONFIG_PATH="/usr/local/lib/docker/cli-plugins"
    mkdir -p "$DOCKER_CONFIG_PATH"
    curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) \
        -o "$DOCKER_CONFIG_PATH/docker-compose"
    chmod +x "$DOCKER_CONFIG_PATH/docker-compose"
    export PATH=$PATH:$DOCKER_CONFIG_PATH
fi

### Verzeichnisstruktur ###
mkdir -p "$NEXTCLOUD_DIR"
mkdir -p "$CERT_DIR"

### Selbstsigniertes Zertifikat erstellen ###
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$CERT_DIR/selfsigned.key" \
  -out "$CERT_DIR/selfsigned.crt" \
  -subj "/C=DE/ST=Berlin/L=Berlin/O=Nextcloud/CN=$SERVER_IP"

### Docker Compose Datei ###
cat > "$NEXTCLOUD_DIR/docker-compose.yml" <<EOF
version: '3'

services:
  db:
    image: mariadb
    restart: always
    volumes:
      - db:/var/lib/mysql
    environment:
      MYSQL_ROOT_PASSWORD=$DB_PASSWORD
      MYSQL_DATABASE=nextcloud
      MYSQL_USER=nextcloud
      MYSQL_PASSWORD=$DB_PASSWORD

  redis:
    image: redis:alpine
    restart: always

  app:
    image: nextcloud
    ports:
      - 443:443
    volumes:
      - nextcloud:/var/www/html
      - $CERT_DIR:/certs
    environment:
      MYSQL_PASSWORD: $DB_PASSWORD
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_HOST: db
      NEXTCLOUD_ADMIN_USER: $NEXTCLOUD_ADMIN_USER
      NEXTCLOUD_ADMIN_PASSWORD: $NEXTCLOUD_ADMIN_PASSWORD
      REDIS_HOST: redis
    depends_on:
      - db
      - redis
    restart: always
    command: >
      sh -c "apache2-foreground"

volumes:
  db:
  nextcloud:
EOF

### Container starten ###
cd "$NEXTCLOUD_DIR"
docker compose up -d

### Warte auf Nextcloud Setup ###
echo "Warte auf Nextcloud-Initialisierung..."
sleep 60

### PHP Konfiguration anpassen ###
PHP_INI=$(docker exec $(docker ps -qf "ancestor=nextcloud") php --ini | grep "Loaded Configuration" | awk '{print $4}')
docker exec $(docker ps -qf "ancestor=nextcloud") bash -c "echo '\
memory_limit = 512M\n\
upload_max_filesize = 20G\n\
post_max_size = 500M\n\
max_execution_time = 300\n\
date.timezone = Europe/Berlin\n\
opcache.enable=1\n\
opcache.interned_strings_buffer=32\n\
opcache.max_accelerated_files=10000\n\
opcache.memory_consumption=128\n\
opcache.save_comments=1\n\
opcache.revalidate_freq=1' >> $PHP_INI"

### Config.php erweitern ###
if [ -f "$CONFIG_PHP" ]; then
  TMP_FILE=$(mktemp)
  awk -v ip="$SERVER_IP" '
    /^\);$/ {
      print "  '\''trusted_domains'\'' => array (";
      print "    0 => '\''localhost'\'',";
      print "    1 => '\''" ip "'\'',";
      print "  ),";
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
  ' "$CONFIG_PHP" > "$TMP_FILE"
  cp "$CONFIG_PHP" "${CONFIG_PHP}.bak"
  cp "$TMP_FILE" "$CONFIG_PHP"
  rm "$TMP_FILE"
fi

### Zugangsdaten speichern ###
cat > "$CREDENTIAL_FILE" <<EOF
Nextcloud-Admin Zugang:
URL: https://$SERVER_IP
Benutzer: $NEXTCLOUD_ADMIN_USER
Passwort: $NEXTCLOUD_ADMIN_PASSWORD

MariaDB:
Benutzer: nextcloud
Passwort: $DB_PASSWORD
EOF
chmod 600 "$CREDENTIAL_FILE"

### Ausgabe ###
echo "Installation abgeschlossen!"
echo "Zugang zur Nextcloud über: https://$SERVER_IP"
echo "Admin Benutzer: $NEXTCLOUD_ADMIN_USER"
echo "Admin Passwort: $NEXTCLOUD_ADMIN_PASSWORD"
echo "MySQL Passwort: $DB_PASSWORD"
echo "Zugangsdaten gespeichert unter: $CREDENTIAL_FILE"

### Bereinigung ###
rm -rf /opt/scriptfiles/testarea-main /opt/main.zip 2>/dev/null || true
