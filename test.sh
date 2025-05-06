#!/bin/bash
# Maintainer: @knilix
# Version: 1.1
# Installation von Nextcloud mit MariaDB und Redis Cache
# Hinweis: Für Debian 12, Ubuntu ab 22.04+ (x64) und Alpine Linux, root erforderlich
#
# wget -q -P /opt/ https://github.com/knilix/testarea/archive/refs/heads/main.zip && unzip /opt/main.zip -d /opt/scriptfiles && chmod 700 /opt/scriptfiles/testarea-main/test.sh
# cd && cd /opt/scriptfiles/testarea-main && ./test.sh
#
# Script nur einmalig ausführen - Abfrage einer vorhandenen Nextcloud-Datenbank noch nicht implementiert!
# -----------------------------------------------------------------------------
# 1. Fehler-Handling und Farben
set -e
trap 'echo "Ein Fehler ist aufgetreten. Installation wurde abgebrochen."' ERR
GREEN='\033[0;32m'; BLUE='\033[0;34m'; RED='\033[0;31m'; GRAY='\033[0;37m'; NC='\033[0m'

# 2. Root-Check
[[ "$EUID" -ne 0 ]] && { echo -e "${RED}Bitte führen Sie das Script als root aus.${NC}"; exit 1; }

# Datenbank-Check
if mysql -e "USE nextcloud;" 2>/dev/null; then
    echo -e "${GRAY}Bereinige temporäre Dateien...${NC}"
    rm -rf /opt/scriptfiles/testarea-main /opt/main.zip 2>/dev/null || true
    echo -e "${GREEN}Datenbank existiert bereits. Installation wird übersprungen.${NC}"
    exit 0
fi

# 3. OS-Check
[[ ! -f /etc/os-release ]] && { echo -e "${RED}Konnte Betriebssystem nicht erkennen. Das Script benötigt Debian 12, Ubuntu 22.04+ oder Alpine Linux.${NC}"; exit 1; }

# OS-Typ ermitteln
if grep -q "Ubuntu" /etc/os-release; then
  OS_TYPE="Ubuntu"
  OS_VERSION=$(grep -oP '(?<=VERSION_ID=").*?(?=")' /etc/os-release)
  [[ $(echo "$OS_VERSION < 22.04" | bc -l) -eq 1 ]] && { echo -e "${RED}Dieses Script benötigt Ubuntu 22.04 oder neuer. Erkannte Version: $OS_VERSION${NC}"; exit 1; }
  echo -e "${BLUE}Ubuntu $OS_VERSION erkannt. Fahre fort...${NC}"
elif grep -q "Debian" /etc/os-release; then
  OS_TYPE="Debian"
  OS_VERSION=$(grep -oP '(?<=VERSION_ID=").*?(?=")' /etc/os-release)
  [[ $(echo "$OS_VERSION < 12" | bc -l) -eq 1 ]] && { echo -e "${RED}Dieses Script benötigt Debian 12 oder neuer. Erkannte Version: $OS_VERSION${NC}"; exit 1; }
  echo -e "${BLUE}Debian $OS_VERSION erkannt. Fahre fort...${NC}"
elif grep -q "alpine" /etc/os-release; then
  OS_TYPE="Alpine"
  OS_VERSION=$(grep -oP '(?<=VERSION_ID=).*' /etc/os-release)
  echo -e "${BLUE}Alpine $OS_VERSION erkannt. Fahre fort...${NC}"
else
  echo -e "${RED}Dieses Script unterstützt nur Debian, Ubuntu oder Alpine. Erkanntes System: $(grep -oP '(?<=^ID=).+' /etc/os-release)${NC}"
  exit 1
fi

# 4. Konfigurationsparameter
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
[[ "$DOMAIN_NAME" = "localhost" || -z "$DOMAIN_NAME" ]] && DOMAIN_NAME=$SERVER_IP

clear

# 5. Installationsparameter anzeigen
echo -e "${BLUE}=== Nextcloud Installationsscript für $OS_TYPE ====${NC}"
echo -e "${BLUE}Dieses Script installiert Nextcloud mit MariaDB und Redis.${NC}\n"
echo -e "${GREEN}Installationsparameter:${NC}"
echo -e "IP-Adresse: ${GREEN}$SERVER_IP${NC}"
echo -e "Admin Benutzer: ${GREEN}$NEXTCLOUD_ADMIN_USER${NC}"
echo -e "Datenbank: ${GREEN}$NEXTCLOUD_DB_NAME${NC}\n"

# 6. Bestätigung 
read -p "Installation starten? (j/n): " CONFIRM
[[ $CONFIRM != "j" && $CONFIRM != "J" ]] && { echo "Installation abgebrochen."; exit 0; }

# 7. System aktualisieren
echo -e "${BLUE}[1/10] System wird aktualisiert...${NC}"
if [ "$OS_TYPE" = "Alpine" ]; then
  apk update && apk upgrade
else
  apt update && apt upgrade -y
fi

# 8. Benötigte Pakete installieren
echo -e "${BLUE}[2/10] Benötigte Pakete werden installiert...${NC}"
if [ "$OS_TYPE" = "Alpine" ]; then
  apk add apache2 mariadb mariadb-client redis \
    php php-fpm php-cli php-common php-json php-intl php-imagick \
    php-curl php-mbstring php-zip php-xml php-gd php-mysqli \
    php-bz2 php-redis php-apcu unzip curl wget openssl imagemagick \
    php-gmp
  # PHP-FPM und Apache starten und für den Boot aktivieren
  rc-service apache2 start
  rc-service mariadb start
  rc-service redis start
  rc-update add apache2
  rc-update add mariadb
  rc-update add redis
else
  apt install -y bc apache2 mariadb-server redis-server \
    php php-cli php-common php-fpm php-json php-intl php-imagick \
    php-curl php-mbstring php-zip php-xml php-gd php-mysql \
    php-bz2 php-redis php-apcu unzip curl wget ssl-cert pv libmagickcore-6.q16-6-extra \
    php-gmp
fi

# 9. Apache für PHP konfigurieren
echo -e "${BLUE}[3/10] Apache für PHP konfigurieren...${NC}"
if [ "$OS_TYPE" = "Alpine" ]; then
  # Apache-Module aktivieren
  echo "LoadModule rewrite_module modules/mod_rewrite.so" >> /etc/apache2/httpd.conf
  echo "LoadModule headers_module modules/mod_headers.so" >> /etc/apache2/httpd.conf
  echo "LoadModule env_module modules/mod_env.so" >> /etc/apache2/httpd.conf
  echo "LoadModule dir_module modules/mod_dir.so" >> /etc/apache2/httpd.conf
  echo "LoadModule mime_module modules/mod_mime.so" >> /etc/apache2/httpd.conf
  echo "LoadModule ssl_module modules/mod_ssl.so" >> /etc/apache2/httpd.conf
  
  # PHP-FPM konfigurieren
  sed -i 's|;include_path =.*|include_path = ".:/usr/share/php"|' /etc/php*/php.ini
  echo -e "<FilesMatch \.php$>\n    SetHandler application/x-httpd-php\n</FilesMatch>" >> /etc/apache2/httpd.conf
  
  rc-service apache2 restart
else
  a2enmod rewrite headers env dir mime ssl
  # PHP-Version ermitteln und konfigurieren
  PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
  if [ -f "/etc/apache2/conf-available/php${PHP_VERSION}-fpm.conf" ]; then
    a2enconf "php${PHP_VERSION}-fpm"
  else
    a2enmod proxy_fcgi setenvif
    a2enconf php${PHP_VERSION}-fpm
  fi
  systemctl restart apache2
fi

# 10. MariaDB konfigurieren
echo -e "${BLUE}[4/10] MariaDB wird konfiguriert...${NC}"

# Systemspezifische MariaDB-Konfiguration
if [ "$OS_TYPE" = "Alpine" ]; then
  # MariaDB initialisieren
  mysql_install_db --user=mysql --datadir=/var/lib/mysql
  rc-service mariadb start
  mysqladmin -u root password "${MYSQL_ROOT_PASSWORD}"
  
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DELETE FROM mysql.user WHERE User='';"
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DROP DATABASE IF EXISTS test;"
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS ${NEXTCLOUD_DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
  
  USER_EXISTS=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT User FROM mysql.user WHERE User='${NEXTCLOUD_DB_USER}';" | grep -o "${NEXTCLOUD_DB_USER}" || echo "")
  [[ -z "$USER_EXISTS" ]] && mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE USER '${NEXTCLOUD_DB_USER}'@'localhost' IDENTIFIED BY '${NEXTCLOUD_DB_PASSWORD}';"
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON ${NEXTCLOUD_DB_NAME}.* TO '${NEXTCLOUD_DB_USER}'@'localhost';"
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"
elif [ "$OS_TYPE" = "Debian" ]; then
  mysql -e "SET PASSWORD FOR root@localhost = PASSWORD('${MYSQL_ROOT_PASSWORD}');"
  mysql -e "DELETE FROM mysql.user WHERE User='';"
  mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
  mysql -e "DROP DATABASE IF EXISTS test;"
  mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
  
  mysql -e "CREATE DATABASE IF NOT EXISTS ${NEXTCLOUD_DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
  USER_EXISTS=$(mysql -e "SELECT User FROM mysql.user WHERE User='${NEXTCLOUD_DB_USER}';" | grep -o "${NEXTCLOUD_DB_USER}" || echo "")
  [[ -z "$USER_EXISTS" ]] && mysql -e "CREATE USER '${NEXTCLOUD_DB_USER}'@'localhost' IDENTIFIED BY '${NEXTCLOUD_DB_PASSWORD}';"
  mysql -e "GRANT ALL PRIVILEGES ON ${NEXTCLOUD_DB_NAME}.* TO '${NEXTCLOUD_DB_USER}'@'localhost';"
  mysql -e "FLUSH PRIVILEGES;"
else
  # Ubuntu-spezifische Konfiguration
  if mysql -e "SELECT 1;" &>/dev/null; then
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
  else
    mysqladmin -u root password "${MYSQL_ROOT_PASSWORD}" || true
  fi
  
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DELETE FROM mysql.user WHERE User='';"
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DROP DATABASE IF EXISTS test;"
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS ${NEXTCLOUD_DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
  
  USER_EXISTS=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT User FROM mysql.user WHERE User='${NEXTCLOUD_DB_USER}';" | grep -o "${NEXTCLOUD_DB_USER}" || echo "")
  [[ -z "$USER_EXISTS" ]] && mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE USER '${NEXTCLOUD_DB_USER}'@'localhost' IDENTIFIED BY '${NEXTCLOUD_DB_PASSWORD}';"
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON ${NEXTCLOUD_DB_NAME}.* TO '${NEXTCLOUD_DB_USER}'@'localhost';"
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"
fi

# MariaDB-Konfigurationspfad
if [ "$OS_TYPE" = "Alpine" ]; then
  MARIADB_CONF_DIR="/etc/mysql"
else
  MARIADB_CONF_DIR="/etc/mysql/mariadb.conf.d"
  [[ ! -d "$MARIADB_CONF_DIR" ]] && { 
    [[ -d "/etc/mysql/conf.d" ]] && MARIADB_CONF_DIR="/etc/mysql/conf.d" || mkdir -p "/etc/mysql/mariadb.conf.d"; 
  }
fi

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
if [ "$OS_TYPE" = "Alpine" ]; then
  rc-service mariadb restart
else
  systemctl restart $(systemctl list-units --type=service | grep -q "mariadb.service" && echo "mariadb" || echo "mysql")
fi

# 11. Redis konfigurieren
echo -e "${BLUE}[5/10] Redis wird konfiguriert...${NC}"

# Redis-Konfigurationspfad
if [ "$OS_TYPE" = "Alpine" ]; then
  REDIS_CONF="/etc/redis.conf"
else
  REDIS_CONF="/etc/redis/redis.conf"
  [[ ! -f "$REDIS_CONF" && -f "/etc/redis/redis-server.conf" ]] && REDIS_CONF="/etc/redis/redis-server.conf"
fi
[[ ! -f "$REDIS_CONF" ]] && { echo -e "${RED}Redis-Konfigurationsdatei nicht gefunden.${NC}"; exit 1; }

# Redis konfigurieren
sed -i "s/port 6379/port 0/" $REDIS_CONF
sed -i "s/# unixsocket/unixsocket/" $REDIS_CONF
sed -i "s/# unixsocketperm 700/unixsocketperm 770/" $REDIS_CONF
sed -i "s/^unixsocketperm 700/unixsocketperm 770/" $REDIS_CONF 2>/dev/null || true
if [ "$OS_TYPE" = "Alpine" ]; then
  adduser -S www-data redis
else
  usermod -a -G redis www-data
fi

# Redis neustarten
if [ "$OS_TYPE" = "Alpine" ]; then
  rc-service redis restart
else
  REDIS_SERVICE=$(systemctl list-units --type=service | grep -q "redis-server.service" && echo "redis-server" || echo "redis")
  systemctl restart $REDIS_SERVICE || { echo -e "${RED}Redis-Service nicht gefunden.${NC}"; exit 1; }
fi

# 12. PHP für Nextcloud optimieren
echo -e "${BLUE}[6/10] PHP-Konfiguration für Nextcloud optimieren...${NC}"
if [ "$OS_TYPE" = "Alpine" ]; then
  PHP_INI="/etc/php*/php.ini"
  cat > /etc/php*/conf.d/99-nextcloud.ini << EOF
memory_limit = 512M
upload_max_filesize = 500M
post_max_size = 500M
max_execution_time = 300
date.timezone = Europe/Berlin

opcache.enable=1
opcache.interned_strings_buffer=32
opcache.max_accelerated_files=10000
opcache.memory_consumption=128
opcache.save_comments=1
opcache.revalidate_freq=1
EOF
  rc-service php-fpm restart
else
  for sapi in fpm cli apache2; do
      if [ -d "/etc/php/${PHP_VERSION}/$sapi/conf.d" ]; then
          echo -e "${BLUE}→ PHP-SAPI: $sapi wird konfiguriert...${NC}"
          cat > /etc/php/${PHP_VERSION}/$sapi/conf.d/99-nextcloud.ini << EOF
memory_limit = 512M
upload_max_filesize = 500M
post_max_size = 500M
max_execution_time = 300
date.timezone = Europe/Berlin

opcache.enable=1
opcache.interned_strings_buffer=32
opcache.max_accelerated_files=10000
opcache.memory_consumption=128
opcache.save_comments=1
opcache.revalidate_freq=1
EOF
      fi
  done
  [[ $(systemctl list-units --type=service | grep -q "php${PHP_VERSION}-fpm") ]] && systemctl restart php${PHP_VERSION}-fpm
fi

# 13. Apache Virtual Host konfigurieren
echo -e "${BLUE}[7/10] Apache Virtual Host für Nextcloud wird konfiguriert...${NC}"
mkdir -p /etc/ssl/nextcloud/
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/nextcloud/nextcloud.key \
  -out /etc/ssl/nextcloud/nextcloud.crt \
  -subj "/CN=${DOMAIN_NAME}/O=Nextcloud/C=DE"

if [ "$OS_TYPE" = "Alpine" ]; then
  cat > /etc/apache2/conf.d/nextcloud.conf << EOF
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

    ErrorLog /var/log/apache2/nextcloud_error.log
    CustomLog /var/log/apache2/nextcloud_access.log combined
</VirtualHost>
EOF
  rc-service apache2 restart
else
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
fi

# 14. Nextcloud installieren
echo -e "${BLUE}[8/10] Nextcloud wird heruntergeladen und installiert...${NC}"
wget -q https://download.nextcloud.com/server/releases/latest.zip -O /tmp/nextcloud.zip
unzip -q /tmp/nextcloud.zip -d /var/www/
rm /tmp/nextcloud.zip
mkdir -p "${NEXTCLOUD_DATA_DIR}"
if [ "$OS_TYPE" = "Alpine" ]; then
  chown -R apache:apache /var/www/nextcloud/ "${NEXTCLOUD_DATA_DIR}"
else
  chown -R www-data:www-data /var/www/nextcloud/ "${NEXTCLOUD_DATA_DIR}"
fi

# 15. Initialisieren
echo -e "${BLUE}[9/10] Nextcloud wird initialisiert...${NC}"
cd /var/www/nextcloud
if [ "$OS_TYPE" = "Alpine" ]; then
  sudo -u apache php occ maintenance:install \
    --database "mysql" \
    --database-name "${NEXTCLOUD_DB_NAME}" \
    --database-user "${NEXTCLOUD_DB_USER}" \
    --database-pass "${NEXTCLOUD_DB_PASSWORD}" \
    --admin-user "${NEXTCLOUD_ADMIN_USER}" \
    --admin-pass "${NEXTCLOUD_ADMIN_PASSWORD}" \
    --data-dir "${NEXTCLOUD_DATA_DIR}"
else
  sudo -u www-data php occ maintenance:install \
    --database "mysql" \
    --database-name "${NEXTCLOUD_DB_NAME}" \
    --database-user "${NEXTCLOUD_DB_USER}" \
    --database-pass "${NEXTCLOUD_DB_PASSWORD}" \
    --admin-user "${NEXTCLOUD_ADMIN_USER}" \
    --admin-pass "${NEXTCLOUD_ADMIN_PASSWORD}" \
    --data-dir "${NEXTCLOUD_DATA_DIR}"
fi

# Nextcloud Konfiguration
if [ "$OS_TYPE" = "Alpine" ]; then
  sudo -u apache php occ config:system:set trusted_domains 0 --value="${DOMAIN_NAME}" \
  && sudo -u apache php occ config:system:set trusted_domains 1 --value="${SERVER_IP}" \
  && sudo -u apache php occ config:system:set memcache.local --value='\OC\Memcache\APCu' \
  && sudo -u apache php occ config:system:set memcache.locking --value='\OC\Memcache\Redis' \
  && sudo -u apache php occ config:system:set redis host --value='/var/run/redis/redis-server.sock' \
  && sudo -u apache php occ config:system:set redis port --value=0 \
  && sudo -u apache php occ config:system:set redis timeout --value=0.0 \
  && sudo -u apache php occ config:system:set trusted_proxies 0 --value="127.0.0.1" \
  && sudo -u apache php occ config:system:set overwriteprotocol --value="https" \
  && sudo -u apache php occ config:system:set htaccess.RewriteBase --value="/" \
  && sudo -u apache php occ maintenance:update:htaccess
else
  sudo -u www-data php occ config:system:set trusted_domains 0 --value="${DOMAIN_NAME}" \
  && sudo -u www-data php occ config:system:set trusted_domains 1 --value="${SERVER_IP}" \
  && sudo -u www-data php occ config:system:set memcache.local --value='\OC\Memcache\APCu' \
  && sudo -u www-data php occ config:system:set memcache.locking --value='\OC\Memcache\Redis' \
  && sudo -u www-data php occ config:system:set redis host --value='/var/run/redis/redis-server.sock' \
  && sudo -u www-data php occ config:system:set redis port --value=0 \
  && sudo -u www-data php occ config:system:set redis timeout --value=0.0 \
  && sudo -u www-data php occ config:system:set trusted_proxies 0 --value="127.0.0.1" \
  && sudo -u www-data php occ config:system:set overwriteprotocol --value="https" \
  && sudo -u www-data php occ config:system:set htaccess.RewriteBase --value="/" \
  && sudo -u www-data php occ maintenance:update:htaccess
fi

# 16. Cronjob
if [ "$OS_TYPE" = "Alpine" ]; then
  echo "*/5 * * * * apache php -f /var/www/nextcloud/cron.php" > /etc/crontabs/nextcloud
  sudo -u apache php occ background:cron
else
  echo "*/5 * * * * www-data php -f /var/www/nextcloud/cron.php" > /etc/cron.d/nextcloud
  sudo -u www-data php occ background:cron
fi

# 17. Zugangsdaten speichern
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

# 18. Anmeldedaten anzeigen Befehl
cat > /usr/local/bin/nextcloud-credentials << 'EOF'
#!/bin/bash
[[ "$EUID" -ne 0 ]] && { echo "Bitte als root ausführen (sudo nextcloud-credentials)"; exit 1; }

CRED_FILE="/root/.nextcloud_credentials"
[[ ! -f "$CRED_FILE" ]] && { echo "Keine Nextcloud-Anmeldedaten gefunden!"; exit 1; }

source "$CRED_FILE"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# 19. Zusätzliche Nextcloud-Konfiguration
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

# 20. Letzter Feinschliff
if [ "$OS_TYPE" = "Alpine" ]; then
  sudo -u apache php /var/www/nextcloud/occ maintenance:mode --on
  sudo -u apache php occ maintenance:repair --include-expensive
  rc-service apache2 restart
else
  sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --on
  sudo -u www-data php occ maintenance:repair --include-expensive
  sudo systemctl restart apache2
fi

# Fortschrittsbalken
echo "Warte, bis der Webserver vollständig hochgefahren ist..."
for i in $(seq 1 10); do echo -n "#"; sleep 1; done
echo

# Log bereinigen
rm -f /var/www/nextcloud/data/nextcloud.log
curl -s -o /dev/null http://localhost || true
if [ "$OS_TYPE" = "Alpine" ]; then
  sudo -u apache php /var/www/nextcloud/occ maintenance:mode --off
else
  sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --off
fi

# Bereinigen
rm -rf /opt/scriptfiles/testarea-main /opt/main.zip 2>/dev/null || true

# 21. Abschlussmeldung
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
