#!/bin/bash
# Maintainer: @knilix (Original), erweitert für Debian und Ubuntu
# Version: 1.0
# Hinweis: Für Debian 12 und Ubuntu ab 22.04+ (x64), root erforderlich

# Fehler-Handling und Farbdefinitionen
set -e
trap 'echo "Ein Fehler ist aufgetreten. Installation wurde abgebrochen."' ERR
GREEN='\033[0;32m'; BLUE='\033[0;34m'; RED='\033[0;31m'; GRAY='\033[0;37m'; NC='\033[0m'

# Root-Prüfung
[ "$EUID" -ne 0 ] && { echo -e "${RED}Bitte führen Sie das Script als root aus.${NC}"; exit 1; }

# Betriebssystem erkennen und prüfen
[ ! -f /etc/os-release ] && { echo -e "${RED}Konnte Betriebssystem nicht erkennen.${NC}"; exit 1; }

# OS-Typ bestimmen
if grep -q "Ubuntu" /etc/os-release; then
  OS_TYPE="Ubuntu"
  OS_VERSION=$(grep -oP '(?<=VERSION_ID=").*?(?=")' /etc/os-release)
  (( $(echo "$OS_VERSION < 22.04" | bc -l) )) && { echo -e "${RED}Benötigt Ubuntu 22.04+. Version: $OS_VERSION${NC}"; exit 1; }
  echo -e "${BLUE}Ubuntu $OS_VERSION erkannt. Fahre fort...${NC}"
elif grep -q "Debian" /etc/os-release; then
  OS_TYPE="Debian"
  OS_VERSION=$(grep -oP '(?<=VERSION_ID=").*?(?=")' /etc/os-release)
  (( $(echo "$OS_VERSION < 12" | bc -l) )) && { echo -e "${RED}Benötigt Debian 12+. Version: $OS_VERSION${NC}"; exit 1; }
  echo -e "${BLUE}Debian $OS_VERSION erkannt. Fahre fort...${NC}"
else
  echo -e "${RED}Dieses Script unterstützt nur Debian oder Ubuntu.${NC}"; exit 1
fi

# Konfigurationsparameter
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
NEXTCLOUD_DB_PASSWORD=$(openssl rand -base64 32)
NEXTCLOUD_DB_NAME="nextcloud"
NEXTCLOUD_DB_USER="nextcloud"
NEXTCLOUD_ADMIN_USER="admin"
NEXTCLOUD_ADMIN_PASSWORD=$(openssl rand -base64 24)
NEXTCLOUD_DATA_DIR="/var/www/nextcloud/data"
CREDENTIALS_FILE="/root/.nextcloud_credentials"
SERVER_IP=$(hostname -I | awk '{print $1}')
DOMAIN_NAME=$(hostname -f)
[ "$DOMAIN_NAME" = "localhost" ] || [ -z "$DOMAIN_NAME" ] && DOMAIN_NAME=$SERVER_IP

# Installationsinfo anzeigen
clear
echo -e "${BLUE}=== Nextcloud Installationsscript für $OS_TYPE ====${NC}"
echo -e "${BLUE}Dieses Script installiert Nextcloud mit MariaDB und Redis.${NC}\n"
echo -e "${GREEN}Installationsparameter:${NC}"
echo -e "IP-Adresse: ${GREEN}$SERVER_IP${NC}"
echo -e "Admin Benutzer: ${GREEN}$NEXTCLOUD_ADMIN_USER${NC}"
echo -e "Datenbank: ${GREEN}$NEXTCLOUD_DB_NAME${NC}\n"

# Bestätigung 
read -p "Installation starten? (j/n): " CONFIRM
[[ $CONFIRM != "j" && $CONFIRM != "J" ]] && { echo "Installation abgebrochen."; exit 0; }

# System aktualisieren und Pakete installieren
echo -e "${BLUE}[1/10] System wird aktualisiert...${NC}"
apt update && apt upgrade -y

echo -e "${BLUE}[2/10] Benötigte Pakete werden installiert...${NC}"
apt install -y bc apache2 mariadb-server redis-server php php-cli php-common php-fpm php-json \
  php-intl php-imagick php-curl php-mbstring php-zip php-xml php-gd php-mysql php-bz2 \
  php-redis php-apcu unzip curl wget ssl-cert pv libmagickcore-6.q16-6-extra

# Apache für PHP konfigurieren
echo -e "${BLUE}[3/10] Apache für PHP konfigurieren...${NC}"
a2enmod rewrite headers env dir mime ssl

# PHP-Version und Konfiguration
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
if [ -f "/etc/apache2/conf-available/php${PHP_VERSION}-fpm.conf" ]; then
  a2enconf "php${PHP_VERSION}-fpm"
else
  a2enmod proxy_fcgi setenvif
  a2enconf php${PHP_VERSION}-fpm
fi
systemctl restart apache2

# MariaDB konfigurieren
echo -e "${BLUE}[4/10] MariaDB wird konfiguriert...${NC}"
config_mariadb() {
  local passwd_param=""
  [ "$OS_TYPE" = "Ubuntu" ] && passwd_param="-u root -p\"${MYSQL_ROOT_PASSWORD}\""
  
  # Setze Root-Passwort entsprechend OS-Typ
  if [ "$OS_TYPE" = "Debian" ]; then
    mysql -e "SET PASSWORD FOR root@localhost = PASSWORD('${MYSQL_ROOT_PASSWORD}');"
  else
    if mysql -e "SELECT 1;" &>/dev/null; then
      mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
    else
      mysqladmin -u root password "${MYSQL_ROOT_PASSWORD}" || true
    fi
  fi
  
  # Datenbank Sicherheitseinstellungen
  eval "mysql $passwd_param -e \"DELETE FROM mysql.user WHERE User='';\""
  eval "mysql $passwd_param -e \"DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');\""
  eval "mysql $passwd_param -e \"DROP DATABASE IF EXISTS test;\""
  eval "mysql $passwd_param -e \"DELETE FROM mysql.db WHERE Db='test' OR Db='test\\\_%';\""
  
  # Nextcloud DB erstellen
  local db_exists=$(eval "mysql $passwd_param -e \"SHOW DATABASES LIKE '${NEXTCLOUD_DB_NAME}';\"" | grep -o "${NEXTCLOUD_DB_NAME}" || echo "")
  [ -z "$db_exists" ] && eval "mysql $passwd_param -e \"CREATE DATABASE ${NEXTCLOUD_DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;\""
  
  # Nextcloud DB-User erstellen
  local user_exists=$(eval "mysql $passwd_param -e \"SELECT User FROM mysql.user WHERE User='${NEXTCLOUD_DB_USER}';\"" | grep -o "${NEXTCLOUD_DB_USER}" || echo "")
  [ -z "$user_exists" ] && eval "mysql $passwd_param -e \"CREATE USER '${NEXTCLOUD_DB_USER}'@'localhost' IDENTIFIED BY '${NEXTCLOUD_DB_PASSWORD}';\""
  
  # Rechte zuweisen
  eval "mysql $passwd_param -e \"GRANT ALL PRIVILEGES ON ${NEXTCLOUD_DB_NAME}.* TO '${NEXTCLOUD_DB_USER}'@'localhost';\""
  eval "mysql $passwd_param -e \"FLUSH PRIVILEGES;\""
}
config_mariadb

# MariaDB-Konfigurationspfad bestimmen
MARIADB_CONF_DIR="/etc/mysql/mariadb.conf.d"
[ ! -d "$MARIADB_CONF_DIR" ] && { 
  [ -d "/etc/mysql/conf.d" ] && MARIADB_CONF_DIR="/etc/mysql/conf.d" || mkdir -p "$MARIADB_CONF_DIR"
}

# MariaDB-Konfiguration für Nextcloud
cat > "${MARIADB_CONF_DIR}/99-nextcloud.cnf" << EOF
[mysqld]
transaction_isolation = READ-COMMITTED
binlog_format = ROW
innodb_large_prefix=on
innodb_file_format=barracuda
innodb_file_per_table=1
max_allowed_packet = 128M
EOF

# MariaDB neustarten
systemctl list-units --type=service | grep -q "mariadb.service" && systemctl restart mariadb || systemctl restart mysql

# Redis konfigurieren
echo -e "${BLUE}[5/10] Redis wird konfiguriert...${NC}"
REDIS_CONF=$([ -f "/etc/redis/redis.conf" ] && echo "/etc/redis/redis.conf" || echo "/etc/redis/redis-server.conf")
[ ! -f "$REDIS_CONF" ] && { echo -e "${RED}Redis-Konfigurationsdatei nicht gefunden.${NC}"; exit 1; }

# Redis anpassen
sed -i "s/port 6379/port 0/" $REDIS_CONF
sed -i "s/# unixsocket/unixsocket/" $REDIS_CONF
sed -i "s/# unixsocketperm 700/unixsocketperm 770/" $REDIS_CONF
sed -i "s/^unixsocketperm 700/unixsocketperm 770/" $REDIS_CONF 2>/dev/null || true
usermod -a -G redis www-data

# Redis neustarten
if systemctl list-units --type=service | grep -q "redis-server.service"; then
  systemctl restart redis-server
elif systemctl list-units --type=service | grep -q "redis.service"; then
  systemctl restart redis
else
  echo -e "${RED}Redis-Service nicht gefunden.${NC}"; exit 1
fi

# PHP für Nextcloud optimieren
echo -e "${BLUE}[6/10] PHP-Konfiguration für Nextcloud optimieren...${NC}"
php_config='memory_limit = 512M
upload_max_filesize = 500M
post_max_size = 500M
max_execution_time = 300
date.timezone = Europe/Berlin

opcache.enable=1
opcache.interned_strings_buffer=32
opcache.max_accelerated_files=10000
opcache.memory_consumption=128
opcache.save_comments=1
opcache.revalidate_freq=1'

for sapi in fpm cli apache2; do
  if [ -d "/etc/php/${PHP_VERSION}/$sapi/conf.d" ]; then
    echo -e "${BLUE}→ PHP-SAPI: $sapi wird konfiguriert...${NC}"
    echo "$php_config" > "/etc/php/${PHP_VERSION}/$sapi/conf.d/99-nextcloud.ini"
  fi
done

# PHP-FPM neustarten
systemctl list-units --type=service | grep -q "php${PHP_VERSION}-fpm" && { 
  echo -e "${BLUE}→ PHP-FPM wird neu gestartet...${NC}"
  systemctl restart php${PHP_VERSION}-fpm
}

# Apache Virtual Host konfigurieren
echo -e "${BLUE}[7/10] Apache Virtual Host für Nextcloud wird konfiguriert...${NC}"
mkdir -p /etc/ssl/nextcloud/
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/nextcloud/nextcloud.key \
  -out /etc/ssl/nextcloud/nextcloud.crt \
  -subj "/CN=${DOMAIN_NAME}/O=Nextcloud/C=DE"

cat > /etc/apache2/sites-available/nextcloud.conf << EOF
<VirtualHost *:80>
    ServerName ${DOMAIN_NAME}
    Redirect permanent / https://${DOMAIN_NAME}/
</VirtualHost>

<VirtualHost *:443>
    ServerName ${DOMAIN_NAME}
    DocumentRoot /var/www/nextcloud
    SSLEngine on
    SSLCertificateFile /etc/ssl/nextcloud/nextcloud.crt
    SSLCertificateKeyFile /etc/ssl/nextcloud/nextcloud.key

    <IfModule mod_headers.c>
        Header always set Strict-Transport-Security "max-age=15552000; includeSubDomains"
    </IfModule>

    <Directory /var/www/nextcloud>
        Options +FollowSymlinks
        AllowOverride All
        Require all granted
        <IfModule mod_dav.c>
            Dav off
        </IfModule>
        SetEnv HOME /var/www/nextcloud
        SetEnv HTTP_HOME /var/www/nextcloud
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/nextcloud_error.log
    CustomLog \${APACHE_LOG_DIR}/nextcloud_access.log combined
</VirtualHost>
EOF

a2enmod headers ssl
a2ensite nextcloud.conf
systemctl reload apache2

# Nextcloud installieren
echo -e "${BLUE}[8/10] Nextcloud wird heruntergeladen und installiert...${NC}"
wget -q https://download.nextcloud.com/server/releases/latest.zip -O /tmp/nextcloud.zip
unzip -q /tmp/nextcloud.zip -d /var/www/
rm /tmp/nextcloud.zip
mkdir -p "${NEXTCLOUD_DATA_DIR}"
chown -R www-data:www-data /var/www/nextcloud/ "${NEXTCLOUD_DATA_DIR}"

# Initialisieren
echo -e "${BLUE}[9/10] Nextcloud wird initialisiert...${NC}"
cd /var/www/nextcloud
sudo -u www-data php occ maintenance:install \
  --database "mysql" --database-name "${NEXTCLOUD_DB_NAME}" \
  --database-user "${NEXTCLOUD_DB_USER}" --database-pass "${NEXTCLOUD_DB_PASSWORD}" \
  --admin-user "${NEXTCLOUD_ADMIN_USER}" --admin-pass "${NEXTCLOUD_ADMIN_PASSWORD}" \
  --data-dir "${NEXTCLOUD_DATA_DIR}"

# Nextcloud konfigurieren
configure_nc() {
  local configs=(
    "trusted_domains 0 --value=\"${DOMAIN_NAME}\""
    "trusted_domains 1 --value=\"${SERVER_IP}\""
    "memcache.local --value='\OC\Memcache\APCu'"
    "memcache.locking --value='\OC\Memcache\Redis'"
    "redis host --value='/var/run/redis/redis-server.sock'"
    "redis port --value=0"
    "redis timeout --value=0.0"
    "trusted_proxies 0 --value=\"127.0.0.1\""
    "overwriteprotocol --value=\"https\""
    "htaccess.RewriteBase --value=\"/\""
  )
  
  for config in "${configs[@]}"; do
    sudo -u www-data php occ config:system:set $config
  done
  
  sudo -u www-data php occ maintenance:update:htaccess
}
configure_nc

# Cronjob einrichten
echo "*/5 * * * * www-data php -f /var/www/nextcloud/cron.php" > /etc/cron.d/nextcloud
sudo -u www-data php occ background:cron

# Zugangsdaten speichern
cat > "${CREDENTIALS_FILE}" << EOF
NEXTCLOUD_URL_DOMAIN=https://${DOMAIN_NAME}
NEXTCLOUD_URL_IP=https://${SERVER_IP}
NEXTCLOUD_ADMIN_USER=${NEXTCLOUD_ADMIN_USER}
NEXTCLOUD_ADMIN_PASSWORD=${NEXTCLOUD_ADMIN_PASSWORD}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
NEXTCLOUD_DB_NAME=${NEXTCLOUD_DB_NAME}
NEXTCLOUD_DB_USER=${NEXTCLOUD_DB_USER}
NEXTCLOUD_DB_PASSWORD=${NEXTCLOUD_DB_PASSWORD}
INSTALLATION_DATE=$(date +"%Y-%m-%d %H:%M:%S")
EOF
chmod 600 "${CREDENTIALS_FILE}"

# Anmeldedaten anzeigen Befehl
cat > /usr/local/bin/nextcloud-credentials << 'EOF'
#!/bin/bash
[ "$EUID" -ne 0 ] && { echo "Bitte als root ausführen (sudo nextcloud-credentials)"; exit 1; }

CRED_FILE="/root/.nextcloud_credentials"
[ ! -f "$CRED_FILE" ] && { echo "Keine Nextcloud-Anmeldedaten gefunden!"; exit 1; }

source "$CRED_FILE"
GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'

echo -e "${BLUE}===== Nextcloud Zugangsdaten =====\n${NC}"
echo -e "Nextcloud URL (Domain): ${GREEN}${NEXTCLOUD_URL_DOMAIN}${NC}"
echo -e "Nextcloud URL (IP): ${GREEN}${NEXTCLOUD_URL_IP}${NC}"
echo -e "Admin Benutzer: ${GREEN}${NEXTCLOUD_ADMIN_USER}${NC}"
echo -e "Admin Passwort: ${GREEN}${NEXTCLOUD_ADMIN_PASSWORD}${NC}"
echo -e "\n${BLUE}MariaDB Datenbank:${NC}"
echo -e "Root Passwort: ${GREEN}${MYSQL_ROOT_PASSWORD}${NC}"
echo -e "Datenbank: ${GREEN}${NEXTCLOUD_DB_NAME}${NC}"
echo -e "DB Benutzer: ${GREEN}${NEXTCLOUD_DB_USER}${NC}" 
echo -e "DB Passwort: ${GREEN}${NEXTCLOUD_DB_PASSWORD}${NC}"
echo -e "\nInstalliert am: ${GREEN}${INSTALLATION_DATE}${NC}"
EOF
chmod +x /usr/local/bin/nextcloud-credentials

# Zusatz: Nextcloud Konfiguration
echo "Füge Nextcloud Konfiguration hinzu"
config_file="/var/www/nextcloud/config/config.php"
if [ -f "$config_file" ]; then
  tmp_file=$(mktemp)
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
  ' "$config_file" > "$tmp_file"
  cp "$config_file" "${config_file}.bak"
  cp "$tmp_file" "$config_file"
  rm "$tmp_file"
fi

# PHP-Module für Nextcloud
install_modules() {
  local needs_update=false
  has_php_module() { php -m | grep -iq "^$1\$"; }
  has_imagick_svg_support() { 
    php -r "if (extension_loaded('imagick')) { \$v = new Imagick(); echo in_array('SVG', \$v->queryFormats()) ? 'yes' : 'no'; } else { echo 'no'; }" 
  }
  
  has_php_module "gmp" || { apt-get install -y "php${PHP_VERSION}-gmp"; needs_update=true; }
  
  if ! has_php_module "imagick"; then
    apt-get install -y "php${PHP_VERSION}-imagick" libmagickcore-6.q16-6-extra
    needs_update=true
  elif [ "$(has_imagick_svg_support)" != "yes" ]; then
    apt-get install -y libmagickcore-6.q16-6-extra
    needs_update=true
  fi
  
  $needs_update && {
    systemctl list-units --type=service | grep -q "apache2.service" && systemctl reload apache2
    systemctl list-units --type=service | grep -q "php${PHP_VERSION}-fpm.service" && systemctl restart "php${PHP_VERSION}-fpm"
  }
}
apt-get update -qq
install_modules

# Feinschliff
sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --on
sudo -u www-data php occ maintenance:repair --include-expensive
sudo systemctl restart apache2

echo "Warte, bis der Webserver vollständig hochgefahren ist..."
for i in {1..10}; do echo -n "#"; sleep 1; done
echo

rm -f /var/www/nextcloud/data/nextcloud.log
curl -s -o /dev/null http://localhost || true
sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --off

# Bereinigen
rm -rf /opt/scriptfiles/testarea-main /opt/main.zip 2>/dev/null || true

# Abschlussmeldung
clear
echo -e "${BLUE}===== Nextcloud Zugangsdaten =====\n${NC}"
echo -e "\n${BLUE}Zugangsdaten:${NC}"
echo -e "Admin Benutzer: ${GREEN}${NEXTCLOUD_ADMIN_USER}${NC}"
echo -e "Admin Passwort: ${GREEN}${NEXTCLOUD_ADMIN_PASSWORD}${NC}"
echo
echo -e "${GREEN}===== Nextcloud Installation abgeschlossen! =====${NC}"
echo -e "Anmeldung unter folgendem Link:\n"
echo -e "IP:     ${BLUE}https://${SERVER_IP}${NC}"
echo -e "\nBenutzen Sie den Befehl ${GREEN}nextcloud-credentials${NC}, um Ihre kompletten Zugangsdaten anzuzeigen."
echo
