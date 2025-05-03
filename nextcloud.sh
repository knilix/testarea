#!/bin/bash
# Maintainer: @knilix
# Version: 1.0
# Hinweis: Nur für Ubuntu/Debian (x64), root erforderlich

set -e

# === Farben ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

# === Eingabe ===
echo -e "${BLUE}== Nextcloud Setup für Ubuntu/Debian ==${NC}"
read -rp "Domain (z.B. cloud.example.com): " DOMAIN
read -rp "E-Mail fuer Let's Encrypt: " EMAIL

if [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then
  echo -e "${RED}Domain oder E-Mail fehlt. Abbruch.${NC}"
  exit 1
fi

# === Pakete installieren ===
echo -e "${BLUE}[+] Installiere benötigte Pakete...${NC}"
apt update
apt install -y apache2 mariadb-server redis-server ufw fail2ban \
  php php-{cli,gd,xml,mbstring,curl,zip,intl,bcmath,gmp,imagick,redis,mysql} \
  unzip curl wget certbot python3-certbot-apache

# === MariaDB vorbereiten ===
echo -e "${BLUE}[+] Konfiguriere MariaDB...${NC}"
NEXTCLOUD_DB="nextcloud"
NEXTCLOUD_DB_USER="ncuser"
NEXTCLOUD_DB_PASS="$(openssl rand -base64 18)"

# MariaDB Zugriff prüfen und Berechtigungen setzen
mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS $NEXTCLOUD_DB CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '$NEXTCLOUD_DB_USER'@'localhost' IDENTIFIED BY '$NEXTCLOUD_DB_PASS';
GRANT ALL PRIVILEGES ON $NEXTCLOUD_DB.* TO '$NEXTCLOUD_DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

# === Nextcloud herunterladen ===
echo -e "${BLUE}[+] Lade Nextcloud herunter...${NC}"
cd /tmp
wget https://download.nextcloud.com/server/releases/latest.zip -O nextcloud.zip

if [[ ! -f nextcloud.zip ]]; then
  echo -e "${RED}[!] Fehler beim Herunterladen von Nextcloud.${NC}"
  exit 1
fi

unzip nextcloud.zip
rm -rf /var/www/nextcloud
mv nextcloud /var/www/nextcloud
chown -R www-data:www-data /var/www/nextcloud

# === Apache konfigurieren ===
echo -e "${BLUE}[+] Konfiguriere Apache...${NC}"
cat >/etc/apache2/sites-available/nextcloud.conf <<EOF
<VirtualHost *:80>
  ServerName $DOMAIN
  DocumentRoot /var/www/nextcloud
  <Directory /var/www/nextcloud>
    Require all granted
    AllowOverride All
    Options FollowSymLinks MultiViews
  </Directory>
</VirtualHost>
EOF

a2ensite nextcloud
a2enmod rewrite headers env dir mime setenvif ssl
systemctl reload apache2

# === Nextcloud installieren ===
echo -e "${BLUE}[+] Starte Nextcloud Installation...${NC}"
NEXTCLOUD_ADMIN="admin"
NEXTCLOUD_ADMIN_PASS="$(openssl rand -base64 18)"

sudo -u www-data php /var/www/nextcloud/occ maintenance:install \
  --database "mysql" \
  --database-name "$NEXTCLOUD_DB" \
  --database-user "$NEXTCLOUD_DB_USER" \
  --database-pass "$NEXTCLOUD_DB_PASS" \
  --admin-user "$NEXTCLOUD_ADMIN" \
  --admin-pass "$NEXTCLOUD_ADMIN_PASS" \
  --data-dir "/var/www/nextcloud/data"

# === Redis Konfiguration ===
echo -e "${BLUE}[+] Konfiguriere Redis...${NC}"
CONFIG="/var/www/nextcloud/config/config.php"
cp "$CONFIG" "${CONFIG}.bak"

sed -i "/);/i\
  'memcache.local' => '\\\\OC\\\\Memcache\\\\Redis',\n  'memcache.locking' => '\\\\OC\\\\Memcache\\\\Redis',\n  'redis' => array (\n    'host' => '127.0.0.1',\n    'port' => 6379,\n  )," "$CONFIG"

# === Let's Encrypt HTTPS ===
echo -e "${BLUE}[+] Beantrage TLS-Zertifikat...${NC}"
certbot --apache --non-interactive --agree-tos -m "$EMAIL" --redirect -d "$DOMAIN"

# === Firewall & Fail2Ban ===
echo -e "${BLUE}[+] Konfiguriere UFW & Fail2Ban...${NC}"
ufw allow OpenSSH
ufw allow 80,443/tcp
ufw --force enable
systemctl enable --now fail2ban

# === Abschluss ===
echo -e "\n${GREEN}✅ Nextcloud-Installation abgeschlossen!${NC}"
echo -e "${YELLOW}🔗 Zugriff: https://$DOMAIN${NC}"
echo -e "${YELLOW}👤 Admin: $NEXTCLOUD_ADMIN${NC}"
echo -e "${YELLOW}🔑 Passwort: $NEXTCLOUD_ADMIN_PASS${NC}"
echo -e "${YELLOW}🗄️ DB-Passwort: $NEXTCLOUD_DB_PASS${NC}"
echo
