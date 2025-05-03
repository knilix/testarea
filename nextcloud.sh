#!/bin/bash
# Maintainer: @knilix
# Für Ubuntu (x64). Root-Rechte erforderlich.

set -e

# === Farben ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

# === Parameter-Parsing ===
for arg in "$@"; do
  case $arg in
    --domain=*)
      DOMAIN="${arg#*=}"
      shift
      ;;
    --email=*)
      EMAIL="${arg#*=}"
      shift
      ;;
    *)
      ;;
  esac
done

# === Benutzer-Eingaben ===
if [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then
  echo -e "${BLUE}== Nextcloud Setup (interaktiv) ==${NC}"
  [[ -z "$DOMAIN" ]] && read -rp "Domain (z.B. cloud.example.com): " DOMAIN
  [[ -z "$EMAIL" ]] && read -rp "E-Mail für Let's Encrypt: " EMAIL
fi

if [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then
  echo -e "${RED}Fehler: Domain oder E-Mail fehlt.${NC}"
  exit 1
fi

# === Pakete installieren ===
echo -e "${BLUE}[+] Installiere Pakete...${NC}"
apt update
apt install -y apache2 mariadb-server redis-server ufw fail2ban unzip curl wget software-properties-common \
  php php-cli php-gd php-xml php-mbstring php-curl php-zip php-intl php-bcmath php-gmp php-imagick php-redis php-mysql \
  certbot python3-certbot-apache

# === Datenbank einrichten ===
echo -e "${BLUE}[+] Erstelle Nextcloud-Datenbank...${NC}"
NEXTCLOUD_DB="nextcloud"
NEXTCLOUD_DB_USER="ncuser"
NEXTCLOUD_DB_PASS="$(openssl rand -base64 18)"

mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS $NEXTCLOUD_DB CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '$NEXTCLOUD_DB_USER'@'localhost' IDENTIFIED BY '$NEXTCLOUD_DB_PASS';
GRANT ALL PRIVILEGES ON $NEXTCLOUD_DB.* TO '$NEXTCLOUD_DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

# === Nextcloud herunterladen ===
echo -e "${BLUE}[+] Lade Nextcloud herunter...${NC}"
wget https://download.nextcloud.com/server/releases/latest.zip -O nextcloud.zip

if [[ ! -f nextcloud.zip ]]; then
  echo -e "${RED}[!] Fehler: Download fehlgeschlagen.${NC}"
  exit 1
fi

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
systemctl reload apache2

# === Nextcloud installieren ===
echo -e "${BLUE}[+] Installiere Nextcloud...${NC}"
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

# === HTTPS mit Let's Encrypt ===
echo -e "${BLUE}[+] Beantrage TLS-Zertifikat...${NC}"
certbot --apache --non-interactive --agree-tos -m "$EMAIL" --redirect -d "$DOMAIN"

# === Firewall aktivieren ===
echo -e "${BLUE}[+] Aktiviere Firewall (UFW)...${NC}"
ufw allow OpenSSH
ufw allow 80,443/tcp
ufw --force enable

# === Fail2Ban starten ===
echo -e "${BLUE}[+] Aktiviere Fail2Ban...${NC}"
systemctl enable --now fail2ban

# === Abschluss ===
echo
echo -e "${GREEN}Installation abgeschlossen!${NC}"
echo -e "${YELLOW}Zugriff: https://$DOMAIN${NC}"
echo -e "${YELLOW}Admin: $NEXTCLOUD_ADMIN${NC}"
echo -e "${YELLOW}Passwort: $NEXTCLOUD_ADMIN_PASS${NC}"
echo -e "${YELLOW}Datenbank-Passwort: $NEXTCLOUD_DB_PASS${NC}"


