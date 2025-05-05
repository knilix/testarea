#!/bin/bash
# Maintainer: @knilix (Original), erweitert für Debian, Ubuntu und Alpine
# Version: 1.1
# Hinweis: Für Debian 12, Ubuntu ab 22.04+ (x64) und Alpine ab 3.18+ (x64), root erforderlich
#
# Nextcloud Autoinstallation Script für Debian, Ubuntu und Alpine
# Mit MariaDB und Redis Cache
# ---------------------------------

# 1. Fehler-Handling
set -e
trap 'echo "Ein Fehler ist aufgetreten. Installation wurde abgebrochen."' ERR

# 2. Farben für die Ausgabe
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# 3. Prüfen, ob Script als root ausgeführt wird
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Bitte führen Sie das Script als root aus.${NC}"
  exit 1
fi

# 4. Betriebssystem erkennen und prüfen
if [ ! -f /etc/os-release ]; then
  echo -e "${RED}Konnte Betriebssystem nicht erkennen. Das Script benötigt Debian 12, Ubuntu 22.04+ oder Alpine 3.18+.${NC}"
  exit 1
fi

# OS-Typ ermitteln (Debian, Ubuntu oder Alpine)
source /etc/os-release
if [ "$ID" == "ubuntu" ]; then
  OS_TYPE="Ubuntu"
  OS_VERSION=$VERSION_ID
  if (( $(echo "$OS_VERSION < 22.04" | bc -l) )); then
    echo -e "${RED}Dieses Script benötigt Ubuntu 22.04 oder neuer. Erkannte Version: $OS_VERSION${NC}"
    exit 1
  fi
  PACKAGE_MANAGER="apt"
  echo -e "${BLUE}Ubuntu $OS_VERSION erkannt. Fahre fort...${NC}"
elif [ "$ID" == "debian" ]; then
  OS_TYPE="Debian"
  OS_VERSION=$VERSION_ID
  if (( $(echo "$OS_VERSION < 12" | bc -l) )); then
    echo -e "${RED}Dieses Script benötigt Debian 12 oder neuer. Erkannte Version: $OS_VERSION${NC}"
    exit 1
  fi
  PACKAGE_MANAGER="apt"
  echo -e "${BLUE}Debian $OS_VERSION erkannt. Fahre fort...${NC}"
elif [ "$ID" == "alpine" ]; then
  OS_TYPE="Alpine"
  OS_VERSION=$VERSION_ID
  if (( $(echo "$OS_VERSION < 3.18" | bc -l) )); then
    echo -e "${RED}Dieses Script benötigt Alpine 3.18 oder neuer. Erkannte Version: $OS_VERSION${NC}"
    exit 1
  fi
  PACKAGE_MANAGER="apk"
  echo -e "${BLUE}Alpine $OS_VERSION erkannt. Fahre fort...${NC}"
else
  echo -e "${RED}Dieses Script unterstützt nur Debian, Ubuntu oder Alpine. Erkanntes System: $ID${NC}"
  exit 1
fi

# 5. Konfigurationsparameter
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
NEXTCLOUD_DB_PASSWORD=$(openssl rand -base64 32)
NEXTCLOUD_DB_NAME="nextcloud"
NEXTCLOUD_DB_USER="nextcloud"
NEXTCLOUD_ADMIN_USER="admin"
NEXTCLOUD_ADMIN_PASSWORD=$(openssl rand -base64 24)
NEXTCLOUD_DATA_DIR="/var/www/nextcloud/data"
CREDENTIALS_FILE="/root/.nextcloud_credentials"
SERVER_IP=$(hostname -I | awk '{print $1}')

# 6. Domain-Einstellungen
DOMAIN_NAME=$(hostname -f)
if [ "$DOMAIN_NAME" = "localhost" ] || [ -z "$DOMAIN_NAME" ]; then
  DOMAIN_NAME=$SERVER_IP
fi

clear

# 7. Installationsparameter anzeigen
echo -e "${BLUE}=== Nextcloud Installationsscript für $OS_TYPE ====${NC}"
echo -e "${BLUE}Dieses Script installiert Nextcloud mit MariaDB und Redis.${NC}\n"
echo -e "${GREEN}Installationsparameter:${NC}"
# echo -e "Domain: ${GREEN}$DOMAIN_NAME${NC}"
echo -e "IP-Adresse: ${GREEN}$SERVER_IP${NC}"
echo -e "Admin Benutzer: ${GREEN}$NEXTCLOUD_ADMIN_USER${NC}"
echo -e "Datenbank: ${GREEN}$NEXTCLOUD_DB_NAME${NC}\n"

# 8. Bestätigung anfordern
read -p "Installation starten? (j/n): " CONFIRM
if [[ $CONFIRM != "j" && $CONFIRM != "J" ]]; then
  echo "Installation abgebrochen."
  exit 0
fi

# 9. System aktualisieren
echo -e "${BLUE}[1/10] System wird aktualisiert...${NC}"
if [ "$PACKAGE_MANAGER" == "apt" ]; then
  apt update && apt upgrade -y
elif [ "$PACKAGE_MANAGER" == "apk" ]; then
  apk update && apk upgrade
fi

# 10. Benötigte Pakete installieren
echo -e "${BLUE}[2/10] Benötigte Pakete werden installiert...${NC}"

if [ "$PACKAGE_MANAGER" == "apt" ]; then
  # Ensure bc is installed (needed for version comparison)
  apt install -y bc

  # Install other requirements
  apt install -y apache2 mariadb-server redis-server \
    php php-cli php-common php-fpm php-json php-intl php-imagick \
    php-curl php-mbstring php-zip php-xml php-gd php-mysql \
    php-bz2 php-redis php-apcu unzip curl wget ssl-cert pv libmagickcore-6.q16-6-extra
elif [ "$PACKAGE_MANAGER" == "apk" ]; then
  # Alpine verwendet BusyBox, welches bc enthält
  # Falls nicht, installieren wir es explizit
  if ! command -v bc &> /dev/null; then
    apk add bc
  fi

# Alpine verwendet BusyBox, welches bc enthält
# Falls nicht, installieren wir es explizit
if ! command -v bc &> /dev/null; then
  apk add bc
fi
  # Installiere Apache, MariaDB, Redis und PHP
  apk add apache2 mariadb mariadb-client redis \
    php php-fpm php-json php-intl php-gd \
    php-curl php-mbstring php-zip php-xml php-mysqli \
    php-bz2 php-redis php-apcu php-pecl-imagick \
    unzip curl wget openssl pv
  
  # Überprüfe, ob wir zusätzliche Pakete für ImageMagick SVG-Support benötigen
  apk add imagemagick
  
# Alpine verwendet nicht systemd, daher starten wir die Dienste direkt
  rc-update add apache2 default
  rc-update add mariadb default
  rc-update add redis default
  
  # Finde den korrekten PHP-FPM Service-Namen
  PHP_FPM_SERVICE=""
  if rc-service -l | grep -q "php-fpm"; then
    PHP_FPM_SERVICE="php-fpm"
  elif rc-service -l | grep -q "php-fpm8"; then
    PHP_FPM_SERVICE="php-fpm8"
  elif rc-service -l | grep -q "php8-fpm"; then
    PHP_FPM_SERVICE="php8-fpm"
  elif rc-service -l | grep -q "php7-fpm"; then
    PHP_FPM_SERVICE="php7-fpm"
  fi
  
  if [ -n "$PHP_FPM_SERVICE" ]; then
    rc-update add $PHP_FPM_SERVICE default
  else
    echo "${RED}Konnte PHP-FPM Service nicht finden. Sie müssen ihn manuell konfigurieren.${NC}"
  fi



  # Starte PHP-FPM Service mit dem vorher bestimmten Namen
  if [ -n "$PHP_FPM_SERVICE" ]; then
    rc-service $PHP_FPM_SERVICE start
  fi


  # Starte PHP-FPM Service mit dem vorher bestimmten Namen
  if [ -n "$PHP_FPM_SERVICE" ]; then
    rc-service $PHP_FPM_SERVICE start
  fi

  # PHP-FPM neustarten
  if [ -n "$PHP_FPM_SERVICE" ]; then
    rc-service $PHP_FPM_SERVICE restart
  fi


  # PHP-FPM neustarten
  if [ -n "$PHP_FPM_SERVICE" ]; then
    rc-service $PHP_FPM_SERVICE restart
  fi
  
# Starte die Services
rc-service mariadb setup
rc-service mariadb start
rc-service redis start
rc-service php-fpm start
fi

# 11. Apache für PHP konfigurieren
echo -e "${BLUE}[3/10] Apache für PHP konfigurieren...${NC}"

if [ "$OS_TYPE" == "Alpine" ]; then
  # Für Alpine Linux
  # Aktiviere benötigte Module
  sed -i 's/#LoadModule rewrite_module/LoadModule rewrite_module/' /etc/apache2/httpd.conf
  sed -i 's/#LoadModule headers_module/LoadModule headers_module/' /etc/apache2/httpd.conf
  sed -i 's/#LoadModule env_module/LoadModule env_module/' /etc/apache2/httpd.conf
  sed -i 's/#LoadModule dir_module/LoadModule dir_module/' /etc/apache2/httpd.conf
  sed -i 's/#LoadModule mime_module/LoadModule mime_module/' /etc/apache2/httpd.conf
  sed -i 's/#LoadModule ssl_module/LoadModule ssl_module/' /etc/apache2/httpd.conf
  
  # Stelle sicher, dass das PHP-Modul geladen wird
  if [ ! -f /etc/apache2/conf.d/php-fpm.conf ]; then
    cat > /etc/apache2/conf.d/php-fpm.conf << EOF
<FilesMatch \.php$>
    SetHandler "proxy:unix:/run/php-fpm/www.sock|fcgi://localhost"
</FilesMatch>
EOF
  fi
  
  # Aktiviere zusätzliche Module
  echo "LoadModule proxy_module modules/mod_proxy.so" >> /etc/apache2/httpd.conf
  echo "LoadModule proxy_fcgi_module modules/mod_proxy_fcgi.so" >> /etc/apache2/httpd.conf
  
  # Starte Apache neu
  rc-service apache2 restart
else
  # Für Debian/Ubuntu
  a2enmod rewrite headers env dir mime ssl
  
  # Detect PHP version
  PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
  if [ -f "/etc/apache2/conf-available/php${PHP_VERSION}-fpm.conf" ]; then
    a2enconf "php${PHP_VERSION}-fpm"
  else
    a2enmod proxy_fcgi setenvif
    a2enconf php${PHP_VERSION}-fpm
  fi
  
  systemctl restart apache2
fi

# 13. MariaDB konfigurieren
echo -e "${BLUE}[4/10] MariaDB wird konfiguriert...${NC}"

if [ "$OS_TYPE" == "Alpine" ]; then
  # Alpine-spezifische MariaDB-Konfiguration
  mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
  mysql -e "DELETE FROM mysql.user WHERE User='';"
  mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
  mysql -e "DROP DATABASE IF EXISTS test;"
  mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
  
  DB_EXISTS=$(mysql -e "SHOW DATABASES LIKE '${NEXTCLOUD_DB_NAME}';" | grep -o "${NEXTCLOUD_DB_NAME}" || echo "")
  if [ -z "$DB_EXISTS" ]; then
    mysql -e "CREATE DATABASE ${NEXTCLOUD_DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
  fi
  
  USER_EXISTS=$(mysql -e "SELECT User FROM mysql.user WHERE User='${NEXTCLOUD_DB_USER}';" | grep -o "${NEXTCLOUD_DB_USER}" || echo "")
  if [ -z "$USER_EXISTS" ]; then
    mysql -e "CREATE USER '${NEXTCLOUD_DB_USER}'@'localhost' IDENTIFIED BY '${NEXTCLOUD_DB_PASSWORD}';"
  fi
  mysql -e "GRANT ALL PRIVILEGES ON ${NEXTCLOUD_DB_NAME}.* TO '${NEXTCLOUD_DB_USER}'@'localhost';"
  mysql -e "FLUSH PRIVILEGES;"
  
  # MariaDB-Konfigurationsdatei erstellen
  mkdir -p /etc/my.cnf.d/
  cat > /etc/my.cnf.d/99-nextcloud.cnf << EOF
[mysqld]
transaction_isolation = READ-COMMITTED
binlog_format = ROW
innodb_large_prefix=on
innodb_file_per_table=1
max_allowed_packet = 128M
EOF

  # Neustart von MariaDB, um Änderungen anzuwenden
  rc-service mariadb restart

elif [ "$OS_TYPE" == "Debian" ]; then
  # Debian-spezifische Konfiguration
  mysql -e "SET PASSWORD FOR root@localhost = PASSWORD('${MYSQL_ROOT_PASSWORD}');"
  mysql -e "DELETE FROM mysql.user WHERE User='';"
  mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
  mysql -e "DROP DATABASE IF EXISTS test;"
  mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
  
  DB_EXISTS=$(mysql -e "SHOW DATABASES LIKE '${NEXTCLOUD_DB_NAME}';" | grep -o "${NEXTCLOUD_DB_NAME}" || echo "")
  if [ -z "$DB_EXISTS" ]; then
    mysql -e "CREATE DATABASE ${NEXTCLOUD_DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
  fi
  
  USER_EXISTS=$(mysql -e "SELECT User FROM mysql.user WHERE User='${NEXTCLOUD_DB_USER}';" | grep -o "${NEXTCLOUD_DB_USER}" || echo "")
  if [ -z "$USER_EXISTS" ]; then
    mysql -e "CREATE USER '${NEXTCLOUD_DB_USER}'@'localhost' IDENTIFIED BY '${NEXTCLOUD_DB_PASSWORD}';"
  fi
  mysql -e "GRANT ALL PRIVILEGES ON ${NEXTCLOUD_DB_NAME}.* TO '${NEXTCLOUD_DB_USER}'@'localhost';"
  mysql -e "FLUSH PRIVILEGES;"
else
  # Ubuntu-spezifische Konfiguration
  if mysql -e "SELECT 1;" &>/dev/null; then
    # Root hat noch kein Passwort
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
  else
    # Root hat bereits ein Passwort oder eine andere Authentifizierungsmethode
    echo "MariaDB scheint bereits konfiguriert zu sein. Passwort wird aktualisiert."
    mysqladmin -u root password "${MYSQL_ROOT_PASSWORD}" || true
  fi
  
  # Weitere Datenbank-Konfiguration
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DELETE FROM mysql.user WHERE User='';"
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DROP DATABASE IF EXISTS test;"
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
  
  DB_EXISTS=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW DATABASES LIKE '${NEXTCLOUD_DB_NAME}';" | grep -o "${NEXTCLOUD_DB_NAME}" || echo "")
  if [ -z "$DB_EXISTS" ]; then
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE DATABASE ${NEXTCLOUD_DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
  fi
  
  USER_EXISTS=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT User FROM mysql.user WHERE User='${NEXTCLOUD_DB_USER}';" | grep -o "${NEXTCLOUD_DB_USER}" || echo "")
  if [ -z "$USER_EXISTS" ]; then
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE USER '${NEXTCLOUD_DB_USER}'@'localhost' IDENTIFIED BY '${NEXTCLOUD_DB_PASSWORD}';"
  fi
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON ${NEXTCLOUD_DB_NAME}.* TO '${NEXTCLOUD_DB_USER}'@'localhost';"
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"
fi

# MariaDB-Konfigurationspfad für Debian/Ubuntu prüfen und erstellen falls nötig
if [ "$OS_TYPE" != "Alpine" ]; then
  if [ ! -d "/etc/mysql/mariadb.conf.d" ]; then
    # Bei Ubuntu könnte es auch unter /etc/mysql/conf.d sein
    if [ -d "/etc/mysql/conf.d" ]; then
      MARIADB_CONF_DIR="/etc/mysql/conf.d"
    else
      # Erstelle das Verzeichnis, falls es nicht existiert
      mkdir -p "/etc/mysql/mariadb.conf.d"
      MARIADB_CONF_DIR="/etc/mysql/mariadb.conf.d"
    fi
  else
    MARIADB_CONF_DIR="/etc/mysql/mariadb.conf.d"
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

  # Neustart von MariaDB, um Änderungen anzuwenden
  if systemctl list-units --type=service | grep -q "mariadb.service"; then
    systemctl restart mariadb
  else
    systemctl restart mysql  # Fallback für manche Ubuntu-Versionen
  fi
fi

# 17. Redis konfigurieren
echo -e "${BLUE}[5/10] Redis wird konfiguriert...${NC}"

if [ "$OS_TYPE" == "Alpine" ]; then
  # Redis-Konfiguration für Alpine
  REDIS_CONF="/etc/redis.conf"
  
  sed -i "s/port 6379/port 0/" $REDIS_CONF
  sed -i "s/# unixsocket/unixsocket/" $REDIS_CONF
  sed -i "s/# unixsocketperm 700/unixsocketperm 770/" $REDIS_CONF
  
  # Web-Server-Benutzer zu Redis-Gruppe hinzufügen
  addgroup www-data redis
  
  # Redis neu starten
  rc-service redis restart
else
  # Pfad der Redis-Konfiguration überprüfen für Debian/Ubuntu
  if [ -f "/etc/redis/redis.conf" ]; then
    REDIS_CONF="/etc/redis/redis.conf"
  elif [ -f "/etc/redis/redis-server.conf" ]; then  # Einige Ubuntu-Versionen verwenden diesen Pfad
    REDIS_CONF="/etc/redis/redis-server.conf"
  else
    echo -e "${RED}Redis-Konfigurationsdatei nicht gefunden.${NC}"
    exit 1
  fi

  # Redis konfigurieren
  sed -i "s/port 6379/port 0/" $REDIS_CONF
  sed -i "s/# unixsocket/unixsocket/" $REDIS_CONF
  sed -i "s/# unixsocketperm 700/unixsocketperm 770/" $REDIS_CONF
  usermod -a -G redis www-data

  # Redis-Servicename überprüfen und neustarten
  if systemctl list-units --type=service | grep -q "redis-server.service"; then
    systemctl restart redis-server
  elif systemctl list-units --type=service | grep -q "redis.service"; then
    systemctl restart redis
  else
    echo -e "${RED}Redis-Service nicht gefunden.${NC}"
    exit 1
  fi
fi

# [6/10] PHP für Nextcloud optimieren
echo -e "${BLUE}[6/10] PHP-Konfiguration für Nextcloud optimieren...${NC}"

if [ "$OS_TYPE" == "Alpine" ]; then
  # Finde heraus, welche PHP-Version verwendet wird
  if [ -d "/etc/php8" ]; then
    PHP_BASE_DIR="/etc/php8"
  elif [ -d "/etc/php7" ]; then
    PHP_BASE_DIR="/etc/php7"
  else
    PHP_BASE_DIR="/etc/php"
  fi
  
  # Für alle verfügbaren PHP-SAPIs konfigurieren
  for sapi in fpm cli apache2; do
    if [ -d "$PHP_BASE_DIR/$sapi/conf.d" ]; then
      echo -e "${BLUE}→ PHP-SAPI: $sapi wird konfiguriert...${NC}"
      cat > $PHP_BASE_DIR/$sapi/conf.d/99-nextcloud.ini << EOF
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
  
  # PHP-FPM neustarten
  rc-service php-fpm restart
else
  # Für Debian/Ubuntu
  PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
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

  # PHP-FPM neustarten (wichtig für Änderungen)
  if systemctl list-units --type=service | grep -q "php${PHP_VERSION}-fpm"; then
    echo -e "${BLUE}→ PHP-FPM wird neu gestartet...${NC}"
    systemctl restart php${PHP_VERSION}-fpm
  fi
fi

# 20. Apache Virtual Host konfigurieren
echo -e "${BLUE}[7/10] Apache Virtual Host für Nextcloud wird konfiguriert...${NC}"
mkdir -p /etc/ssl/nextcloud/
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/nextcloud/nextcloud.key \
  -out /etc/ssl/nextcloud/nextcloud.crt \
  -subj "/CN=${DOMAIN_NAME}/O=Nextcloud/C=DE"

if [ "$OS_TYPE" == "Alpine" ]; then
  # Für Alpine Linux
  # Stellen Sie sicher, dass das SSL-Modul in der Apache-Konfiguration aktiviert ist
  if ! grep -q "LoadModule ssl_module" /etc/apache2/httpd.conf; then
    echo "LoadModule ssl_module modules/mod_ssl.so" >> /etc/apache2/httpd.conf
  fi
  
  # Virtual Host für HTTP und HTTPS konfigurieren
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

  # Apache neu starten
  rc-service apache2 restart
else
  # Für Debian/Ubuntu
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

# 24. Nextcloud installieren
echo -e "${BLUE}[8/10] Nextcloud wird heruntergeladen und installiert...${NC}"
wget -q https://download.nextcloud.com/server/releases/latest.zip -O /tmp/nextcloud.zip
unzip -q /tmp/nextcloud.zip -d /var/www/
rm /tmp/nextcloud.zip
mkdir -p "${NEXTCLOUD_DATA_DIR}"
chown -R www-data:www-data /var/www/nextcloud/
chown -R www-data:www-data "${NEXTCLOUD_DATA_DIR}"

# 27. Initialisieren
echo -e "${BLUE}[9/10] Nextcloud wird initialisiert...${NC}"
cd /var/www/nextcloud
sudo -u www-data php occ maintenance:install \
  --database "mysql" \
  --database-name "${NEXTCLOUD_DB_NAME}" \
  --database-user "${NEXTCLOUD_DB_USER}" \
  --database-pass "${NEXTCLOUD_DB_PASSWORD}" \
  --admin-user "${NEXTCLOUD_ADMIN_USER}" \
  --admin-pass "${NEXTCLOUD_ADMIN_PASSWORD}" \
  --data-dir "${NEXTCLOUD_DATA_DIR}"

sudo -u www-data php occ config:system:set trusted_domains 0 --value="${DOMAIN_NAME}"
sudo -u www-data php occ config:system:set trusted_domains 1 --value="${SERVER_IP}"
sudo -u www-data php occ config:system:set memcache.local --value='\OC\Memcache\APCu'
sudo -u www-data php occ config:system:set memcache.locking --value='\OC\Memcache\Redis'
sudo -u www-data php occ config:system:set redis host --value='/var/run/redis/redis-server.sock'
sudo -u www-data php occ config:system:set redis port --value=0
sudo -u www-data php occ config:system:set redis timeout --value=0.0
sudo -u www-data php occ config:system:set trusted_proxies 0 --value="127.0.0.1"
sudo -u www-data php occ config:system:set overwriteprotocol --value="https"
sudo -u www-data php occ config:system:set htaccess.RewriteBase --value="/"
sudo -u www-data php occ maintenance:update:htaccess

# Alpine-spezifischer Fix für Redis-Socket-Pfad
if [ "$OS_TYPE" == "Alpine" ]; then
  # Überprüfen des tatsächlichen Redis-Socket-Pfads
  ACTUAL_REDIS_SOCKET=$(find /var/run -name "redis*.sock" | head -n 1)
  if [ -n "$ACTUAL_REDIS_SOCKET" ]; then
    sudo -u www-data php occ config:system:set redis host --value="$ACTUAL_REDIS_SOCKET"
  fi
fi

# 30. Cronjob
if [ "$OS_TYPE" == "Alpine" ]; then
  # Für Alpine Linux - Verwende /etc/crontabs/root
  echo "*/5 * * * * cd /var/www/nextcloud && php -f cron.php" >> /etc/crontabs/root
  sudo -u www-data php occ background:cron
  
  # Cron-Dienst aktivieren
  rc-update add crond default || rc-update add cron default
  rc-service crond start || rc-service cron start
else
  # Für Debian/Ubuntu
  echo "*/5 * * * * www-data php -f /var/www/nextcloud/cron.php" > /etc/cron.d/nextcloud
  sudo -u www-data php occ background:cron
fi

#!/bin/bash
# 31. Zugangsdaten speichern
echo -e "${BLUE}[10/10] Zugangsdaten werden gespeichert...${NC}"
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

# 32. Anmeldedaten anzeigen Befehl für Alpine
cat > /usr/local/bin/nextcloud-credentials << 'EOF'
#!/bin/sh
if [ "$(id -u)" -ne 0 ]; then
  echo "Bitte als root ausführen (doas nextcloud-credentials)"
  exit 1
fi

CRED_FILE="/root/.nextcloud_credentials"
if [ ! -f "$CRED_FILE" ]; then
  echo "Keine Nextcloud-Anmeldedaten gefunden!"
  exit 1
fi

. "$CRED_FILE"

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

# 33. Alpine-spezifische Redis-Konfiguration prüfen
# Redis-Konfigurationspfad für Alpine
REDIS_CONF="/etc/redis.conf"

if [ -f "$REDIS_CONF" ] && grep -q "^unixsocketperm 700" "$REDIS_CONF"; then
  sed -i "s/^unixsocketperm 700/unixsocketperm 770/" "$REDIS_CONF"
  
  # Redis-Service neu starten (Alpine verwendet OpenRC)
  rc-service redis restart
fi

# 34. Alpine-spezifische Nextcloud Konfiguration
echo -e "${BLUE}Füge Alpine-spezifische Nextcloud Konfiguration hinzu...${NC}"

config_file="/var/www/nextcloud/config/config.php"

if [ -f "$config_file" ]; then
  echo "Füge Konfiguration in config.php ein"

  # Temporäre Datei erzeugen
  tmp_file=$(mktemp)

  # Konfiguration vor der letzten Klammer einfügen - angepasst für Alpine
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
      print "  '\''templatedirectory'\'' => '\''\\'',";
      print "  '\''logfile'\'' => '\''data/nextcloud.log'\'',";
      print "  '\''loglevel'\'' => 2,";
    }
    { print }
  ' "$config_file" > "$tmp_file"

  # Backup und Überschreiben
  cp "$config_file" "${config_file}.bak"
  cp "$tmp_file" "$config_file"
  rm "$tmp_file"

  echo "Konfiguration erfolgreich eingefügt in $config_file"
else
  echo -e "${RED}Die Konfigurationsdatei $config_file wurde nicht gefunden!${NC}"
fi

# 35. Alpine-spezifische PHP-Module für Nextcloud
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")

echo -e "${BLUE}Prüfe und installiere PHP-Module für Alpine...${NC}"

has_php_module() {
  php -m | grep -iq "^$1\$"
}

has_imagick_svg_support() {
  php -r "if (extension_loaded('imagick')) { \$v = new Imagick(); echo in_array('SVG', \$v->queryFormats()) ? 'yes' : 'no'; } else { echo 'no'; }"
}

# Liste der Alpine-spezifischen PHP-Module
MODULES_TO_CHECK="gmp imagick bz2 intl redis apcu zip gd fileinfo curl mbstring xml session ctype xmlreader xmlwriter"

for module in $MODULES_TO_CHECK; do
  if has_php_module "$module"; then
    echo -e " ${GREEN}php-$module ist bereits installiert.${NC}"
  else
    echo -e " ${BLUE}php-$module fehlt. Wird installiert...${NC}"
    apk add php${PHP_VERSION}-$module
  fi
done

# Überprüfen und ggf. SVG-Support installieren
if [ "$(has_imagick_svg_support)" == "yes" ]; then
  echo -e " ${GREEN}imagick unterstützt SVG.${NC}"
else
  echo -e " ${BLUE}imagick hat keine SVG-Unterstützung. Wird installiert...${NC}"
  apk add imagemagick-svg
fi

# 36. Dienste neustarten für Alpine
echo -e "${BLUE}Dienste werden neu gestartet...${NC}"

# Auf Alpine verwenden wir OpenRC
rc-service nginx restart 2>/dev/null || rc-service apache2 restart 2>/dev/null
rc-service php-fpm restart 2>/dev/null

# 37. Nextcloud in Wartungsmodus schalten und reparieren
echo -e "${BLUE}Wartungsreparatur wird durchgeführt...${NC}"
cd /var/www/nextcloud
sudo -u www-data php occ maintenance:mode --on
sudo -u www-data php occ maintenance:repair --include-expensive

# Webserver neu starten
if command -v rc-service >/dev/null 2>&1; then
  # Alpine verwendet OpenRC
  rc-service nginx restart 2>/dev/null || rc-service apache2 restart 2>/dev/null
fi

# Fortschrittsbalken für die Wartezeit
echo "Warte, bis der Webserver vollständig hochgefahren ist..."

# Manuelle Schleife für den Fortschrittsbalken
TOTAL_STEPS=10
for i in $(seq 1 $TOTAL_STEPS); do
    echo -n "#"
    sleep 1
done
echo # Um die Zeile zu beenden

# Log bereinigen (wird automatisch neu angelegt)
if [ -f "/var/www/nextcloud/data/nextcloud.log" ]; then
  rm -f /var/www/nextcloud/data/nextcloud.log
fi

# Zusätzliche Anfrage an den Server senden, um die Sitzung zu initialisieren
wget -q -O /dev/null http://localhost || true

# Wartungsmodus deaktivieren
sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --off

# 38. Automatisches Update aktivieren
echo -e "${BLUE}Automatische Updates werden konfiguriert...${NC}"
sudo -u www-data php occ app:install updatenotification
sudo -u www-data php occ app:enable updatenotification
sudo -u www-data php occ config:app:set updatenotification notify_groups --value="admin"

# 39. Cronjob für Alpine (verwendet crond von busybox)
echo -e "${BLUE}Cronjob für Nextcloud wird eingerichtet...${NC}"
echo "*/5 * * * * su -s /bin/sh www-data -c 'php -f /var/www/nextcloud/cron.php'" > /etc/crontabs/root
rc-service crond restart

# 40. Systemoptimierungen für Alpine
echo -e "${BLUE}Systempakete werden optimiert...${NC}"
apk cache clean
rm -rf /var/cache/apk/*

# 41. Firewall-Konfiguration (falls vorhanden)
if command -v ufw >/dev/null 2>&1; then
  echo -e "${BLUE}Firewall wird konfiguriert...${NC}"
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw --force enable
fi

# 42. Abschlussmeldung
clear
echo -e "${BLUE}===== Nextcloud Zugangsdaten =====\n${NC}"
echo -e "Nextcloud URL (Domain): ${GREEN}https://${DOMAIN_NAME}${NC}"
echo -e "Nextcloud URL (IP): ${GREEN}https://${SERVER_IP}${NC}"
echo -e "\n${BLUE}Zugangsdaten:${NC}"
echo -e "Admin Benutzer: ${GREEN}${NEXTCLOUD_ADMIN_USER}${NC}"
echo -e "Admin Passwort: ${GREEN}${NEXTCLOUD_ADMIN_PASSWORD}${NC}"
echo
echo -e "${GREEN}===== Nextcloud Installation auf Alpine Linux abgeschlossen! =====${NC}"
echo -e "Anmeldung unter folgendem Link:\n"
echo -e "IP:     ${BLUE}https://${SERVER_IP}${NC}"
echo -e "\nBenutzen Sie den Befehl ${GREEN}nextcloud-credentials${NC}, um Ihre kompletten Zugangsdaten anzuzeigen."
echo
echo -e "${BLUE}Tipps:${NC}"
echo -e "1. Für externe Zugriffe konfigurieren Sie bitte Ihre Router-Portweiterleitung."
echo -e "2. Für mehr Sicherheit sollten Sie ein Let's Encrypt Zertifikat einrichten."
echo -e "3. Sie können weitere Apps über die Nextcloud-Weboberfläche installieren."

# Ende des Scripts
