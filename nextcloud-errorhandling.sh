#!/bin/bash
# Nextcloud Fehlerbehandlung Script
# Dieses Script behandelt häufige Ursachen für "Internal Server Error" in Nextcloud
#
# Nicht aktuell - nur zur Info - Only Test!
#

set -e

# Farbdefinitionen
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

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
      sed -i 's/^port .*/port 0/' /etc/redis/redis.conf
      sed -i 's|^#\? *unixsocket .*|unixsocket /var/run/redis/redis-server.sock|' /etc/redis/redis.conf

      # unixsocketperm 770 setzen oder ersetzen
      if grep -qE '^\s*#?\s*unixsocketperm' /etc/redis/redis.conf; then
        sed -i -E 's/^\s*#?\s*unixsocketperm\s+[0-9]+/unixsocketperm 770/' /etc/redis/redis.conf
      else
        sed -i '/^unixsocket /a unixsocketperm 770' /etc/redis/redis.conf
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
