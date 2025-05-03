#!/bin/bash
# Maintainer: @Knilix
# Beschreibung: Installiert Nextcloud, MariaDB, Redis, Apache2 mit Let's Encrypt in einem Debian-LXC-Container
# Hinweis: Bestehende Installationen von Nextcloud, Redis oder MariaDB (nextcloud DB) werden erkannt und erfordern Bestätigung zur Löschung

# TEST ONLY!!!

set -e

# Farben
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
GRAY="\e[90m"
NC="\e[0m"

# Konfig
NEXTCLOUD_DB="nextcloud"
NEXTCLOUD_DB_USER="nextcloud"
NEXTCLOUD_DB_PASS="$(openssl rand -base64 32)"
NEXTCLOUD_URL="nextcloud-script.home.lan"
DATADIR="/var/www/nextcloud/data"
NC_ADMIN_USER="admin"
NC_ADMIN_PASS="$(openssl rand -base64 16)"

# Vorbereitungen
apt update && apt install -y sudo curl wget unzip gnupg2 software-properties-common lsb-release ca-certificates apt-transport-https lsb-release ufw fail2ban

# Bestehende Installationen prüfen
bestehend=false

echo -e "${YELLOW}Prüfe auf bestehende Installationen...${NC}"
if [ -d "/var/www/nextcloud" ]; then
  echo -e "${RED}Vorhandene Nextcloud-Installation erkannt in /var/www/nextcloud${NC}"
  bestehend=true
fi

if mariadb -e "USE ${NEXTCLOUD_DB};" 2>/dev/null; then
  echo -e "${RED}Datenbank '${NEXTCLOUD_DB}' ist bereits vorhanden${NC}"
  bestehend=true
  NEXTCLOUD_DB="nextcloud1"
  echo -e "${YELLOW}Wechsle auf neue Datenbank: ${NEXTCLOUD_DB}${NC}"
fi

if [ -S /var/run/redis/redis-server.sock ]; then
  echo -e "${RED}Redis scheint bereits installiert zu sein${NC}"
  bestehend=true
fi

if [ "$bestehend" = true ]; then
  echo -e "${YELLOW}Eine oder mehrere Komponenten sind bereits installiert.${NC}"
  read -rp "Möchtest du diese Installationen entfernen und fortfahren? (j/n): " confirm
  if [[ ! "$confirm" =~ ^[Jj]$ ]]; then
    echo -e "${RED}Abbruch durch Benutzer.${NC}"
    exit 1
  fi
  echo -e "${GRAY}Bereinige alte Installation...${NC}"
  systemctl stop apache2 mariadb redis-server || true
  rm -rf /var/www/nextcloud
  mariadb -e "DROP DATABASE IF EXISTS ${NEXTCLOUD_DB}; DROP USER IF EXISTS '${NEXTCLOUD_DB_USER}'@'localhost';" || true
  apt purge -y redis-server mariadb-server || true
  apt autoremove -y
  rm -rf /etc/redis /var/lib/mysql /var/run/redis
fi

# Apache & PHP
apt install -y apache2 libapache2-mod-php php php-gd php-json php-mysql php-curl php-mbstring php-intl php-imagick php-xml php-zip php-bcmath php-gmp php-apcu php-redis

# MariaDB
apt install -y mariadb-server
systemctl enable mariadb --now

# Nextcloud DB
mariadb -e "CREATE DATABASE ${NEXTCLOUD_DB};"
mariadb -e "CREATE USER '${NEXTCLOUD_DB_USER}'@'localhost' IDENTIFIED BY '${NEXTCLOUD_DB_PASS}';"
mariadb -e "GRANT ALL PRIVILEGES ON ${NEXTCLOUD_DB}.* TO '${NEXTCLOUD_DB_USER}'@'localhost';"
mariadb -e "FLUSH PRIVILEGES;"

# Redis
apt install -y redis-server
usermod -aG redis www-data
systemctl enable redis-server --now

# SSL-Zertifikat
apt install -y certbot python3-certbot-apache
certbot --apache --noninteractive --agree-tos -m admin@${NEXTCLOUD_URL} -d ${NEXTCLOUD_URL} || true

# Nextcloud herunterladen
cd /opt
wget https://download.nextcloud.com/server/releases/latest.zip -O main.zip
unzip main.zip
rm main.zip
mv nextcloud /var/www/
chown -R www-data:www-data /var/www/nextcloud

# Apache konfigurieren
cat <<EOF >/etc/apache2/sites-available/nextcloud.conf
<VirtualHost *:80>
    ServerName ${NEXTCLOUD_URL}
    Redirect permanent / https://${NEXTCLOUD_URL}/
</VirtualHost>

<VirtualHost *:443>
    ServerName ${NEXTCLOUD_URL}

    DocumentRoot /var/www/nextcloud
    <Directory /var/www/nextcloud/>
        Require all granted
        AllowOverride All
        Options FollowSymLinks MultiViews
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/nextcloud_error.log
    CustomLog \${APACHE_LOG_DIR}/nextcloud_access.log combined

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/${NEXTCLOUD_URL}/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/${NEXTCLOUD_URL}/privkey.pem
</VirtualHost>
EOF

a2ensite nextcloud.conf
a2enmod rewrite headers env dir mime ssl
systemctl reload apache2

# Nextcloud installieren (occ)
sudo -u www-data php /var/www/nextcloud/occ maintenance:install \
  --database "mysql" \
  --database-name "$NEXTCLOUD_DB" \
  --database-user "$NEXTCLOUD_DB_USER" \
  --database-pass "$NEXTCLOUD_DB_PASS" \
  --admin-user "$NC_ADMIN_USER" \
  --admin-pass "$NC_ADMIN_PASS"

# Nextcloud Konfiguration
sudo -u www-data php /var/www/nextcloud/occ config:system:set trusted_domains 1 --value=${NEXTCLOUD_URL}
sudo -u www-data php /var/www/nextcloud/occ config:system:set trusted_domains 2 --value=$(hostname -I | awk '{print $1}')
sudo -u www-data php /var/www/nextcloud/occ config:system:set overwrite.cli.url --value=https://${NEXTCLOUD_URL}
sudo -u www-data php /var/www/nextcloud/occ config:system:set memcache.local --value='\OC\Memcache\APCu'
sudo -u www-data php /var/www/nextcloud/occ config:system:set memcache.locking --value='\OC\Memcache\Redis'
sudo -u www-data php /var/www/nextcloud/occ config:system:set redis host --value=/var/run/redis/redis-server.sock
sudo -u www-data php /var/www/nextcloud/occ config:system:set redis port --value=0 --type=integer

# Firewall und Fail2ban (optional aktiviert)
ufw allow OpenSSH
ufw allow http
ufw allow https
ufw --force enable
systemctl enable fail2ban --now

# Bereinigung
echo -e "${GRAY}Bereinige temporäre Dateien...${NC}"
rm -rf /opt/scriptfiles/testarea-main /opt/main.zip 2>/dev/null || true

# Abschluss
clear
echo -e "${GREEN}Nextcloud erfolgreich installiert unter: https://${NEXTCLOUD_URL}${NC}"
echo -e "${GREEN}Admin: ${NC_ADMIN_USER}${NC}, Passwort: ${NC_ADMIN_PASS}${NC}"
echo -e "${GREEN}Datenbank: ${NEXTCLOUD_DB}, User: ${NEXTCLOUD_DB_USER}${NC}"

