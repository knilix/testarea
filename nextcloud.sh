#!/bin/bash

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

set -e

# Variablen
NEXTCLOUD_DB="nextcloud"
NEXTCLOUD_DB_USER="ncuser"
NEXTCLOUD_DB_PASS="$(openssl rand -base64 18)"
NEXTCLOUD_ADMIN_USER="admin"
NEXTCLOUD_ADMIN_PASS="$(openssl rand -base64 18)"
NEXTCLOUD_DATA_DIR="/var/www/nextcloud/data"
NEXTCLOUD_DIR="/var/www/nextcloud"

# Passwort zur Kontrolle speichern
echo "$NEXTCLOUD_DB_PASS" > /root/nextcloud-db-pass.txt
echo "$NEXTCLOUD_ADMIN_PASS" > /root/nextcloud-admin-pass.txt

# System erkennen
if [ -f /etc/debian_version ]; then
  DISTRO="debian"
elif [ -f /etc/lsb-release ]; then
  DISTRO="ubuntu"
else
  echo -e "${RED}[-] Nicht unterstützte Distribution${NC}"
  exit 1
fi

echo -e "${BLUE}[i] Erkanntes System: $DISTRO${NC}"
echo -e "${BLUE}[+] Installiere Pakete für $DISTRO...${NC}"

apt-get update
apt-get install -y apache2 mariadb-server redis-server ufw fail2ban \
  php php-cli php-gd php-xml php-mbstring php-curl php-zip php-intl php-bcmath php-gmp php-imagick php-redis php-mysql \
  unzip curl wget certbot python3-certbot-apache

# Nextcloud herunterladen
echo -e "${BLUE}[+] Lade Nextcloud herunter...${NC}"
cd /var/www
wget https://download.nextcloud.com/server/releases/latest.zip
unzip latest.zip
chown -R www-data:www-data nextcloud
chmod -R 755 nextcloud

# Apache konfigurieren
echo -e "${BLUE}[+] Konfiguriere Apache...${NC}"
cat >/etc/apache2/sites-available/nextcloud.conf <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/nextcloud
    <Directory /var/www/nextcloud>
        Require all granted
        AllowOverride All
        Options FollowSymLinks MultiViews
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

a2ensite nextcloud.conf
a2enmod rewrite headers env dir mime ssl
systemctl reload apache2

# HTTPS mit Certbot
echo -e "${BLUE}[+] Richte HTTPS mit Let's Encrypt ein...${NC}"
certbot --apache --non-interactive --agree-tos -m admin@example.com -d your.domain.com || echo -e "${RED}[-] Certbot fehlgeschlagen. Bitte manuell prüfen.${NC}"

# MariaDB konfigurieren
echo -e "${BLUE}[+] Konfiguriere MariaDB...${NC}"
mysql -u root -e "DROP USER IF EXISTS '$NEXTCLOUD_DB_USER'@'localhost';"
mysql -u root -e "CREATE USER '$NEXTCLOUD_DB_USER'@'localhost' IDENTIFIED BY '${NEXTCLOUD_DB_PASS}';"
mysql -u root -e "CREATE DATABASE IF NOT EXISTS ${NEXTCLOUD_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
mysql -u root -e "GRANT ALL PRIVILEGES ON ${NEXTCLOUD_DB}.* TO '${NEXTCLOUD_DB_USER}'@'localhost';"
mysql -u root -e "FLUSH PRIVILEGES;"

# Redis konfigurieren
sed -i "s/^;session.save_handler.*/session.save_handler = redis/" /etc/php/*/apache2/php.ini
sed -i "s|^;session.save_path.*|session.save_path = \"tcp://127.0.0.1:6379\"|" /etc/php/*/apache2/php.ini
systemctl restart apache2

# Nextcloud installieren
echo -e "${BLUE}[+] Starte Nextcloud Installation...${NC}"
sudo -u www-data php ${NEXTCLOUD_DIR}/occ maintenance:install \
  --database "mysql" \
  --database-name "${NEXTCLOUD_DB}" \
  --database-user "${NEXTCLOUD_DB_USER}" \
  --database-pass "${NEXTCLOUD_DB_PASS}" \
  --admin-user "${NEXTCLOUD_ADMIN_USER}" \
  --admin-pass "${NEXTCLOUD_ADMIN_PASS}" \
  --data-dir "${NEXTCLOUD_DATA_DIR}"

# UFW konfigurieren
echo -e "${BLUE}[+] Konfiguriere Firewall...${NC}"
ufw allow OpenSSH
ufw allow 'Apache Full'
ufw --force enable

# Fail2Ban aktivieren
echo -e "${BLUE}[+] Aktiviere Fail2Ban...${NC}"
systemctl enable fail2ban --now

# Abschlussmeldung
echo -e "${GREEN}[✓] Nextcloud erfolgreich installiert!${NC}"
echo -e "${GREEN}Admin-Benutzer: ${NEXTCLOUD_ADMIN_USER}${NC}"
echo -e "${GREEN}Admin-Passwort: $(cat /root/nextcloud-admin-pass.txt)${NC}"
echo -e "${GREEN}DB-Benutzer: ${NEXTCLOUD_DB_USER}${NC}"
echo -e "${GREEN}DB-Passwort: $(cat /root/nextcloud-db-pass.txt)${NC}"
