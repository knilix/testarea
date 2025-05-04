#!/bin/bash

# Maintainer: @knilix
# Version: 1.1
# Hinweis: Nur für Debian 12 (x64), root erforderlich
#
# Nextcloud Autoinstallation Script für Debian 12
# Mit MariaDB und Redis Cache
# ---------------------------------

# 1. Fehler-Handling (verbessert)
set -eo pipefail  # Stoppt auch bei Fehlern in Pipes
trap 'echo -e "\033[0;31mEin Fehler ist aufgetreten in Zeile $LINENO. Installation wurde abgebrochen.\033[0m"' ERR

# 2. Farben für die Ausgabe
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# 3. Funktion für Log-Meldungen
log() {
  local type=$1
  local message=$2
  local color=$BLUE
  
  case $type in
    "info") color=$BLUE ;;
    "success") color=$GREEN ;;
    "warning") color=$YELLOW ;;
    "error") color=$RED ;;
  esac
  
  echo -e "${color}${message}${NC}"
}

# 4. Prüfen, ob Script als root ausgeführt wird
if [ "$EUID" -ne 0 ]; then
  log "error" "Bitte führen Sie das Script als root aus."
  exit 1
fi

# 5. Prüfen ob Debian 12
if [ ! -f /etc/debian_version ] || [ "$(cat /etc/debian_version | cut -d'.' -f1)" -ne 12 ]; then
  log "error" "Dieses Script ist nur für Debian 12 konzipiert."
  exit 1
fi

# 6. Prüfen auf minimale Systemanforderungen
RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
DISK_GB=$(df -BG / | awk 'NR==2 {gsub("G", "", $4); print $4}')

if [ "$RAM_MB" -lt 2048 ]; then
  log "warning" "Warnung: Weniger als 2GB RAM verfügbar (${RAM_MB}MB). Nextcloud könnte langsam laufen."
fi

if [ "$DISK_GB" -lt 10 ]; then
  log "warning" "Warnung: Weniger als 10GB freier Speicherplatz verfügbar (${DISK_GB}GB)."
fi

# 7. Konfigurationsparameter
# Erstelle sicherere Passwörter ohne Sonderzeichen, die zu Shell-Problemen führen könnten
generate_password() {
  local length=$1
  tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$length"
}

MYSQL_ROOT_PASSWORD=$(generate_password 32)
NEXTCLOUD_DB_PASSWORD=$(generate_password 32)
NEXTCLOUD_DB_NAME="nextcloud"
NEXTCLOUD_DB_USER="nextcloud"
NEXTCLOUD_ADMIN_USER="admin"
NEXTCLOUD_ADMIN_PASSWORD=$(generate_password 16)
NEXTCLOUD_DATA_DIR="/var/www/nextcloud/data"
CREDENTIALS_FILE="/root/.nextcloud_credentials"
# 30. Befehl zum Anzeigen der Anmeldedaten erstellen
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
YELLOW='\033[1;33m'
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
echo -e "\nBackup-Verzeichnis: ${YELLOW}${BACKUP_DIR}${NC}"
echo -e "\nPHP-Version: ${GREEN}${PHP_VERSION}${NC}"
EOF

chmod +x /usr/local/bin/nextcloud-credentials

# 31. System-Status-Check-Tool erstellen
cat > /usr/local/bin/nextcloud-status << 'EOF'
#!/bin/bash
if [ "$EUID" -ne 0 ]; then
  echo "Bitte als root ausführen (sudo nextcloud-status)"
  exit 1
fi

# Farben für die Ausgabe
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}===== Nextcloud System Status =====${NC}\n"

# PHP-Version
PHP_VERSION=$(php -r "echo PHP_VERSION;")
echo -e "PHP Version: ${GREEN}${PHP_VERSION}${NC}"

# Apache Status
APACHE_STATUS=$(systemctl is-active apache2)
if [ "$APACHE_STATUS" = "active" ]; then
  echo -e "Apache Status: ${GREEN}Aktiv${NC}"
else
  echo -e "Apache Status: ${RED}Inaktiv${NC}"
fi

# MariaDB Status
MARIADB_STATUS=$(systemctl is-active mariadb)
if [ "$MARIADB_STATUS" = "active" ]; then
  echo -e "MariaDB Status: ${GREEN}Aktiv${NC}"
else
  echo -e "MariaDB Status: ${RED}Inaktiv${NC}"
fi

# Redis Status
REDIS_STATUS=$(systemctl is-active redis-server)
if [ "$REDIS_STATUS" = "active" ]; then
  echo -e "Redis Status: ${GREEN}Aktiv${NC}"
else
  echo -e "Redis Status: ${RED}Inaktiv${NC}"
fi

# Speicherplatz
echo -e "\n${BLUE}Speicherplatz:${NC}"
df -h / | awk 'NR==2 {print "Gesamt: " $2 "   Benutzt: " $3 "   Frei: " $4 "   Prozent: " $5}'

# RAM
echo -e "\n${BLUE}Arbeitsspeicher:${NC}"
free -h | grep "Mem:" | awk '{print "Gesamt: " $2 "   Benutzt: " $3 "   Frei: " $4 "   Cache: " $6}'

# CPU-Auslastung
echo -e "\n${BLUE}CPU-Auslastung:${NC}"
top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4 "% benutzt, " $6 + $8 + $10 "% frei"}'

# Nextcloud Version
if [ -f /var/www/nextcloud/version.php ]; then
  NC_VERSION=$(grep "OC_VersionString" /var/www/nextcloud/version.php | cut -d\' -f2)
  echo -e "\nNextcloud Version: ${GREEN}${NC_VERSION}${NC}"
fi

# Nextcloud Status Check
echo -e "\n${BLUE}Nextcloud Health Check:${NC}"
if [ -d /var/www/nextcloud ]; then
  cd /var/www/nextcloud
  sudo -u www-data php occ status
  echo -e "\n${BLUE}Nextcloud Integritätscheck:${NC}"
  sudo -u www-data php occ integrity:check-core
else
  echo -e "${RED}Nextcloud scheint nicht installiert zu sein!${NC}"
fi

# Letzter Login
echo -e "\n${BLUE}Letzte Logins:${NC}"
last -n 5 | head

# Check für wichtige Updates
echo -e "\n${BLUE}Verfügbare Updates:${NC}"
apt update -qq > /dev/null
UPDATES=$(apt list --upgradable 2>/dev/null | grep -c "upgradable")
SECURITY=$(apt list --upgradable 2>/dev/null | grep -c "security")

if [ "$UPDATES" -gt 0 ]; then
  echo -e "${YELLOW}$UPDATES Pakete können aktualisiert werden (davon $SECURITY Sicherheitsupdates)${NC}"
  echo -e "Führen Sie 'apt upgrade' aus, um diese zu installieren."
else
  echo -e "${GREEN}System ist aktuell.${NC}"
fi

echo -e "\n${BLUE}===== Status-Check abgeschlossen =====\n${NC}"
EOF

chmod +x /usr/local/bin/nextcloud-status

# 32. Automatisches Update-Script erstellen
cat > /usr/local/bin/nextcloud-update << 'EOF'
#!/bin/bash
if [ "$EUID" -ne 0 ]; then
  echo "Bitte als root ausführen (sudo nextcloud-update)"
  exit 1
fi

# Farben für die Ausgabe
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}===== Nextcloud Update wird ausgeführt =====\n${NC}"

# Backup erstellen
BACKUP_DIR="/root/nextcloud_backup_$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo -e "${YELLOW}Erstelle Backup in $BACKUP_DIR...${NC}"
mysqldump --single-transaction -h localhost -u root $(cat /root/.nextcloud_credentials | grep NEXTCLOUD_DB_NAME | cut -d= -f2) > "$BACKUP_DIR/nextcloud-sqlbkp.bak"
rsync -a /var/www/nextcloud "$BACKUP_DIR/"

# Nextcloud in Wartungsmodus versetzen
echo -e "${BLUE}Aktiviere Wartungsmodus...${NC}"
cd /var/www/nextcloud
sudo -u www-data php occ maintenance:mode --on

# Update durchführen
echo -e "${BLUE}Führe Update durch...${NC}"
sudo -u www-data php occ upgrade

# Wenn Update erfolgreich, Wartungsmodus deaktivieren
if [ $? -eq 0 ]; then
  echo -e "${GREEN}Update erfolgreich!${NC}"
  sudo -u www-data php occ maintenance:mode --off
  sudo -u www-data php occ maintenance:repair
  sudo -u www-data php occ db:add-missing-indices
  sudo -u www-data php occ db:add-missing-columns
  sudo -u www-data php occ db:convert-filecache-bigint
  echo -e "${GREEN}Wartungsmodus wurde deaktiviert.${NC}"
else
  echo -e "${RED}Update fehlgeschlagen! Wartungsmodus bleibt aktiviert.${NC}"
  echo -e "${YELLOW}Bitte prüfen Sie die Logs für weitere Informationen.${NC}"
  echo -e "${YELLOW}Backup wurde in $BACKUP_DIR erstellt.${NC}"
  exit 1
fi

echo -e "\n${BLUE}===== Update abgeschlossen =====\n${NC}"
EOF

chmod +x /usr/local/bin/nextcloud-update

# 33. Dokumentation erstellen
mkdir -p /root/nextcloud-docs
cat > /root/nextcloud-docs/README.md << EOF
# Nextcloud Dokumentation

## Installation
Nextcloud wurde automatisch installiert am $(date +"%Y-%m-%d %H:%M:%S") mit folgenden Parametern:
- Domain: https://${DOMAIN_NAME}
- IP: https://${SERVER_IP}
- PHP-Version: ${PHP_VERSION}
- Datenbank: MariaDB
- Cache: Redis

## Wichtige Verzeichnisse
- Nextcloud-Installation: /var/www/nextcloud
- Daten-Verzeichnis: ${NEXTCLOUD_DATA_DIR}
- Konfiguration: /var/www/nextcloud/config/config.php
- Logs: /var/log/nextcloud.log

## Nützliche Befehle
- Zugangsdaten anzeigen: \`sudo nextcloud-credentials\`
- System-Status prüfen: \`sudo nextcloud-status\`
- Nextcloud aktualisieren: \`sudo nextcloud-update\`

## Sicherheitshinweise
- Ein selbstsigniertes SSL-Zertifikat wurde erstellt. Für Produktivumgebungen sollte ein offizielles Zertifikat (z.B. Let's Encrypt) verwendet werden.
- Die Firewall (UFW) wurde konfiguriert, um nur SSH, HTTP und HTTPS zuzulassen.
- Backup-Verzeichnis: ${BACKUP_DIR}

## Wichtige Dateien
- Apache Konfiguration: /etc/apache2/sites-available/nextcloud.conf
- PHP Konfiguration: /etc/php/${PHP_VERSION}/fpm/conf.d/99-nextcloud.ini
- MariaDB Konfiguration: /etc/mysql/mariadb.conf.d/99-nextcloud.cnf
- Redis Konfiguration: /etc/redis/redis.conf
EOF

# 34. Let's Encrypt Auto-Setup vorbereiten (optional)
cat > /usr/local/bin/nextcloud-ssl << 'EOF'
#!/bin/bash
if [ "$EUID" -ne 0 ]; then
  echo "Bitte als root ausführen (sudo nextcloud-ssl)"
  exit 1
fi

# Farben für die Ausgabe
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}===== Let's Encrypt SSL für Nextcloud =====\n${NC}"

# Domain abfragen
read -p "Bitte geben Sie Ihre Domain ein (z.B. cloud.example.com): " DOMAIN

if [ -z "$DOMAIN" ]; then
  echo -e "${RED}Keine Domain angegeben. Abbruch.${NC}"
  exit 1
fi

# Prüfen, ob Domain erreichbar ist
echo -e "${YELLOW}Prüfe, ob Domain $DOMAIN erreichbar ist...${NC}"
if ! host $DOMAIN &>/dev/null; then
  echo -e "${RED}Die Domain $DOMAIN scheint nicht auf diesen Server zu zeigen.${NC}"
  echo -e "${YELLOW}Bitte stellen Sie sicher, dass die DNS-Einstellungen korrekt sind.${NC}"
  read -p "Trotzdem fortfahren? (j/N): " CONTINUE
  if [[ $CONTINUE != "j" && $CONTINUE != "J" ]]; then
    echo -e "${RED}Installation abgebrochen.${NC}"
    exit 1
  fi
fi

# Certbot installieren
echo -e "${BLUE}Installiere Certbot...${NC}"
apt update
apt install -y certbot python3-certbot-apache

# Zertifikat beantragen
echo -e "${BLUE}Beantrage Zertifikat für $DOMAIN...${NC}"
certbot --apache -d $DOMAIN

# Prüfen, ob Zertifikat erfolgreich installiert wurde
if [ $? -eq 0 ]; then
  echo -e "${GREEN}SSL-Zertifikat wurde erfolgreich installiert!${NC}"
  
  # Auto-Renewal testen
  echo -e "${BLUE}Teste Auto-Renewal...${NC}"
  certbot renew --dry-run
  
  # Nextcloud Config anpassen
  echo -e "${BLUE}Konfiguriere Nextcloud für HTTPS...${NC}"
  cd /var/www/nextcloud
  sudo -u www-data php occ config:system:set overwriteprotocol --value="https"
  sudo -u www-data php occ config:system:set trusted_domains 0 --value="$DOMAIN"
  
  echo -e "${GREEN}Einrichtung abgeschlossen! Nextcloud ist nun über https://$DOMAIN erreichbar.${NC}"
else
  echo -e "${RED}Fehler beim Beantragen des Zertifikats.${NC}"
  echo -e "${YELLOW}Bitte prüfen Sie die Logs für weitere Informationen.${NC}"
fi

echo -e "\n${BLUE}===== SSL-Setup abgeschlossen =====\n${NC}"
EOF

chmod +x /usr/local/bin/nextcloud-ssl

# 35. Überprüfen Sie die Installation und führen Sicherheitschecks durch
log "info" "Führe Sicherheitschecks durch..."

# Apache-Module prüfen
if ! apache2ctl -M | grep -q "ssl_module"; then
  log "warning" "Apache SSL-Modul ist nicht aktiviert. Aktiviere es..."
  a2enmod ssl
  systemctl restart apache2
fi

# PHP-Module prüfen
MISSING_PHP_MODULES=""
for module in curl gd mbstring xml zip intl mysql redis; do
  if ! php -m | grep -q "$module"; then
    MISSING_PHP_MODULES+="php-$module "
  fi
done

if [ ! -z "$MISSING_PHP_MODULES" ]; then
  log "warning" "Fehlende PHP-Module: $MISSING_PHP_MODULES. Installiere sie..."
  apt install -y $MISSING_PHP_MODULES
  systemctl restart $PHP_FPM_SERVICE
fi

# Redis-Socket-Berechtigungen prüfen
if [ ! -S /var/run/redis/redis-server.sock ]; then
  log "warning" "Redis-Socket nicht gefunden. Starte Redis neu..."
  systemctl restart redis-server
else
  REDIS_SOCKET_PERMS=$(stat -c "%a" /var/run/redis/redis-server.sock)
  if [ "$REDIS_SOCKET_PERMS" != "770" ]; then
    log "warning" "Falsche Redis-Socket-Berechtigungen: $REDIS_SOCKET_PERMS. Korrigiere..."
    chmod 770 /var/run/redis/redis-server.sock
  fi
fi

# 36. Aufräumen
log "info" "Bereinige temporäre Dateien..."
rm -f /tmp/nextcloud*
apt autoremove -y
apt clean

clear # für eine saubere Bildschirmanzeige

# 37. Installation abgeschlossen
log "success" "===== Nextcloud Installation abgeschlossen! ====="
echo ""
echo -e "Ihre Nextcloud ist unter folgenden URLs erreichbar:"
echo -e "Domain: ${GREEN}https://${DOMAIN_NAME}${NC}"
echo -e "IP-Adresse: ${GREEN}https://${SERVER_IP}${NC}"
echo -e "\nAdmin Benutzer: ${GREEN}${NEXTCLOUD_ADMIN_USER}${NC}"
echo -e "Admin Passwort: ${GREEN}${NEXTCLOUD_ADMIN_PASSWORD}${NC}"
echo -e "MariaDB Root Passwort: ${GREEN}${MYSQL_ROOT_PASSWORD}${NC}"

echo -e "\n${BLUE}Diese Anmeldedaten wurden in ${CREDENTIALS_FILE} gespeichert.${NC}"
echo -e "${BLUE}Sie können sie jederzeit mit dem Befehl 'nextcloud-credentials' anzeigen.${NC}"
echo -e "${BLUE}Für ein Let's Encrypt SSL-Zertifikat, verwenden Sie 'nextcloud-ssl'.${NC}"
echo -e "${BLUE}Für Systemstatus, verwenden Sie 'nextcloud-status'.${NC}"
echo -e "${BLUE}Für Updates, verwenden Sie 'nextcloud-update'.${NC}"
echo -e "${YELLOW}Dokumentation wurde in /root/nextcloud-docs/ erstellt.${NC}"

echo -e "\n${GREEN}Alle Aufgaben abgeschlossen!${NC}"
echo
echo -e "\nViel Erfolg mit Ihrer neuen Nextcloud-Installation!"
PASSWORD=$(generate_password 32)
NEXTCLOUD_DB_NAME="nextcloud"
NEXTCLOUD_DB_USER="nextcloud"
NEXTCLOUD_ADMIN_USER="admin"
NEXTCLOUD_ADMIN_PASSWORD=$(generate_password 16)
NEXTCLOUD_DATA_DIR="/var/www/nextcloud/data"
CREDENTIALS_FILE="/root/.nextcloud_credentials"

# Backup-Verzeichnis für Konfigurationsdateien
BACKUP_DIR="/root/nextcloud_install_backup_$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR"

# 8. Domain-Einstellungen verbessert
SERVER_IP=$(hostname -I | awk '{print $1}')
DOMAIN_NAME=$(hostname -f)

# Prüfen auf gültige Domain
if [ "$DOMAIN_NAME" = "localhost" ] || [ -z "$DOMAIN_NAME" ] || [ "$DOMAIN_NAME" = "$SERVER_IP" ]; then
  log "warning" "Kein gültiger Domainname gefunden. IP-Adresse wird verwendet: $SERVER_IP"
  DOMAIN_NAME=$SERVER_IP
fi

clear # für einen sauberen Start

# 9. Installationsparameter anzeigen
log "info" "=== Nextcloud Installationsscript für Debian 12 ==="
log "info" "Dieses Script installiert automatisch Nextcloud mit MariaDB und Redis."
echo ""
log "success" "Installationsparameter:"
echo -e "Domain: ${GREEN}$DOMAIN_NAME${NC}"
echo -e "IP-Adresse: ${GREEN}$SERVER_IP${NC}"
echo -e "Admin Benutzer: ${GREEN}$NEXTCLOUD_ADMIN_USER${NC}"
echo -e "Datenbank: ${GREEN}$NEXTCLOUD_DB_NAME${NC}"
echo -e "Speicherort: ${GREEN}$NEXTCLOUD_DATA_DIR${NC}"
echo -e "PHP Version: ${GREEN}$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null || echo "Wird installiert")${NC}"
echo ""

# 10. Bestätigung anfordern
read -p "Installation starten? (j/n): " CONFIRM
if [[ $CONFIRM != "j" && $CONFIRM != "J" ]]; then
  log "info" "Installation abgebrochen."
  exit 0
fi

# 11. System aktualisieren
log "info" "[1/12] System wird aktualisiert..."
apt update
apt upgrade -y

# 12. Firewall installieren und konfigurieren
log "info" "[2/12] Firewall wird installiert und konfiguriert..."
if ! dpkg -l | grep -q ufw; then
  apt install -y ufw
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow ssh
  ufw allow http
  ufw allow https
  echo "y" | ufw enable
  log "success" "Firewall wurde konfiguriert und aktiviert."
else
  # Nur sicherstellen, dass Ports offen sind
  ufw allow http
  ufw allow https
  log "success" "Firewall-Regeln aktualisiert."
fi

# 13. Benötigte Pakete installieren
log "info" "[3/12] Benötigte Pakete werden installiert..."
apt install -y apache2 mariadb-server redis-server \
  php php-cli php-common php-fpm php-json php-intl php-imagick \
  php-curl php-mbstring php-zip php-xml php-gd php-mysql \
  php-bz2 php-redis php-apcu unzip curl wget ssl-cert \
  libapache2-mod-php php-bcmath php-gmp htop

# 14. PHP-Version ermitteln
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"
log "success" "PHP $PHP_VERSION wurde installiert."

# 15. Apache für PHP konfigurieren
log "info" "[4/12] Apache für PHP konfigurieren..."

# Backup Apache-Konfiguration
if [ -f /etc/apache2/apache2.conf ]; then
  cp /etc/apache2/apache2.conf "$BACKUP_DIR/apache2.conf.bak"
fi

# Apache-Module aktivieren
a2enmod rewrite headers env dir mime ssl security2 http2

# 16. PHP-FPM konfigurieren
if [ -f "/etc/apache2/conf-available/php${PHP_VERSION}-fpm.conf" ]; then
  a2enconf "php${PHP_VERSION}-fpm"
else
  a2enmod proxy_fcgi setenvif
  a2enconf php-fpm
fi

# Apache-Konfiguration für mehr Sicherheit
cat > /etc/apache2/conf-available/security-hardening.conf << EOF
# Erweiterte Sicherheitseinstellungen für Apache
ServerTokens Prod
ServerSignature Off
TraceEnable Off

# XSS-Protection
Header set X-XSS-Protection "1; mode=block"
# Content-Security-Policy
Header set X-Content-Type-Options "nosniff"
# Clickjacking-Protection
Header set X-Frame-Options "SAMEORIGIN"
# HSTS (HTTP Strict Transport Security)
Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
# Referrer-Policy
Header set Referrer-Policy "same-origin"
EOF

a2enconf security-hardening
systemctl restart apache2

# 17. MariaDB absichern und konfigurieren
log "info" "[5/12] MariaDB wird konfiguriert..."

# Backup MariaDB-Konfiguration
if [ -f /etc/mysql/mariadb.cnf ]; then
  cp /etc/mysql/mariadb.cnf "$BACKUP_DIR/mariadb.cnf.bak"
fi

# MariaDB Root-Passwort setzen und Datenbank einrichten
mysql -e "SET PASSWORD FOR root@localhost = PASSWORD('${MYSQL_ROOT_PASSWORD}');"
mysql -e "DELETE FROM mysql.user WHERE User='';"
mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -e "DROP DATABASE IF EXISTS test;"
mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"

# 18. Prüfen, ob die Nextcloud-Datenbank bereits existiert
DB_EXISTS=$(mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES LIKE '${NEXTCLOUD_DB_NAME}';" | grep -o "${NEXTCLOUD_DB_NAME}" || echo "")
if [ -z "$DB_EXISTS" ]; then
  log "success" "Erstelle neue Datenbank: ${NEXTCLOUD_DB_NAME}"
  mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE ${NEXTCLOUD_DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
else
  log "info" "Datenbank ${NEXTCLOUD_DB_NAME} existiert bereits. Überspringe Erstellung..."
fi

# 19. Prüfen, ob der Datenbankbenutzer bereits existiert
USER_EXISTS=$(mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT User FROM mysql.user WHERE User='${NEXTCLOUD_DB_USER}';" | grep -o "${NEXTCLOUD_DB_USER}" || echo "")
if [ -z "$USER_EXISTS" ]; then
  log "success" "Erstelle neuen Datenbankbenutzer: ${NEXTCLOUD_DB_USER}"
  mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "CREATE USER '${NEXTCLOUD_DB_USER}'@'localhost' IDENTIFIED BY '${NEXTCLOUD_DB_PASSWORD}';"
  mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON ${NEXTCLOUD_DB_NAME}.* TO '${NEXTCLOUD_DB_USER}'@'localhost';"
else
  log "info" "Benutzer ${NEXTCLOUD_DB_USER} existiert bereits. Setze Passwort und Rechte..."
  mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SET PASSWORD FOR '${NEXTCLOUD_DB_USER}'@'localhost' = PASSWORD('${NEXTCLOUD_DB_PASSWORD}');"
  mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON ${NEXTCLOUD_DB_NAME}.* TO '${NEXTCLOUD_DB_USER}'@'localhost';"
fi

mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"

# 20. MariaDB für Nextcloud optimieren basierend auf verfügbarem RAM
log "info" "MariaDB wird optimiert basierend auf Systemressourcen..."

# Berechne Puffergröße basierend auf verfügbarem RAM (25% des RAM)
BUFFER_POOL_SIZE=$(echo "scale=0; $RAM_MB * 0.25 / 1" | bc)
if [ "$BUFFER_POOL_SIZE" -gt 2048 ]; then
  BUFFER_POOL_SIZE=2048  # Maximale Größe begrenzen
elif [ "$BUFFER_POOL_SIZE" -lt 128 ]; then
  BUFFER_POOL_SIZE=128   # Minimale Größe festlegen
fi

cat > /etc/mysql/mariadb.conf.d/99-nextcloud.cnf << EOF
[mysqld]
transaction_isolation = READ-COMMITTED
binlog_format = ROW
innodb_large_prefix=on
innodb_file_format=barracuda
innodb_file_per_table=1
max_allowed_packet = 128M
innodb_buffer_pool_size = ${BUFFER_POOL_SIZE}M
innodb_io_capacity = 2000
innodb_io_capacity_max = 4000
innodb_flush_method = O_DIRECT
innodb_redo_log_capacity = 128M
innodb_buffer_pool_instances = 1

# Connection settings
max_connections = 200
connect_timeout = 10
wait_timeout = 600
interactive_timeout = 600

# Query cache
query_cache_type = 1
query_cache_limit = 2M
query_cache_size = 32M

character-set-server = utf8mb4
collation-server = utf8mb4_general_ci
EOF

# 21. Redis konfigurieren
log "info" "[6/12] Redis wird konfiguriert..."

# Backup Redis-Konfiguration
if [ -f /etc/redis/redis.conf ]; then
  cp /etc/redis/redis.conf "$BACKUP_DIR/redis.conf.bak"
fi

# Redis Konfiguration anpassen
sed -i "s/port 6379/port 0/" /etc/redis/redis.conf
sed -i "s/# unixsocket/unixsocket/" /etc/redis/redis.conf
sed -i "s/# unixsocketperm 700/unixsocketperm 770/" /etc/redis/redis.conf
sed -i "s/^unixsocketperm 700/unixsocketperm 770/" /etc/redis/redis.conf
sed -i "s/# maxmemory <bytes>/maxmemory 128mb/" /etc/redis/redis.conf
sed -i "s/# maxmemory-policy noeviction/maxmemory-policy allkeys-lru/" /etc/redis/redis.conf

usermod -a -G redis www-data
systemctl restart redis-server

# 22. PHP für Nextcloud optimieren
log "info" "[7/12] PHP für Nextcloud optimieren..."

# Backup PHP-Konfiguration
if [ -f "/etc/php/${PHP_VERSION}/fpm/php.ini" ]; then
  cp "/etc/php/${PHP_VERSION}/fpm/php.ini" "$BACKUP_DIR/php-fpm.ini.bak"
fi

# PHP-Speicherlimit basierend auf RAM berechnen
PHP_MEMORY_LIMIT=$(echo "scale=0; $RAM_MB * 0.3 / 1" | bc)
if [ "$PHP_MEMORY_LIMIT" -gt 512 ]; then
  PHP_MEMORY_LIMIT=512  # Max 512MB
elif [ "$PHP_MEMORY_LIMIT" -lt 128 ]; then
  PHP_MEMORY_LIMIT=128  # Min 128MB
fi

# PHP-Konfiguration anpassen
cat > "/etc/php/${PHP_VERSION}/fpm/conf.d/99-nextcloud.ini" << EOF
; Optimierte PHP-Einstellungen für Nextcloud
memory_limit = ${PHP_MEMORY_LIMIT}M
upload_max_filesize = 500M
post_max_size = 500M
max_execution_time = 300
date.timezone = Europe/Berlin
max_input_time = 300
max_input_vars = 5000

; OpCache-Einstellungen
opcache.enable=1
opcache.enable_cli=1
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.memory_consumption=256
opcache.save_comments=1
opcache.revalidate_freq=1
opcache.jit=1255
opcache.jit_buffer_size=128M

; APCu-Einstellungen
apc.enabled=1
apc.shm_segments=1
apc.shm_size=128M
apc.ttl=7200
apc.enable_cli=1

; Allgemeine Sicherheit
expose_php = Off
session.cookie_httponly = 1
session.cookie_secure = 1
session.use_strict_mode = 1
session.cookie_samesite = "Lax"
EOF

# PHP-FPM-Pool-Konfiguration optimieren
PHP_FPM_POOL="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"
if [ -f "$PHP_FPM_POOL" ]; then
  cp "$PHP_FPM_POOL" "$BACKUP_DIR/www.conf.bak"
  
  # Bestimme die Anzahl der CPU-Kerne
  CPU_CORES=$(nproc)
  MAX_CHILDREN=$(( CPU_CORES * 4 ))
  START_SERVERS=$(( CPU_CORES * 2 ))
  MIN_SPARE_SERVERS=$START_SERVERS
  MAX_SPARE_SERVERS=$(( CPU_CORES * 3 ))
  
  # Setze optimierte Werte
  sed -i "s/^pm = .*/pm = dynamic/" "$PHP_FPM_POOL"
  sed -i "s/^pm.max_children = .*/pm.max_children = $MAX_CHILDREN/" "$PHP_FPM_POOL"
  sed -i "s/^pm.start_servers = .*/pm.start_servers = $START_SERVERS/" "$PHP_FPM_POOL"
  sed -i "s/^pm.min_spare_servers = .*/pm.min_spare_servers = $MIN_SPARE_SERVERS/" "$PHP_FPM_POOL"
  sed -i "s/^pm.max_spare_servers = .*/pm.max_spare_servers = $MAX_SPARE_SERVERS/" "$PHP_FPM_POOL"
  sed -i "s/^;pm.max_requests = .*/pm.max_requests = 500/" "$PHP_FPM_POOL"
fi

# PHP-FPM neustarten
if systemctl list-units --full -all | grep -q "$PHP_FPM_SERVICE"; then
  systemctl restart "$PHP_FPM_SERVICE"
else
  systemctl restart php-fpm
fi

# 23. Apache Virtual Host für Nextcloud konfigurieren
log "info" "[8/12] Apache Virtual Host für Nextcloud wird konfiguriert..."

# SSL-Zertifikat erstellen
mkdir -p /etc/ssl/nextcloud/
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/nextcloud/nextcloud.key \
  -out /etc/ssl/nextcloud/nextcloud.crt \
  -subj "/CN=${DOMAIN_NAME}/O=Nextcloud/C=DE"

# Setze sichere Berechtigungen für SSL-Zertifikate
chmod 600 /etc/ssl/nextcloud/nextcloud.key
chmod 644 /etc/ssl/nextcloud/nextcloud.crt

# OpenSSL Konfiguration mit moderner Cipher-Suite
cat > /etc/apache2/conf-available/ssl-params.conf << EOF
# Moderne SSL-Konfiguration
SSLProtocol All -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
SSLCipherSuite EECDH+AESGCM:EDH+AESGCM
SSLHonorCipherOrder On
SSLCompression Off
SSLSessionTickets Off
EOF

a2enconf ssl-params

# Virtual Host erstellen
cat > /etc/apache2/sites-available/nextcloud.conf << EOF
<VirtualHost *:80>
    ServerName ${DOMAIN_NAME}
    ServerAdmin webmaster@localhost
    Redirect permanent / https://${DOMAIN_NAME}/
</VirtualHost>

<VirtualHost *:443>
    ServerName ${DOMAIN_NAME}
    ServerAdmin webmaster@localhost
    
    DocumentRoot /var/www/nextcloud
    
    # HTTP/2 aktivieren
    Protocols h2 http/1.1
    
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
        
        # Sicherheitsheader für Nextcloud
        Header always set Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; media-src 'self'; frame-ancestors 'self'; frame-src 'self'"
        
        SetEnv HOME /var/www/nextcloud
        SetEnv HTTP_HOME /var/www/nextcloud
    </Directory>
    
    # Directory-Einstellungen für .well-known
    <IfModule mod_rewrite.c>
        RewriteEngine on
        RewriteRule ^/\.well-known/carddav https://%{SERVER_NAME}/remote.php/dav/ [R=301,L]
        RewriteRule ^/\.well-known/caldav https://%{SERVER_NAME}/remote.php/dav/ [R=301,L]
        RewriteRule ^/\.well-known/webfinger https://%{SERVER_NAME}/index.php/.well-known/webfinger [R=301,L]
        RewriteRule ^/\.well-known/nodeinfo https://%{SERVER_NAME}/index.php/.well-known/nodeinfo [R=301,L]
    </IfModule>
    
    # Performance-Optimierungen
    <IfModule mod_expires.c>
        ExpiresActive on
        ExpiresDefault "access plus 1 month"
        ExpiresByType text/css "access plus 1 year"
        ExpiresByType application/javascript "access plus 1 year"
        ExpiresByType image/gif "access plus 1 year"
        ExpiresByType image/png "access plus 1 year"
        ExpiresByType image/jpeg "access plus 1 year"
        ExpiresByType image/svg+xml "access plus 1 year"
        ExpiresByType image/x-icon "access plus 1 year"
        ExpiresByType application/font-woff "access plus 1 year"
        ExpiresByType application/font-woff2 "access plus 1 year"
        ExpiresByType application/vnd.ms-fontobject "access plus 1 year"
        ExpiresByType application/x-font-ttf "access plus 1 year"
        ExpiresByType font/opentype "access plus 1 year"
    </IfModule>
    
    # Komprimierung
    <IfModule mod_deflate.c>
        AddOutputFilterByType DEFLATE text/plain text/html text/css application/javascript application/json
        AddOutputFilterByType DEFLATE application/xml application/xhtml+xml image/x-icon
        AddOutputFilterByType DEFLATE application/x-font-ttf application/x-font application/x-font-opentype
        AddOutputFilterByType DEFLATE font/otf font/ttf font/eot font/woff font/woff2
    </IfModule>
    
    ErrorLog \${APACHE_LOG_DIR}/nextcloud_error.log
    CustomLog \${APACHE_LOG_DIR}/nextcloud_access.log combined
</VirtualHost>
EOF

# Virtual Host aktivieren
a2ensite nextcloud.conf
systemctl reload apache2

# 24. Nextcloud herunterladen und installieren
log "info" "[9/12] Nextcloud wird heruntergeladen und installiert..."

# Neueste stabile Version herunterladen mit Überprüfung
wget -q https://download.nextcloud.com/server/releases/latest.zip -O /tmp/nextcloud.zip
if [ ! -f /tmp/nextcloud.zip ] || [ ! -s /tmp/nextcloud.zip ]; then
  log "error" "Download von Nextcloud fehlgeschlagen!"
  exit 1
fi

# Prüfe, ob Nextcloud bereits installiert ist
if [ -d /var/www/nextcloud ]; then
  log "warning" "Nextcloud-Verzeichnis existiert bereits. Erstelle Backup..."
  tar -czf "$BACKUP_DIR/nextcloud_files_backup.tar.gz" -C /var/www nextcloud
  rm -rf /var/www/nextcloud
fi

# Entpacke Nextcloud
unzip -q /tmp/nextcloud.zip -d /var/www/
rm /tmp/nextcloud.zip

# Berechtigungen setzen
mkdir -p "${NEXTCLOUD_DATA_DIR}"
chown -R www-data:www-data /var/www/nextcloud/
chmod -R 750 /var/www/nextcloud/
find /var/www/nextcloud/ -type f -print0 | xargs -0 chmod 640
find /var/www/nextcloud/ -type d -print0 | xargs -0 chmod 750
chown -R www-data:www-data "${NEXTCLOUD_DATA_DIR}"

# 25. Nextcloud initialisieren
log "info" "[10/12] Nextcloud wird initialisiert..."

cd /var/www/nextcloud
sudo -u www-data php occ maintenance:install \
  --database "mysql" \
  --database-name "${NEXTCLOUD_DB_NAME}" \
  --database-user "${NEXTCLOUD_DB_USER}" \
  --database-pass "${NEXTCLOUD_DB_PASSWORD}" \
  --admin-user "${NEXTCLOUD_ADMIN_USER}" \
  --admin-pass "${NEXTCLOUD_ADMIN_PASSWORD}" \
  --data-dir "${NEXTCLOUD_DATA_DIR}"

# 26. Vertrauenswürdige Domains konfigurieren
sudo -u www-data php occ config:system:set trusted_domains 0 --value="${DOMAIN_NAME}"
sudo -u www-data php occ config:system:set trusted_domains 1 --value="${SERVER_IP}"

# 27. Caching und Optimierungen konfigurieren
log "info" "[11/12] Optimierungen werden angewendet..."
sudo -u www-data php occ config:system:set memcache.local --value='\OC\Memcache\APCu'
sudo -u www-data php occ config:system:set memcache.locking --value='\OC\Memcache\Redis'
sudo -u www-data php occ config:system:set redis host --value='/var/run/redis/redis-server.sock'
sudo -u www-data php occ config:system:set redis port --value=0
sudo -u www-data php occ config:system:set redis timeout --value=0.0
sudo -u www-data php occ config:system:set trusted_proxies 0 --value="127.0.0.1"
sudo -u www-data php occ config:system:set overwriteprotocol --value="https"
sudo -u www-data php occ config:system:set htaccess.RewriteBase --value="/"

# Zusätzliche Sicherheitseinstellungen
sudo -u www-data php occ config:system:set debug --value=false
sudo -u www-data php occ config:system:set log_type --value="file"
sudo -u www-data php occ config:system:set logfile --value="/var/log/nextcloud.log"
sudo -u www-data php occ config:system:set loglevel --value=2
sudo -u www-data php occ config:system:set logtimezone --value="Europe/Berlin"
sudo -u www-data php occ config:system:set log_rotate_size --value=10485760

# Erweiterte Performance-Einstellungen
sudo -u www-data php occ config:system:set filelocking.enabled --value="true"
sudo -u www-data php occ config:system:set enable_previews --value="true"
sudo -u www-data php occ config:system:set preview_max_x --value=2048
sudo -u www-data php occ config:system:set preview_max_y --value=2048
sudo -u www-data php occ config:system:set jpeg_quality --value=60
sudo -u www-data php occ config:system:set trashbin_retention_obligation --value="auto, 30"
sudo -u www-data php occ config:system:set versions_retention_obligation --value="auto, 30"

# Aktiviere empfohlene Apps
sudo -u www-data php occ app:enable admin_audit
sudo -u www-data php occ app:enable calendar
sudo -u www-data php occ app:enable contacts
sudo -u www-data php occ maintenance:update:htaccess

# 28. Cronjob für Nextcloud einrichten
log "info" "[12/12] Cron-Job wird eingerichtet..."
echo "*/5 * * * * www-data php -f /var/www/nextcloud/cron.php" > /etc/cron.d/nextcloud
sudo -u www-data php occ background:cron

# Logrotate für Nextcloud konfigurieren
cat > /etc/logrotate.d/nextcloud << EOF
/var/log/nextcloud.log {
  daily
  rotate 14
  compress
  delaycompress
  missingok
  notifempty
  create 0640 www-data www-data
}
EOF

# Log-Datei erstellen, falls nicht vorhanden
touch /var/log/nextcloud.log
chown www-data:www-data /var/log/nextcloud.log
chmod 0640 /var/log/nextcloud.log

# 29. Zugangsdaten in Datei speichern
cat > "${CREDENTIALS_FILE}" << EOF
NEXTCLOUD_URL_DOMAIN=https://${DOMAIN_NAME}
NEXTCLOUD_URL_IP=https://${SERVER_IP}
NEXTCLOUD_ADMIN_USER=${NEXTCLOUD_ADMIN_USER}
NEXTCLOUD_ADMIN_PASSWORD=${NEXTCLOUD_ADMIN_PASSWORD}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
NEXTCLOUD_DB_NAME=${NEXTCLOUD_DB_NAME}
NEXTCLOUD_DB_
