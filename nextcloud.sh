#!/bin/bash
# Maintener: @knilix
# --> Nur für Debian geeignet.

set -e
# === Farben ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

# === Benutzer-Eingaben ===
echo -e "${BLUE}== Nextcloud Setup ==${NC}"
read -rp "Domain (z.B. cloud.example.com): " DOMAIN
read -rp "E-Mail fuer Let's Encrypt: " EMAIL

if [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then
  echo -e "${RED} Domain oder E-Mail fehlt.${NC}"
  exit 1
fi

# === Hilfsfunktionen ===
function install_packages() {
  echo -e "${BLUE}[+] Installiere Pakete fuer Debian...${NC}"
  apt update
  apt install -y apache2 mariadb-server redis-server ufw fail2ban \
    php php-{cli,gd,xml,mbstring,curl,zip,intl,bcmath,gmp,imagick,redis,mysql} \
    unzip curl wget certbot python3-certbot-apache
}

# === Systemerkennung und Paketinstallation ===
DISTRO="debian"
echo -e "${BLUE}[i] Erkanntes System: $DISTRO${NC}"
install_packages "$DISTRO"

# === Datenbank einrichten ===
NEXTCLOUD_DB="nextcloud"
NEXTCLOUD_DB_USER="ncuser"
NEXTCLOUD_DB_PASS="$(openssl rand -base64 18)"

mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS $NEXTCLOUD_DB CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '$NEXTCLOUD_DB_USER'@'localhost' IDENTIFIED BY '$NEXTCLOUD_DB_PASS';
GRANT ALL PRIVILEGES ON $NEXTCLOUD_DB.* TO '$NEXTCLOUD_DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

# === Nextcloud herunterladen und entpacken ===
echo -e "${BLUE}[+] Lade Nextcloud herunter...${NC}"

# Direktes wget verwenden
wget https://download.nextcloud.com/server/releases/latest.zip -O nextcloud.zip

# Prüfen, ob der Download erfolgreich war
if [[ ! -f nextcloud.zip ]]; then
  echo -e "${RED}[!] Fehler: Nextcloud konnte nicht heruntergeladen werden.${NC}"
  exit 1
fi

# Entpacken
unzip nextcloud.zip -d /var/www/
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
systemctl restart apache2

# === Nextcloud installieren ===
echo -e "${BLUE}[+] Fuehre Nextcloud-Installation aus...${NC}"
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

# === Redis konfigurieren ===
echo -e "${BLUE}[+] Konfiguriere Redis...${NC}"
CONFIG="/var/www/nextcloud/config/config.php"
sudo -u www-data php -r "
  \$CONFIG = include '$CONFIG';
  \$CONFIG['memcache.local'] = '\\OC\\Memcache\\Redis';
  \$CONFIG['memcache.locking'] = '\\OC\\Memcache\\Redis';
  \$CONFIG['redis'] = ['host' => '127.0.0.1', 'port' => 6379];
  file_put_contents('$CONFIG', '<?php\nreturn ' . var_export(\$CONFIG, true) . ';');"

# === HTTPS via Let's Encrypt ===
echo -e "${BLUE}[+] Beantrage TLS-Zertifikat...${NC}"
certbot --apache --non-interactive --agree-tos -m "$EMAIL" --redirect -d "$DOMAIN"

# === UFW aktivieren ===
echo -e "${BLUE}[+] Aktiviere Firewall (UFW)...${NC}"
ufw allow OpenSSH
ufw allow 80,443/tcp
ufw --force enable

# === Fail2Ban konfigurieren ===
echo -e "${BLUE}[+] Aktiviere Fail2Ban...${NC}"
systemctl enable --now fail2ban

# === Abschluss ===
echo -e "\n${GREEN} Installation abgeschlossen!${NC}"
echo -e "${YELLOW} Zugriff: https://$DOMAIN${NC}"
echo -e "${YELLOW} Admin: $NEXTCLOUD_ADMIN${NC}"
echo -e "${YELLOW} Passwort: $NEXTCLOUD_ADMIN_PASS${NC}"

