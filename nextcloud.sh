#!/bin/bash
# Maintener: @knilix
# --> Only test - only x64 !
# root user benötigt (su)
# Für Debian, Ubuntu, Alpine, Fedora, Arch, FreeBSD und OpenBSD geeignet.
# Vorher erledigen: 
# - installieren von wget und zip 
#
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
  echo -e "${BLUE}[+] Installiere Pakete fuer $1...${NC}"
  case "$1" in
    debian|ubuntu)
      apt update
      apt install -y apache2 mariadb-server redis-server ufw fail2ban \
        php php-{cli,gd,xml,mbstring,curl,zip,intl,bcmath,gmp,imagick,redis,mysql} \
        unzip curl wget certbot python3-certbot-apache
      ;;
    fedora)
      dnf install -y httpd mariadb-server redis ufw fail2ban \
        php php-{cli,gd,xml,mbstring,curl,zip,intl,bcmath,gmp,imagick,redis,mysqlnd} \
        unzip curl wget certbot mod_ssl
      ;;
    alpine)
      # Überprüfe, ob die richtigen Repositories aktiviert sind
      if ! grep -q 'community' /etc/apk/repositories; then
        echo -e "${YELLOW}[+] Community-Repositories aktivieren...${NC}"
        echo "http://dl-cdn.alpinelinux.org/alpine/v3.18/community" >> /etc/apk/repositories
        apk update
      fi

      apk add php8 php8-fpm php8-opcache php8-mysqli php8-redis php8-curl php8-gd php8-bcmath php8-xml php8-mbstring php8-intl php8-zip php8-gmp php8-imagick \
        apache2 mariadb mariadb-client redis unzip curl wget certbot py3-certbot-apache ufw fail2ban
      rc-update add apache2 default
      rc-update add mariadb default
      rc-update add redis default
      ;;
    arch)
      pacman -Sy --noconfirm apache mariadb redis php php-apache php-gd php-intl php-curl \
        php-zip php-mbstring php-gmp php-imagick php-redis unzip curl wget certbot ufw fail2ban
      ;;
    freebsd|openbsd)
      echo -e "${YELLOW}[!] BSD-Unterstuetzung noch manuell. Bitte manuell Pakete installieren.${NC}"
      exit 1
      ;;
    *)
      echo -e "${RED} Nicht unterstuetzte Distribution: $1${NC}"
      exit 1
      ;;
  esac
}

function detect_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "$ID"
  elif uname -s | grep -q FreeBSD; then
    echo "freebsd"
  elif uname -s | grep -q OpenBSD; then
    echo "openbsd"
  else
    echo "unknown"
  fi
}

# === Systemerkennung und Paketinstallation ===
DISTRO=$(detect_distro)
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

# === Nextcloud holen und entpacken ===
echo -e "${BLUE}[+] Lade Nextcloud herunter...${NC}"
cd /tmp
LATEST_URL=$(curl -s https://nextcloud.com/install | grep -oP 'https://download\.nextcloud\.com/server/releases/nextcloud-[0-9.]+\.zip' | head -n1)
wget "$LATEST_URL"
unzip nextcloud-*.zip -d /var/www/
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
  </
