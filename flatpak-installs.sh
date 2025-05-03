#!/bin/bash

##################################################################
#   Maintainer: Dein Name / Dein Unternehmen
#   Version: 1.0
#   Beschreibung: Installations- und Bereinigungs-Skript für Nextcloud,
#   MariaDB, Redis sowie Aufräumprozesse. Löscht bei Erkennung einer
#   bestehenden Installation alle relevanten Daten.
##################################################################

# Definiere Farben
GRAY='\033[1;30m'
NC='\033[0m' # No Color

# WARNUNG und Bestätigungsabfrage
echo -e "${GRAY}WARNUNG: Eine bestehende Nextcloud-Installation und ihre Datenbank sowie Redis werden gelöscht, wenn diese erkannt wird. Dies löscht alle Daten!${NC}"
read -p "Möchtest du fortfahren und die Installation löschen? (ja/nein): " confirmation

if [[ "$confirmation" != "ja" ]]; then
    echo -e "${GRAY}Abbruch. Keine Änderungen vorgenommen.${NC}"
    exit 0
fi

# Überprüfe, ob Nextcloud bereits installiert ist
if [ -d "/var/www/nextcloud" ]; then
    echo -e "${GRAY}Nextcloud wurde erkannt. Lösche Dateien...${NC}"
    rm -rf /var/www/nextcloud
fi

# Überprüfe, ob die Datenbank 'nextcloud' existiert
if mysql -u root -p -e "USE nextcloud"; then
    echo -e "${GRAY}Datenbank 'nextcloud' wurde erkannt. Lösche die Datenbank...${NC}"
    mysql -u root -p -e "DROP DATABASE nextcloud;"
    mysql -u root -p -e "DROP USER 'nextcloud'@'localhost';"
fi

# Überprüfe, ob Redis läuft und lösche Redis-Cache
if systemctl is-active --quiet redis; then
    echo -e "${GRAY}Redis-Server erkannt. Lösche Redis-Daten...${NC}"
    systemctl stop redis
    rm -rf /var/lib/redis/*
    systemctl start redis
fi

# Weiterhin: Aufräumen von temporären Dateien
echo -e "${GRAY}Bereinige temporäre Dateien...${NC}"
rm -r /opt/scriptfiles/testarea-main 2>/dev/null
rm /opt/main.zip 2>/dev/null

# Installiere MariaDB und konfiguriere die Datenbank für Nextcloud
echo -e "${GRAY}Installiere MariaDB...${NC}"
apt update && apt install -y mariadb-server

# MariaDB sichern und Benutzer/Datenbank für Nextcloud erstellen
echo -e "${GRAY}MariaDB konfigurieren...${NC}"
mysql_secure_installation
mysql -u root -p -e "CREATE DATABASE nextcloud;"
mysql -u root -p -e "CREATE USER 'nextcloud'@'localhost' IDENTIFIED BY 'nextcloudpassword';"
mysql -u root -p -e "GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';"
mysql -u root -p -e "FLUSH PRIVILEGES;"

# Installiere Redis
echo -e "${GRAY}Installiere Redis...${NC}"
apt install -y redis-server

# Installiere Apache, PHP und benötigte Module für Nextcloud
echo -e "${GRAY}Installiere Apache und PHP...${NC}"
apt install -y apache2 libapache2-mod-php php php-cli php-fpm php-json php-common php-mysql php-redis php-imagick php-mbstring php-xml php-zip php-curl php-bz2

# Installiere Nextcloud
echo -e "${GRAY}Lade Nextcloud herunter...${NC}"
wget https://download.nextcloud.com/server/releases/nextcloud-25.0.3.tar.bz2 -P /tmp
tar -xjf /tmp/nextcloud-25.0.3.tar.bz2 -C /var/www/
chown -R www-data:www-data /var/www/nextcloud

# Nextcloud konfigurieren
echo -e "${GRAY}Nextcloud konfigurieren...${NC}"
mkdir -p /var/www/nextcloud/data
chown -R www-data:www-data /var/www/nextcloud/data

# Apache für Nextcloud konfigurieren
echo -e "${GRAY}Apache konfigurieren...${NC}"
cat <<EOF > /etc/apache2/sites-available/nextcloud.conf
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/nextcloud
    ServerName nextcloud.local

    <Directory /var/www/nextcloud/>
        Options +FollowSymlinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

a2ensite nextcloud.conf
a2enmod rewrite
systemctl restart apache2

# Setze Nextcloud-Datenbankverbindung und Initialisiere
echo -e "${GRAY}Nextcloud initialisieren...${NC}"
sudo -u www-data php /var/www/nextcloud/occ maintenance:install --database "mysql" --database-name "nextcloud" --database-user "nextcloud" --database-pass "nextcloudpassword" --admin-user "admin" --admin-pass "adminpassword"

# Redis für Nextcloud konfigurieren
echo -e "${GRAY}Redis konfigurieren...${NC}"
echo "redis://localhost:6379" > /var/www/nextcloud/config/config.php

# Bereinigung
echo -e "${GRAY}Bereinige temporäre Dateien...${NC}"
rm -r /opt/scriptfiles/testarea-main 2>/dev/null
rm /opt/main.zip 2>/dev/null

echo -e "${GRAY}Installation abgeschlossen!${NC}"
