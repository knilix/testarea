#!/bin/bash
# Maintainer: @Knilix
# Beschreibung: Installiert Nextcloud, MariaDB, Redis, Apache und Let's Encrypt in einem LXC-Container (Debian-basiert)
# ONLY TEST!
set -e

# Farbdefinitionen
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# Konfiguration
NEXTCLOUD_DB="nextcloud"
NEXTCLOUD_DB_USER="nextcloud"
NEXTCLOUD_DB_PASSWORD="$(openssl rand -base64 18)"
NEXTCLOUD_ADMIN_USER="admin"
NEXTCLOUD_ADMIN_PASSWORD="$(openssl rand -base64 18)"
DOMAIN="nextcloud-script.home.lan"

# Prüfen, ob Installation bereits existiert
INSTALL_FOUND=false

if [ -d "/var/www/nextcloud" ]; then
  echo -e "${YELLOW}Nextcloud-Verzeichnis gefunden.${NC}"
  INSTALL_FOUND=true
fi

if mariadb -e "USE $NEXTCLOUD_DB;" 2>/dev/null; then
  echo -e "${YELLOW}Datenbank $NEXTCLOUD_DB existiert bereits.${NC}"
  INSTALL_FOUND=true
fi

if systemctl is-active --quiet redis; then
  echo -e "${YELLOW}Redis scheint bereits installiert oder aktiv zu sein.${NC}"
  INSTALL_FOUND=true
fi

if [ "$INSTALL_FOUND" = true ]; then
  echo -e "${RED}Eine bestehende Installation wurde erkannt.${NC}"
  read -rp "Möchtest du mit der Bereinigung und Neuinstallation fortfahren? (j/N): " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Jj]$ ]]; then
    echo -e "${GRAY}Abbruch durch Benutzer.${NC}"
    exit 1
  fi

  echo -e "${GRAY}Bereinige alte Installation...${NC}"
  systemctl stop apache2 redis mariadb 2>/dev/null || true
  rm -rf /var/www/nextcloud
  mariadb -e "DROP DATABASE IF EXISTS $NEXTCLOUD_DB;" || true
  mariadb -e "DROP USER IF EXISTS '$NEXTCLOUD_DB_USER'@'localhost';" || true
  apt purge -y redis-server || true
  apt autoremove -y
fi

# System aktualisieren und Pakete installieren
echo -e "${GRAY}Installiere benötigte Pakete...${NC}"
apt update && apt install -y \
  apache2 \
  mariadb-server \
  libapache2-mod-php \
  php \
  php-mysql \
  php-gd \
  php-xml \
  php-curl \
  php-zip \
  php-mbstring \
  php-bz2 \
  php-intl \
  php-bcmath \
  php-gmp \
  php-apcu \
  php-redis \
  redis-server \
  unzip \
  wget \
  curl \
  gnupg2 \
  certbot \
  python3-certbot-apache

# MariaDB vorbereiten
echo -e "${GRAY}Richte MariaDB ein...${NC}"
mariadb -e "CREATE DATABASE $NEXTCLOUD_DB CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
mariadb -e "CREATE USER '$NEXTCLOUD_DB_USER'@'localhost' IDENTIFIED BY '$NEXTCLOUD_DB_PASSWORD';"
mariadb -e "GRANT ALL PRIVILEGES ON $NEXTCLOUD_DB.* TO '$NEXTCLOUD_DB_USER'@'localhost';"
mariadb -e "FLUSH PRIVILEGES;"

# Nextcloud herunterladen
echo -e "${GRAY}Lade Nextcloud herunter...${NC}"
cd /tmp
wget https://download.nextcloud.com/server/releases/latest.zip -O nextcloud.zip
unzip nextcloud.zip
mv nextcloud /var/www/nextcloud
chown -R www-data:www-data /var/www/nextcloud
chmod -R 755 /var/www/nextcloud

# Apache konfigurieren
echo -e "${GRAY}Konfiguriere Apache...${NC}"
cat <<EOF > /etc/apache2/sites-available/nextcloud.conf
<VirtualHost *:80>
    ServerName $DOMAIN
    DocumentRoot /var/www/nextcloud
    <Directory /var/www/nextcloud/>
        Require all granted
        AllowOverride All
        Options FollowSymLinks MultiViews
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/nextcloud_error.log
    CustomLog \${APACHE_LOG_DIR}/nextcloud_access.log combined
</VirtualHost>
EOF

a2ensite nextcloud.conf
a2enmod rewrite headers env dir mime setenvif ssl
systemctl reload apache2

# Let's Encrypt SSL-Zertifikat holen
certbot --apache -d "$DOMAIN" --non-interactive --agree-tos -m admin@$DOMAIN || true

# Nextcloud Installation
sudo -u www-data php /var/www/nextcloud/occ maintenance:install \
  --admin-user "$NEXTCLOUD_ADMIN_USER" \
  --admin-pass "$NEXTCLOUD_ADMIN_PASSWORD" \
  --database "mysql" \
  --database-name "$NEXTCLOUD_DB" \
  --database-user "$NEXTCLOUD_DB_USER" \
  --database-pass "$NEXTCLOUD_DB_PASSWORD"

# Redis-Konfiguration einfügen
echo -e "${GRAY}Füge Redis-Konfiguration zur config.php hinzu...${NC}"
CONFIG_FILE="/var/www/nextcloud/config/config.php"
sed -i "/);/i\  'memcache.local' => '\\OC\\Memcache\\APCu'," "$CONFIG_FILE"
sed -i "/);/i\  'memcache.locking' => '\\OC\\Memcache\\Redis'," "$CONFIG_FILE"
sed -i "/);/i\  'redis' => array (\n    'host' => '/var/run/redis/redis-server.sock',\n  )," "$CONFIG_FILE"

# Abschließende Informationen
echo -e "${GREEN}Nextcloud-Installation abgeschlossen.${NC}"
echo -e "URL: https://$DOMAIN"
echo -e "Admin-Benutzer: $NEXTCLOUD_ADMIN_USER"
echo -e "Admin-Passwort: $NEXTCLOUD_ADMIN_PASSWORD"
echo -e "DB Benutzer: $NEXTCLOUD_DB_USER"
echo -e "DB Passwort: $NEXTCLOUD_DB_PASSWORD"

# Bereinigen
echo -e "${GRAY}Bereinige temporäre Dateien...${NC}"
rm -rf /tmp/nextcloud /tmp/nextcloud.zip

exit 0
