#!/bin/bash
# Maintainer: DeinName <dein.email@example.com>
# Beschreibung: Installiert Nextcloud, MariaDB, Redis, Apache und Let's Encrypt in einem LXC-Container (Debian-basiert)

set -e

# Farbdefinitionen
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# Konfiguration
NEXTCLOUD_DB="nextcloud"
NEXTCLOUD_DB_USER="nextcloud"
NEXTCLOUD_DB_PASSWORD="$(openssl rand -base64 18)"
NEXTCLOUD_ADMIN_USER="admin"
NEXTCLOUD_ADMIN_PASSWORD="$(openssl rand -base64 18)"
DOMAIN="nextcloud-script.home.lan"
# Prüfe, ob wir im Internet sind, für Let's Encrypt
IS_INTERNET_DOMAIN=false
if host -t A "$DOMAIN" >/dev/null 2>&1; then
  if [[ ! "$DOMAIN" =~ \.local$ ]] && [[ ! "$DOMAIN" =~ \.lan$ ]]; then
    IS_INTERNET_DOMAIN=true
  fi
fi

# Logfunktion
log() {
  local level=$1
  local message=$2
  local color=${GRAY}

  case $level in
    "info") color=${GRAY} ;;
    "success") color=${GREEN} ;;
    "warning") color=${YELLOW} ;;
    "error") color=${RED} ;;
  esac

  echo -e "${color}${message}${NC}"
}

# Prüfen, ob Installation bereits existiert
INSTALL_FOUND=false

if [ -d "/var/www/nextcloud" ]; then
  log "warning" "Nextcloud-Verzeichnis gefunden."
  INSTALL_FOUND=true
fi

if command -v mariadb >/dev/null 2>&1; then
  if mariadb -e "USE $NEXTCLOUD_DB;" 2>/dev/null; then
    log "warning" "Datenbank $NEXTCLOUD_DB existiert bereits."
    INSTALL_FOUND=true
  fi
fi

if systemctl is-active --quiet redis-server; then
  log "warning" "Redis scheint bereits installiert oder aktiv zu sein."
  INSTALL_FOUND=true
fi

if [ "$INSTALL_FOUND" = true ]; then
  log "error" "Eine bestehende Installation wurde erkannt."
  read -rp "Möchtest du mit der Bereinigung und Neuinstallation fortfahren? (j/N): " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Jj]$ ]]; then
    log "info" "Abbruch durch Benutzer."
    exit 1
  fi

  log "info" "Bereinige alte Installation..."
  systemctl stop apache2 redis-server mariadb 2>/dev/null || true
  rm -rf /var/www/nextcloud
  if command -v mariadb >/dev/null 2>&1; then
    mariadb -e "DROP DATABASE IF EXISTS $NEXTCLOUD_DB;" || true
    mariadb -e "DROP USER IF EXISTS '$NEXTCLOUD_DB_USER'@'localhost';" || true
  fi
  apt purge -y redis-server || true
  apt autoremove -y
fi

# System aktualisieren und Pakete installieren
log "info" "Installiere benötigte Pakete..."
apt update && apt install -y \
  apache2 \
  mariadb-server \
  libapache2-mod-php \
  php \
  php-mysql \
  php-gd \
  php-xml \
  php-curl \
  php-zip \
  php-mbstring \
  php-bz2 \
  php-intl \
  php-bcmath \
  php-gmp \
  php-apcu \
  php-redis \
  php-imagick \
  php-opcache \
  redis-server \
  unzip \
  wget \
  curl \
  gnupg2 \
  certbot \
  python3-certbot-apache \
  cron

# MariaDB vorbereiten
log "info" "Richte MariaDB ein..."
mariadb -e "CREATE DATABASE $NEXTCLOUD_DB CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
mariadb -e "CREATE USER '$NEXTCLOUD_DB_USER'@'localhost' IDENTIFIED BY '$NEXTCLOUD_DB_PASSWORD';"
mariadb -e "GRANT ALL PRIVILEGES ON $NEXTCLOUD_DB.* TO '$NEXTCLOUD_DB_USER'@'localhost';"
mariadb -e "FLUSH PRIVILEGES;"

# PHP für Nextcloud optimieren
log "info" "Optimiere PHP für Nextcloud..."
cat <<EOF > /etc/php/$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')/apache2/conf.d/99-nextcloud.ini
memory_limit = 512M
upload_max_filesize = 2G
post_max_size = 2G
max_execution_time = 300
date.timezone = Europe/Berlin
opcache.enable=1
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=10000
opcache.memory_consumption=128
opcache.save_comments=1
opcache.revalidate_freq=1
EOF

# Redis-Konfiguration optimieren
log "info" "Optimiere Redis..."
sed -i 's/port 6379/port 0/' /etc/redis/redis.conf
sed -i 's|# unixsocket /var/run/redis/redis-server.sock|unixsocket /var/run/redis/redis-server.sock|' /etc/redis/redis.conf
# Stelle sicher, dass unixsocketperm auf 770 gesetzt ist, unabhängig vom aktuellen Wert
if grep -q "unixsocketperm 700" /etc/redis/redis.conf; then
  sed -i 's/unixsocketperm 700/unixsocketperm 770/' /etc/redis/redis.conf
elif grep -q "# unixsocketperm 700" /etc/redis/redis.conf; then
  sed -i 's/# unixsocketperm 700/unixsocketperm 770/' /etc/redis/redis.conf
else
  # Falls der Eintrag in einem anderen Format existiert oder fehlt
  sed -i '/unixsocket .*redis.*sock/a unixsocketperm 770' /etc/redis/redis.conf
fi
usermod -a -G redis www-data
systemctl restart redis-server

# Nextcloud herunterladen
log "info" "Lade Nextcloud herunter..."
cd /tmp
wget https://download.nextcloud.com/server/releases/latest.zip -O nextcloud.zip
unzip nextcloud.zip
mv nextcloud /var/www/
chown -R www-data:www-data /var/www/nextcloud
chmod -R 755 /var/www/nextcloud

# Apache konfigurieren
log "info" "Konfiguriere Apache..."
cat <<EOF > /etc/apache2/sites-available/nextcloud.conf
<VirtualHost *:80>
    ServerName $DOMAIN
    DocumentRoot /var/www/nextcloud
    
    <Directory /var/www/nextcloud/>
        Require all granted
        AllowOverride All
        Options FollowSymLinks MultiViews
        
        <IfModule mod_dav.c>
            Dav off
        </IfModule>
        
        SetEnv HOME /var/www/nextcloud
        SetEnv HTTP_HOME /var/www/nextcloud
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/nextcloud_error.log
    CustomLog \${APACHE_LOG_DIR}/nextcloud_access.log combined
    
    <IfModule mod_headers.c>
        Header always set Strict-Transport-Security "max-age=15552000; includeSubDomains"
        Header always set Referrer-Policy "no-referrer"
        Header always set X-Content-Type-Options "nosniff"
        Header always set X-Download-Options "noopen"
        Header always set X-Frame-Options "SAMEORIGIN"
        Header always set X-Permitted-Cross-Domain-Policies "none"
        Header always set X-Robots-Tag "none"
        Header always set X-XSS-Protection "1; mode=block"
    </IfModule>
</VirtualHost>
EOF

a2ensite nextcloud.conf
a2enmod rewrite headers env dir mime setenvif ssl
a2dissite 000-default.conf

# Let's Encrypt SSL-Zertifikat holen
if [ "$IS_INTERNET_DOMAIN" = true ]; then
  log "info" "Versuche Let's Encrypt SSL-Zertifikat zu erhalten..."
  certbot --apache -d "$DOMAIN" --non-interactive --agree-tos -m admin@$DOMAIN || {
    log "warning" "Let's Encrypt fehlgeschlagen. Selbstsigniertes Zertifikat wird erstellt."
    SELFSIGNED=true
  }
else
  log "warning" "Lokale Domain erkannt. Überspringe Let's Encrypt."
  SELFSIGNED=true
fi

# Selbstsigniertes Zertifikat erstellen falls nötig
if [ "$SELFSIGNED" = true ]; then
  log "info" "Erstelle selbstsigniertes Zertifikat..."
  mkdir -p /etc/ssl/nextcloud/
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/nextcloud/nextcloud.key \
    -out /etc/ssl/nextcloud/nextcloud.crt \
    -subj "/CN=$DOMAIN" -addext "subjectAltName = DNS:$DOMAIN"
  
  cat <<EOF > /etc/apache2/sites-available/nextcloud-ssl.conf
<VirtualHost *:443>
    ServerName $DOMAIN
    DocumentRoot /var/www/nextcloud
    
    SSLEngine on
    SSLCertificateFile /etc/ssl/nextcloud/nextcloud.crt
    SSLCertificateKeyFile /etc/ssl/nextcloud/nextcloud.key
    
    <Directory /var/www/nextcloud/>
        Require all granted
        AllowOverride All
        Options FollowSymLinks MultiViews
        
        <IfModule mod_dav.c>
            Dav off
        </IfModule>
        
        SetEnv HOME /var/www/nextcloud
        SetEnv HTTP_HOME /var/www/nextcloud
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/nextcloud_ssl_error.log
    CustomLog \${APACHE_LOG_DIR}/nextcloud_ssl_access.log combined
    
    <IfModule mod_headers.c>
        Header always set Strict-Transport-Security "max-age=15552000; includeSubDomains"
        Header always set Referrer-Policy "no-referrer"
        Header always set X-Content-Type-Options "nosniff"
        Header always set X-Download-Options "noopen"
        Header always set X-Frame-Options "SAMEORIGIN"
        Header always set X-Permitted-Cross-Domain-Policies "none"
        Header always set X-Robots-Tag "none"
        Header always set X-XSS-Protection "1; mode=block"
    </IfModule>
</VirtualHost>
EOF
  
  a2ensite nextcloud-ssl.conf
fi

systemctl reload apache2

# Nextcloud Installation
log "info" "Installiere Nextcloud..."
sudo -u www-data php /var/www/nextcloud/occ maintenance:install \
  --admin-user "$NEXTCLOUD_ADMIN_USER" \
  --admin-pass "$NEXTCLOUD_ADMIN_PASSWORD" \
  --database "mysql" \
  --database-name "$NEXTCLOUD_DB" \
  --database-user "$NEXTCLOUD_DB_USER" \
  --database-pass "$NEXTCLOUD_DB_PASSWORD" \
  --data-dir "/var/www/nextcloud/data"

# Redis-Konfiguration einfügen
log "info" "Füge Redis-Konfiguration zur config.php hinzu..."
CONFIG_FILE="/var/www/nextcloud/config/config.php"
sed -i "/);/i\  'memcache.local' => '\\OC\\Memcache\\APCu'," "$CONFIG_FILE"
sed -i "/);/i\  'memcache.locking' => '\\OC\\Memcache\\Redis'," "$CONFIG_FILE"
sed -i "/);/i\  'redis' => array (\n    'host' => '/var/run/redis/redis-server.sock',\n    'port' => 0,\n  )," "$CONFIG_FILE"

# Trusted Domains konfigurieren
log "info" "Konfiguriere Trusted Domains..."
SERVER_IP=$(hostname -I | awk '{print $1}')
sudo -u www-data php /var/www/nextcloud/occ config:system:set trusted_domains 1 --value="$SERVER_IP"
sudo -u www-data php /var/www/nextcloud/occ config:system:set trusted_domains 2 --value="$DOMAIN"

# Cron-Job für Nextcloud einrichten
log "info" "Richte Cron-Job für Nextcloud ein..."
echo "*/5 * * * * www-data php -f /var/www/nextcloud/cron.php > /dev/null 2>&1" > /etc/cron.d/nextcloud
sudo -u www-data php /var/www/nextcloud/occ background:cron

# Abschließende Optimierungen
log "info" "Führe abschließende Optimierungen durch..."
sudo -u www-data php /var/www/nextcloud/occ db:add-missing-indices
sudo -u www-data php /var/www/nextcloud/occ db:convert-filecache-bigint

# Abschließende Informationen
log "success" "Nextcloud-Installation abgeschlossen."
echo -e "${GREEN}----------------------------------------${NC}"
echo -e "${GREEN}URL: https://$DOMAIN${NC}"
echo -e "${GREEN}Admin-Benutzer: $NEXTCLOUD_ADMIN_USER${NC}"
echo -e "${GREEN}Admin-Passwort: $NEXTCLOUD_ADMIN_PASSWORD${NC}"
echo -e "${GREEN}DB Benutzer: $NEXTCLOUD_DB_USER${NC}"
echo -e "${GREEN}DB Passwort: $NEXTCLOUD_DB_PASSWORD${NC}"
if [ -n "$SERVER_IP" ]; then
  echo -e "${GREEN}Alternativ-URL: https://$SERVER_IP${NC}"
fi
echo -e "${GREEN}----------------------------------------${NC}"
echo -e "${YELLOW}WICHTIG: Bewahre diese Informationen sicher auf!${NC}"

# Zugangsdaten in sichere Datei speichern
CREDENTIALS_FILE="/root/nextcloud_credentials.txt"
log "info" "Speichere Zugangsdaten in $CREDENTIALS_FILE"

cat <<EOF > $CREDENTIALS_FILE
# Nextcloud Installations-Zugangsdaten
# Erstellt am $(date)
# VERTRAULICH - NUR FÜR ROOT-BENUTZER!

URL: https://$DOMAIN
$([ -n "$SERVER_IP" ] && echo "Alternativ-URL: https://$SERVER_IP")

Admin-Benutzer: $NEXTCLOUD_ADMIN_USER
Admin-Passwort: $NEXTCLOUD_ADMIN_PASSWORD

Datenbank-Name: $NEXTCLOUD_DB
Datenbank-Benutzer: $NEXTCLOUD_DB_USER
Datenbank-Passwort: $NEXTCLOUD_DB_PASSWORD
EOF

# Berechtigungen für Credentials-Datei auf nur root lesbar setzen
chmod 600 $CREDENTIALS_FILE
echo -e "${YELLOW}WICHTIG: Zugangsdaten wurden in $CREDENTIALS_FILE gespeichert.${NC}"
echo -e "${YELLOW}Diese Datei ist nur für den root-Benutzer lesbar!${NC}"

# Bereinigen
log "info" "Bereinige temporäre Dateien..."
rm -rf /tmp/nextcloud /tmp/nextcloud.zip

##################################################################################################################################

# Nextcloud Pfade
NEXTCLOUD_PATH="/var/www/nextcloud"
CONFIG_PATH="$NEXTCLOUD_PATH/config/config.php"
DATA_PATH=$(grep -oP "(?<='datadirectory' => ').*?(?=')" $CONFIG_PATH 2>/dev/null || echo "$NEXTCLOUD_PATH/data")

# Logdateien
APACHE_ERROR_LOG="/var/log/apache2/error.log"
NEXTCLOUD_LOG="$NEXTCLOUD_PATH/data/nextcloud.log"

echo -e "${YELLOW}=== Nextcloud Fehlerdiagnose & Reparatur ===${NC}"

# 1. Apache und PHP Status prüfen
echo -e "${GRAY}Prüfe Apache und PHP Status...${NC}"
if ! systemctl is-active --quiet apache2; then
  echo -e "${RED}Apache läuft nicht! Starte Apache...${NC}"
  systemctl start apache2
  echo -e "${GREEN}Apache wurde gestartet.${NC}"
else
  echo -e "${GREEN}Apache läuft.${NC}"
fi

# 2. PHP-Module überprüfen
echo -e "${GRAY}Prüfe erforderliche PHP-Module...${NC}"
MISSING_MODULES=false
PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')

REQUIRED_MODULES=(
  "curl" "gd" "intl" "json" "mbstring" "mysql" "zip" "xml" "fileinfo"
  "bz2" "gmp" "apcu" "redis" "imagick" "opcache"
)

for MODULE in "${REQUIRED_MODULES[@]}"; do
  if ! php -m | grep -q -i "$MODULE"; then
    echo -e "${RED}PHP-Modul '$MODULE' fehlt! Installiere...${NC}"
    MISSING_MODULES=true
    apt-get install -y php$PHP_VERSION-$MODULE
  fi
done

if [ "$MISSING_MODULES" = true ]; then
  echo -e "${GREEN}Fehlende PHP-Module wurden installiert. Apache wird neu gestartet...${NC}"
  systemctl restart apache2
else
  echo -e "${GREEN}Alle erforderlichen PHP-Module sind installiert.${NC}"
fi

# 3. Berechtigungen korrigieren
echo -e "${GRAY}Korrigiere Datei-Berechtigungen...${NC}"
chown -R www-data:www-data $NEXTCLOUD_PATH
find $NEXTCLOUD_PATH -type d -exec chmod 750 {} \;
find $NEXTCLOUD_PATH -type f -exec chmod 640 {} \;
chmod 755 $NEXTCLOUD_PATH/occ
echo -e "${GREEN}Datei-Berechtigungen korrigiert.${NC}"

# 4. Datenbank-Verbindung prüfen
echo -e "${GRAY}Prüfe Datenbank-Verbindung...${NC}"
if [ -f "$CONFIG_PATH" ]; then
  DB_NAME=$(grep -oP "(?<='dbname' => ').*?(?=')" $CONFIG_PATH)
  DB_USER=$(grep -oP "(?<='dbuser' => ').*?(?=')" $CONFIG_PATH)
  DB_PASS=$(grep -oP "(?<='dbpassword' => ').*?(?=')" $CONFIG_PATH)
  DB_HOST=$(grep -oP "(?<='dbhost' => ').*?(?=')" $CONFIG_PATH)
  
  if [ -n "$DB_USER" ] && [ -n "$DB_PASS" ] && [ -n "$DB_NAME" ]; then
    if mariadb -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME;" 2>/dev/null; then
      echo -e "${GREEN}Datenbank-Verbindung erfolgreich.${NC}"
    else
      echo -e "${RED}Datenbank-Verbindung fehlgeschlagen! Überprüfe die Datenbank-Zugangsdaten.${NC}"
    fi
  else
    echo -e "${RED}Datenbank-Konfiguration unvollständig oder nicht gefunden.${NC}"
  fi
else
  echo -e "${RED}Nextcloud config.php nicht gefunden!${NC}"
fi

# 5. PHP-Einstellungen optimieren
echo -e "${GRAY}Optimiere PHP-Einstellungen...${NC}"
cat <<EOF > /etc/php/$PHP_VERSION/apache2/conf.d/99-nextcloud.ini
memory_limit = 512M
upload_max_filesize = 2G
post_max_size = 2G
max_execution_time = 300
date.timezone = Europe/Berlin
opcache.enable=1
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=10000
opcache.memory_consumption=128
opcache.save_comments=1
opcache.revalidate_freq=1
EOF
echo -e "${GREEN}PHP-Einstellungen optimiert.${NC}"

# 6. Sonderfall: Redis-Konfiguration prüfen
echo -e "${GRAY}Prüfe Redis-Konfiguration...${NC}"
if grep -q "memcache.locking" "$CONFIG_PATH"; then
  REDIS_SOCKET=$(grep -oP "(?<='host' => ').*?(?=')" "$CONFIG_PATH" | grep -i "redis")
  if [ -n "$REDIS_SOCKET" ]; then
    if [ ! -e "$REDIS_SOCKET" ]; then
      echo -e "${RED}Redis-Socket '$REDIS_SOCKET' existiert nicht!${NC}"
      echo -e "${GRAY}Prüfe Redis-Installation...${NC}"
      
      if ! systemctl is-active --quiet redis-server; then
        echo -e "${RED}Redis-Server ist nicht aktiv! Starte Redis...${NC}"
        systemctl start redis-server
      fi
      
      # Redis-Konfiguration anpassen
      echo -e "${GRAY}Passe Redis-Konfiguration an...${NC}"
      sed -i 's/port 6379/port 0/' /etc/redis/redis.conf
      sed -i 's|# unixsocket /var/run/redis/redis-server.sock|unixsocket /var/run/redis/redis-server.sock|' /etc/redis/redis.conf
      # Stelle sicher, dass unixsocketperm auf 770 gesetzt ist, unabhängig vom aktuellen Wert
      if grep -q "unixsocketperm 700" /etc/redis/redis.conf; then
        sed -i 's/unixsocketperm 700/unixsocketperm 770/' /etc/redis/redis.conf
      elif grep -q "# unixsocketperm 700" /etc/redis/redis.conf; then
        sed -i 's/# unixsocketperm 700/unixsocketperm 770/' /etc/redis/redis.conf
      else
        # Falls der Eintrag in einem anderen Format existiert oder fehlt
        sed -i '/unixsocket .*redis.*sock/a unixsocketperm 770' /etc/redis/redis.conf
      fi
      
      # www-data zur redis-Gruppe hinzufügen
      usermod -a -G redis www-data
      
      # Redis neu starten
      systemctl restart redis-server
      echo -e "${GREEN}Redis wurde neu konfiguriert und gestartet.${NC}"
    else
      echo -e "${GREEN}Redis-Socket existiert.${NC}"
    fi
  else
    echo -e "${YELLOW}Redis scheint nicht als Speicher-Backend konfiguriert zu sein.${NC}"
  fi
else
  echo -e "${YELLOW}Redis ist nicht als Locking-Mechanismus konfiguriert.${NC}"
fi

# 7. Nextcloud Wartungsmodus und Reparatur
echo -e "${GRAY}Setze Nextcloud in den Wartungsmodus...${NC}"
sudo -u www-data php $NEXTCLOUD_PATH/occ maintenance:mode --on
echo -e "${GREEN}Wartungsmodus aktiviert.${NC}"

echo -e "${GRAY}Führe Nextcloud-Reparatur durch...${NC}"
sudo -u www-data php $NEXTCLOUD_PATH/occ maintenance:repair
echo -e "${GREEN}Reparatur abgeschlossen.${NC}"

echo -e "${GRAY}Aktualisiere Datenbank-Indizes...${NC}"
sudo -u www-data php $NEXTCLOUD_PATH/occ db:add-missing-indices
echo -e "${GREEN}Datenbank-Indizes aktualisiert.${NC}"

echo -e "${GRAY}Konvertiere Filecache zu BigInt...${NC}"
sudo -u www-data php $NEXTCLOUD_PATH/occ db:convert-filecache-bigint
echo -e "${GREEN}Filecache konvertiert.${NC}"

echo -e "${GRAY}Deaktiviere Wartungsmodus...${NC}"
sudo -u www-data php $NEXTCLOUD_PATH/occ maintenance:mode --off
echo -e "${GREEN}Wartungsmodus deaktiviert.${NC}"

# 8. Apache neu starten
echo -e "${GRAY}Starte Apache neu...${NC}"
systemctl restart apache2
echo -e "${GREEN}Apache neu gestartet.${NC}"

# 9. Fehlerprotokollierung aktivieren für zukünftige Diagnose
echo -e "${GRAY}Aktiviere erweiterte Fehlerprotokollierung...${NC}"
sudo -u www-data php $NEXTCLOUD_PATH/occ config:system:set loglevel --value=1

# 10. Sichern der Zugangsdaten
if [ -f "$CONFIG_PATH" ]; then
  echo -e "${GRAY}Sichern der Zugangsdaten...${NC}"
  DB_NAME=$(grep -oP "(?<='dbname' => ').*?(?=')" $CONFIG_PATH)
  DB_USER=$(grep -oP "(?<='dbuser' => ').*?(?=')" $CONFIG_PATH)
  DB_PASS=$(grep -oP "(?<='dbpassword' => ').*?(?=')" $CONFIG_PATH)
  
  ADMIN_USER="admin"  # Standard, falls nicht anders bekannt
  # Versuche, den Admin-Benutzer zu finden, wenn möglich
  ADMIN_CHECK=$(sudo -u www-data php $NEXTCLOUD_PATH/occ user:list 2>/dev/null | grep -o "admin" || echo "")
  if [ -n "$ADMIN_CHECK" ]; then
    ADMIN_USER="admin"
  fi
  
  CREDENTIALS_FILE="/root/nextcloud_credentials.txt"
  # Aktuelle Domain aus der Apache-Konfiguration ermitteln
  DOMAIN=$(grep -oP "ServerName\s+\K\S+" /etc/apache2/sites-available/nextcloud*.conf 2>/dev/null || hostname -f)
  SERVER_IP=$(hostname -I | awk '{print $1}')
  
  cat <<EOF > $CREDENTIALS_FILE
# Nextcloud Installations-Zugangsdaten
# Gesichert am $(date)
# VERTRAULICH - NUR FÜR ROOT-BENUTZER!

URL: https://$DOMAIN
Alternativ-URL: https://$SERVER_IP

Admin-Benutzer: $ADMIN_USER
(Passwort konnte aus Sicherheitsgründen nicht automatisch ermittelt werden)

Datenbank-Name: $DB_NAME
Datenbank-Benutzer: $DB_USER
Datenbank-Passwort: $DB_PASS

# Hinweis: 
# Falls du das Admin-Passwort vergessen hast, kannst du ein neues setzen mit:
# sudo -u www-data php $NEXTCLOUD_PATH/occ user:resetpassword admin
EOF

  chmod 600 $CREDENTIALS_FILE
  echo -e "${GREEN}Zugangsdaten wurden in $CREDENTIALS_FILE gesichert.${NC}"
  echo -e "${YELLOW}WICHTIG: Diese Datei ist nur für den root-Benutzer lesbar!${NC}"
else
  echo -e "${RED}Config.php nicht gefunden. Konnte Zugangsdaten nicht sichern.${NC}"
fi

# 11. Logdateien anzeigen
echo -e "${YELLOW}=== Letzte Fehlermeldungen ===${NC}"
echo -e "${GRAY}Apache-Fehlerprotokoll:${NC}"
tail -n 20 $APACHE_ERROR_LOG

echo -e "${GRAY}Nextcloud-Fehlerprotokoll:${NC}"
if [ -f "$NEXTCLOUD_LOG" ]; then
  tail -n 20 $NEXTCLOUD_LOG
else
  echo -e "${RED}Nextcloud-Logdatei nicht gefunden.${NC}"
fi

exit 0
