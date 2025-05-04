#!/bin/bash

# Maintainer: @knilix
# Version: 1.0
# Hinweis: Nur für Debian (x64), root erforderlich
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
if [ ! -f /etc/debian_version ] || [ "$(cat /etc/debian_version | cut -d'.' -f1)" -ne 12 ]; then
  echo -e "${RED}Dieses Script ist nur für Debian 12 konzipiert.${NC}"
  exit 1
fi

# 5. Konfigurationsparameter
# Diese können nach Bedarf angepasst werden
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

clear # für einen sauberen Start

# 7. Installationsparameter anzeigen
echo -e "${BLUE}=== Nextcloud Installationsscript für Debian 12 ===${NC}"
echo -e "${BLUE}Dieses Script installiert automatisch Nextcloud mit MariaDB und Redis.${NC}"
echo ""
echo -e "${GREEN}Installationsparameter:${NC}"
echo -e "Domain: ${GREEN}$DOMAIN_NAME${NC}"
echo -e "IP-Adresse: ${GREEN}$SERVER_IP${NC}"
echo -e "Admin Benutzer: ${GREEN}$NEXTCLOUD_ADMIN_USER${NC}"
echo -e "Datenbank: ${GREEN}$NEXTCLOUD_DB_NAME${NC}"
echo ""

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
  php-bz2 php-redis php-apcu unzip curl wget ssl-cert

# 11. Apache für PHP konfigurieren
echo -e "${BLUE}[3/10] Apache für PHP konfigurieren...${NC}"
a2enmod rewrite headers env dir mime ssl

# 12. PHP-FPM konfigurieren
# Prüfen welche PHP-Version installiert ist und entsprechend konfigurieren
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
if [ -f "/etc/apache2/conf-available/php${PHP_VERSION}-fpm.conf" ]; then
  a2enconf "php${PHP_VERSION}-fpm"
else
  # Falls PHP-FPM conf nicht existiert, proxy_fcgi und setenvif Module aktivieren
  a2enmod proxy_fcgi setenvif
  a2enconf php-fpm
fi

systemctl restart apache2

# 13. MariaDB absichern und konfigurieren
echo -e "${BLUE}[4/10] MariaDB wird konfiguriert...${NC}"

# MariaDB Root-Passwort setzen und Datenbank einrichten
mysql -e "SET PASSWORD FOR root@localhost = PASSWORD('${MYSQL_ROOT_PASSWORD}');"
mysql -e "DELETE FROM mysql.user WHERE User='';"
mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -e "DROP DATABASE IF EXISTS test;"
mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"

# 14. Prüfen, ob die Nextcloud-Datenbank bereits existiert
DB_EXISTS=$(mysql -e "SHOW DATABASES LIKE '${NEXTCLOUD_DB_NAME}';" | grep -o "${NEXTCLOUD_DB_NAME}" || echo "")
if [ -z "$DB_EXISTS" ]; then
  echo -e "${GREEN}Erstelle neue Datenbank: ${NEXTCLOUD_DB_NAME}${NC}"
  mysql -e "CREATE DATABASE ${NEXTCLOUD_DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
else
  echo -e "${BLUE}Datenbank ${NEXTCLOUD_DB_NAME} existiert bereits. Überspringe Erstellung...${NC}"
fi

# 15. Prüfen, ob der Datenbankbenutzer bereits existiert
USER_EXISTS=$(mysql -e "SELECT User FROM mysql.user WHERE User='${NEXTCLOUD_DB_USER}';" | grep -o "${NEXTCLOUD_DB_USER}" || echo "")
if [ -z "$USER_EXISTS" ]; then
  echo -e "${GREEN}Erstelle neuen Datenbankbenutzer: ${NEXTCLOUD_DB_USER}${NC}"
  mysql -e "CREATE USER '${NEXTCLOUD_DB_USER}'@'localhost' IDENTIFIED BY '${NEXTCLOUD_DB_PASSWORD}';"
  mysql -e "GRANT ALL PRIVILEGES ON ${NEXTCLOUD_DB_NAME}.* TO '${NEXTCLOUD_DB_USER}'@'localhost';"
else
  echo -e "${BLUE}Benutzer ${NEXTCLOUD_DB_USER} existiert bereits. Setze Passwort und Rechte...${NC}"
  mysql -e "SET PASSWORD FOR '${NEXTCLOUD_DB_USER}'@'localhost' = PASSWORD('${NEXTCLOUD_DB_PASSWORD}');"
  mysql -e "GRANT ALL PRIVILEGES ON ${NEXTCLOUD_DB_NAME}.* TO '${NEXTCLOUD_DB_USER}'@'localhost';"
fi

mysql -e "FLUSH PRIVILEGES;"

# 16. MariaDB für Nextcloud optimieren
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

# 18. PHP für Nextcloud optimieren
echo -e "${BLUE}[6/10] PHP für Nextcloud optimieren...${NC}"

# PHP-Version ermitteln
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"

# PHP-Konfiguration anpassen
cat > /etc/php/${PHP_VERSION}/fpm/conf.d/99-nextcloud.ini << EOF
memory_limit = 512M
upload_max_filesize = 500M
post_max_size = 500M
max_execution_time = 300
date.timezone = Europe/Berlin
opcache.enable=1
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=10000
opcache.memory_consumption=128
opcache.save_comments=1
opcache.revalidate_freq=1
EOF

# 19. PHP-FPM neustarten
if systemctl list-units --full -all | grep -q "$PHP_FPM_SERVICE"; then
  systemctl restart "$PHP_FPM_SERVICE"
else
  systemctl restart php-fpm
fi

# 20. Apache Virtual Host für Nextcloud konfigurieren
echo -e "${BLUE}[7/10] Apache Virtual Host für Nextcloud wird konfiguriert...${NC}"

# 21. SSL-Zertifikat erstellen
mkdir -p /etc/ssl/nextcloud/
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/nextcloud/nextcloud.key \
  -out /etc/ssl/nextcloud/nextcloud.crt \
  -subj "/CN=${DOMAIN_NAME}/O=Nextcloud/C=DE"

# 22. Virtual Host erstellen
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

# 23. Virtual Host aktivieren
a2ensite nextcloud.conf
systemctl reload apache2

# 24. Nextcloud herunterladen und installieren
echo -e "${BLUE}[8/10] Nextcloud wird heruntergeladen und installiert...${NC}"

# 25. Neueste stabile Version herunterladen
wget -q https://download.nextcloud.com/server/releases/latest.zip -O /tmp/nextcloud.zip
unzip -q /tmp/nextcloud.zip -d /var/www/
rm /tmp/nextcloud.zip

# 26. Berechtigungen setzen
mkdir -p "${NEXTCLOUD_DATA_DIR}"
chown -R www-data:www-data /var/www/nextcloud/
chown -R www-data:www-data "${NEXTCLOUD_DATA_DIR}"

# 27. Nextcloud initialisieren
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

# 28. Vertrauenswürdige Domains konfigurieren
sudo -u www-data php occ config:system:set trusted_domains 0 --value="${DOMAIN_NAME}"
sudo -u www-data php occ config:system:set trusted_domains 1 --value="${SERVER_IP}"

# 29. Caching und Optimierungen konfigurieren
echo -e "${BLUE}[10/10] Optimierungen werden angewendet...${NC}"
sudo -u www-data php occ config:system:set memcache.local --value='\OC\Memcache\APCu'
sudo -u www-data php occ config:system:set memcache.locking --value='\OC\Memcache\Redis'
sudo -u www-data php occ config:system:set redis host --value='/var/run/redis/redis-server.sock'
sudo -u www-data php occ config:system:set redis port --value=0
sudo -u www-data php occ config:system:set redis timeout --value=0.0
sudo -u www-data php occ config:system:set trusted_proxies 0 --value="127.0.0.1"
sudo -u www-data php occ config:system:set overwriteprotocol --value="https"
sudo -u www-data php occ config:system:set htaccess.RewriteBase --value="/"
sudo -u www-data php occ maintenance:update:htaccess

# 30. Cronjob für Nextcloud einrichten
echo "*/5 * * * * www-data php -f /var/www/nextcloud/cron.php" > /etc/cron.d/nextcloud
sudo -u www-data php occ background:cron

# 31. Zugangsdaten in Datei speichern
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

# 32. Befehl zum Anzeigen der Anmeldedaten erstellen
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

# Farben für die Ausgabe
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# 33. Überprüfen und Berechtigungen in redis.conf korrigieren, falls nötig
echo -e "${BLUE}Prüfe unixsocketperm in /etc/redis/redis.conf...${NC}"

# Suche nach der Zeile 'unixsocketperm' und prüfe, ob sie 770 ist
if grep -q "^unixsocketperm 700" /etc/redis/redis.conf; then
  echo -e "${BLUE}Berechtigung 'unixsocketperm' ist auf 700 gesetzt, ändere auf 770...${NC}"
  sed -i "s/^unixsocketperm 700/unixsocketperm 770/" /etc/redis/redis.conf
  systemctl restart redis-server  # Redis neu starten, um die Änderungen zu übernehmen
else
  echo -e "${BLUE}Berechtigung 'unixsocketperm' ist bereits korrekt oder nicht 700.${NC}"
fi
# Redis neu starten, damit die Änderungen wirksam werden
systemctl restart redis-server

clear # für eine saubere Bildschirmanzeige

# 34. Installation abgeschlossen
echo -e "${GREEN}===== Nextcloud Installation abgeschlossen! =====\n${NC}"
echo -e "Ihre Nextcloud ist unter folgenden URLs erreichbar:"
echo -e "Domain: ${GREEN}https://${DOMAIN_NAME}${NC}"
echo -e "IP-Adresse: ${GREEN}https://${SERVER_IP}${NC}"
echo -e "\nAdmin Benutzer: ${GREEN}${NEXTCLOUD_ADMIN_USER}${NC}"
echo -e "Admin Passwort: ${GREEN}${NEXTCLOUD_ADMIN_PASSWORD}${NC}"
echo -e "MariaDB Root Passwort: ${GREEN}${MYSQL_ROOT_PASSWORD}${NC}"
echo -e "Nextcloud Datenbank: ${GREEN}${NEXTCLOUD_DB_NAME}${NC}"
echo -e "Nextcloud DB Benutzer: ${GREEN}${NEXTCLOUD_DB_USER}${NC}" 
echo -e "Nextcloud DB Passwort: ${GREEN}${NEXTCLOUD_DB_PASSWORD}${NC}"
echo -e "\n${BLUE}Diese Anmeldedaten wurden in ${CREDENTIALS_FILE} gespeichert.${NC}"
echo -e "${BLUE}Sie können sie jederzeit mit dem Befehl 'nextcloud-credentials' anzeigen.${NC}"
echo -e "${BLUE}Aus Sicherheitsgründen sollten Sie für die Produktion ein offizielles SSL-Zertifikat einrichten.${NC}"

# 35. Aufräumen
echo -e "${GRAY}Bereinige temporäre Dateien...${NC}"
rm -r /opt/scriptfiles/testarea-main 2>/dev/null
rm /opt/main.zip 2>/dev/null
#
echo
echo -e "${GREEN}Alle Aufgaben abgeschlossen!${NC}"
echo
echo -e "\nViel Erfolg mit Ihrer neuen Nextcloud-Installation!"
echo
