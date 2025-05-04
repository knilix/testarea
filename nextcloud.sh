#!/bin/bash
# Maintainer: @knilix
# Version: 1.0
# Hinweis: Nur für Debian 12 (x64), root erforderlich
#
# Nextcloud Autoinstallation Script für Debian 12
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

# 4. Prüfen ob Debian 12
if [ ! -f /etc/debian_version ] || [ "$(cut -d'.' -f1 < /etc/debian_version)" -ne 12 ]; then
  echo -e "${RED}Dieses Script ist nur für Debian 12 konzipiert.${NC}"
  exit 1
fi

# 5. Konfigurationsparameter
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
NEXTCLOUD_DB_PASSWORD=$(openssl rand -base64 32)
NEXTCLOUD_DB_NAME="nextcloud"
NEXTCLOUD_DB_USER="nextcloud"
NEXTCLOUD_ADMIN_USER="admin"
NEXTCLOUD_ADMIN_PASSWORD=$(openssl rand -base64 12)
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
echo -e "${BLUE}=== Nextcloud Installationsscript für Debian 12 ===${NC}"
echo -e "${BLUE}Dieses Script installiert automatisch Nextcloud mit MariaDB und Redis.${NC}\n"
echo -e "${GREEN}Installationsparameter:${NC}"
echo -e "Domain: ${GREEN}$DOMAIN_NAME${NC}"
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
apt update && apt upgrade -y

# 10. Benötigte Pakete installieren
echo -e "${BLUE}[2/10] Benötigte Pakete werden installiert...${NC}"
apt install -y apache2 mariadb-server redis-server \
  php php-cli php-common php-fpm php-json php-intl php-imagick \
  php-curl php-mbstring php-zip php-xml php-gd php-mysql \
  php-bz2 php-redis php-apcu unzip curl wget ssl-cert pv

# 11. Apache für PHP konfigurieren
echo -e "${BLUE}[3/10] Apache für PHP konfigurieren...${NC}"
a2enmod rewrite headers env dir mime ssl

PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
if [ -f "/etc/apache2/conf-available/php${PHP_VERSION}-fpm.conf" ]; then
  a2enconf "php${PHP_VERSION}-fpm"
else
  a2enmod proxy_fcgi setenvif
  a2enconf php-fpm
fi

systemctl restart apache2

# 13. MariaDB konfigurieren
echo -e "${BLUE}[4/10] MariaDB wird konfiguriert...${NC}"
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

cat > /etc/mysql/mariadb.conf.d/99-nextcloud.cnf << EOF
[mysqld]
transaction_isolation = READ-COMMITTED
binlog_format = ROW
innodb_large_prefix=on
innodb_file_format=barracuda
innodb_file_per_table=1
max_allowed_packet = 128M
EOF

# 17. Redis konfigurieren
echo -e "${BLUE}[5/10] Redis wird konfiguriert...${NC}"
sed -i "s/port 6379/port 0/" /etc/redis/redis.conf
sed -i "s/# unixsocket/unixsocket/" /etc/redis/redis.conf
sed -i "s/# unixsocketperm 700/unixsocketperm 770/" /etc/redis/redis.conf
usermod -a -G redis www-data
systemctl restart redis-server

# [6/10] PHP für Nextcloud optimieren
echo -e "${BLUE}[6/10] PHP-Konfiguration für Nextcloud optimieren...${NC}"
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

# 20. Apache Virtual Host konfigurieren
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

a2enmod headers
a2ensite nextcloud.conf
systemctl reload apache2


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

# 30. Cronjob
echo "*/5 * * * * www-data php -f /var/www/nextcloud/cron.php" > /etc/cron.d/nextcloud
sudo -u www-data php occ background:cron

# 31. Zugangsdaten speichern
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

# 32. Anmeldedaten anzeigen Befehl
cat > /usr/local/bin/nextcloud-credentials << 'EOF'
#!/bin/bash
if [ "$EUID" -ne 0 ]; then
  echo "Bitte als root ausführen (sudo nextcloud-credentials)"
  exit 1
fi

CRED_FILE="/root/.nextcloud_credentials"
if [ ! -f "$CRED_FILE" ]; then
  echo "Keine Nextcloud-Anmeldedaten gefunden!"
  exit 1
fi

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

# 33. Redis Socket-Perm prüfen
if grep -q "^unixsocketperm 700" /etc/redis/redis.conf; then
  sed -i "s/^unixsocketperm 700/unixsocketperm 770/" /etc/redis/redis.conf
  systemctl restart redis-server
fi

#######################################################################################################################################################################
# Zusatz, in letzter Minute hinzugefügt
## 1
echo "Füge Nextcloud Konfiguration hinzu"

config_file="/var/www/nextcloud/config/config.php"

if [ -f "$config_file" ]; then
  echo "Füge Konfiguration in config.php ein"

  # Temporäre Datei erzeugen
  tmp_file=$(mktemp)

  # Konfiguration vor der letzten Klammer einfügen
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

  # Backup und Überschreiben
  cp "$config_file" "${config_file}.bak"
  cp "$tmp_file" "$config_file"
  rm "$tmp_file"

  echo "Konfiguration erfolgreich eingefügt in $config_file"
else
  echo "Die Konfigurationsdatei $config_file wurde nicht gefunden!"
fi

## 2
# --> verschoben zu 4

##3 Nachtrag PHP-Module für Nextcloud
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")

has_php_module() {
  php -m | grep -iq "^$1\$"
}

has_imagick_svg_support() {
  php -r "if (extension_loaded('imagick')) { \$v = new Imagick(); echo in_array('SVG', \$v->queryFormats()) ? 'yes' : 'no'; } else { echo 'no'; }"
}

install_gmp=false
install_svg_support=false
install_imagick=false

if has_php_module "gmp"; then
  echo " php-gmp ist bereits installiert."
else
  echo " php-gmp fehlt."
  install_gmp=true
fi

if has_php_module "imagick"; then
  echo " php-imagick ist installiert."
  if [ "$(has_imagick_svg_support)" == "yes" ]; then
    echo " imagick unterstützt SVG."
  else
    echo " imagick hat keine SVG-Unterstützung."
    install_svg_support=true
  fi
else
  echo " php-imagick fehlt."
  install_imagick=true
  install_svg_support=true
fi

# echo " Installiere erforderliche Pakete ..."
apt-get update -qq

if $install_gmp; then
  apt-get install -y "php${PHP_VERSION}-gmp"
fi

if $install_imagick; then
  apt-get install -y "php${PHP_VERSION}-imagick"
fi

if $install_svg_support; then
  apt-get install -y libmagickcore-6.q16-6-extra
fi

echo " Dienste neu starten (falls vorhanden) ..."

if systemctl list-units --type=service | grep -q "apache2.service"; then
  echo " Starte Apache neu ..."
  systemctl reload apache2
fi

if systemctl list-units --type=service | grep -q "php${PHP_VERSION}-fpm.service"; then
  echo " Starte PHP-FPM neu ..."
  systemctl restart "php${PHP_VERSION}-fpm"
fi

echo " Fertig. PHP-Module aktualisiert und Dienste neu geladen."
echo
echo " Nun noch einen Erststart von cron.php."

## 4 Letzter Feinschliff
# Zwingen, den Cache zu leeren und den Webserver neu zu starten
sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --on
sudo -u www-data php occ maintenance:repair --include-expensive
sudo systemctl restart apache2

# Fortschrittsbalken für die Wartezeit
echo "Warte, bis der Webserver vollständig hochgefahren ist..."

# Manuelle Schleife für den Fortschrittsbalken
# Anzahl der Schritte (dauert insgesamt 10 Sekunden)
TOTAL_STEPS=10
for i in $(seq 1 $TOTAL_STEPS); do
    echo -n "#"
    sleep 1
done

echo # Um die Zeile zu beenden

# Log bereinigen (wird automatisch neu angelegt)
rm /var/www/nextcloud/data/nextcloud.log

# Zusätzliche Anfrage an den Server senden, um die Sitzung zu initialisieren
curl -s -o /dev/null http://localhost

sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --off
#######################################################################################################################################################################

# Bereinigen
echo -e "${GRAY}Bereinige temporäre Dateien...${NC}"
rm -rf /opt/scriptfiles/testarea-main /opt/main.zip

# 34. Abschlussmeldung
clear
echo -e "${BLUE}===== Nextcloud Zugangsdaten =====\n${NC}"
# echo -e "Nextcloud URL (Domain): ${GREEN}${NEXTCLOUD_URL_DOMAIN}${NC}"
echo -e "Nextcloud URL (IP): ${GREEN}${NEXTCLOUD_URL_IP}${NC}"
echo -e "Admin Benutzer: ${GREEN}${NEXTCLOUD_ADMIN_USER}${NC}"
echo -e "Admin Passwort: ${GREEN}${NEXTCLOUD_ADMIN_PASSWORD}${NC}"
echo -e "\n${BLUE}MariaDB Datenbank:${NC}"
echo -e "Root Passwort: ${GREEN}${MYSQL_ROOT_PASSWORD}${NC}"
echo -e "Datenbank: ${GREEN}${NEXTCLOUD_DB_NAME}${NC}"
echo -e "DB Benutzer: ${GREEN}${NEXTCLOUD_DB_USER}${NC}" 
echo -e "DB Passwort: ${GREEN}${NEXTCLOUD_DB_PASSWORD}${NC}"
echo -e "\nInstalliert am: ${GREEN}${INSTALLATION_DATE}${NC}"
echo
echo -e "${GREEN}===== Nextcloud Installation abgeschlossen! =====${NC}"
echo -e "Sie können sich nun unter folgendem Link anmelden:\n"
# echo -e "Domain: ${BLUE}https://${DOMAIN_NAME}${NC}"
echo -e "IP:     ${BLUE}https://${SERVER_IP}${NC}"
echo -e "\nBenutzen Sie den Befehl ${GREEN}nextcloud-credentials${NC}, um Ihre Zugangsdaten anzuzeigen."
echo
