#!/bin/bash

# Maintainer: @knilix
# Version: 1.0
# Hinweis: Nur für Debian (x64), root erforderlich
#
# Nextcloud Autoinstallation Script für Debian 12
# Mit MariaDB und Redis Cache
# ---------------------------------
# Farben
GRAY="\033[0;37m"
NC="\033[0m"

# MariaDB-Datenbank-Setup
DB_NAME="nextcloud"
DB_USER="nextcloud"
DB_PASS=$(openssl rand -base64 32)

# MariaDB-Root-Passwort
MYSQL_ROOT_PASS="DEIN_ROOT_PASSWORT"  # Setze hier das Root-Passwort für MariaDB

# Nextcloud Admin-Benutzer
NEXTCLOUD_ADMIN_USER="admin"
NEXTCLOUD_ADMIN_PASS="DEIN_ADMIN_PASSWORT"  # Setze hier das Admin-Passwort für Nextcloud

# Prüfe, ob der MariaDB-Benutzer existiert
echo -e "${GRAY}Prüfe, ob der MariaDB-Benutzer existiert...${NC}"

EXISTING_USER=$(mysql -u root -p$MYSQL_ROOT_PASS -e "SELECT User FROM mysql.user WHERE User = '$DB_USER';" -s -N)

if [ "$EXISTING_USER" != "$DB_USER" ]; then
  echo -e "${GRAY}Benutzer '$DB_USER' existiert nicht. Erstelle den Benutzer...${NC}"
  
  # Benutzer erstellen und Berechtigungen vergeben
  mysql -u root -p$MYSQL_ROOT_PASS <<EOF
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF
else
  echo -e "${GRAY}Benutzer '$DB_USER' existiert bereits. Überprüfe die Berechtigungen...${NC}"
  
  # Berechtigungen prüfen
  GRANTS=$(mysql -u root -p$MYSQL_ROOT_PASS -e "SHOW GRANTS FOR '$DB_USER'@'localhost';" -s -N)
  if [[ ! "$GRANTS" =~ "ALL PRIVILEGES" ]]; then
    echo -e "${GRAY}Benutzer '$DB_USER' hat nicht alle erforderlichen Berechtigungen. Berechtigungen werden angepasst...${NC}"
    mysql -u root -p$MYSQL_ROOT_PASS <<EOF
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF
  else
    echo -e "${GRAY}Berechtigungen für '$DB_USER' sind korrekt.${NC}"
  fi
fi

# Datenbank erstellen, falls sie noch nicht existiert
echo -e "${GRAY}Prüfe, ob die Datenbank existiert...${NC}"
DB_EXISTS=$(mysql -u root -p$MYSQL_ROOT_PASS -e "SHOW DATABASES LIKE '$DB_NAME';" -s -N)

if [ -z "$DB_EXISTS" ]; then
  echo -e "${GRAY}Datenbank '$DB_NAME' existiert nicht. Erstelle die Datenbank...${NC}"
  mysql -u root -p$MYSQL_ROOT_PASS -e "CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
else
  echo -e "${GRAY}Datenbank '$DB_NAME' existiert bereits.${NC}"
fi

# Nextcloud Installation
echo -e "${GRAY}Nextcloud wird installiert...${NC}"

# Hier die Nextcloud-Installation durchführen
# Wechsle ins Webverzeichnis, wo Nextcloud installiert werden soll (z. B. /var/www/nextcloud)
cd /var/www

# Lade Nextcloud herunter und entpacke es
wget https://download.nextcloud.com/server/releases/nextcloud-24.0.0.zip -O nextcloud.zip
unzip nextcloud.zip
rm nextcloud.zip
chown -R www-data:www-data nextcloud
chmod -R 755 nextcloud

# Führe die Nextcloud-Initialisierung mit 'occ' durch
sudo -u www-data php /var/www/nextcloud/occ maintenance:install \
  --database "mysql" \
  --database-name "$DB_NAME" \
  --database-user "$DB_USER" \
  --database-pass "$DB_PASS" \
  --admin-user "$NEXTCLOUD_ADMIN_USER" \
  --admin-pass "$NEXTCLOUD_ADMIN_PASS" \
  --data-dir "/var/www/nextcloud/data"

# Aufräumen
echo -e "${GRAY}Bereinige temporäre Dateien...${NC}"
rm -r /opt/scriptfiles/testarea-main 2>/dev/null
rm /opt/main.zip 2>/dev/null

# Bereinigung der installierten Pakete und Caches
echo -e "${GRAY}Bereinige nicht mehr benötigte Pakete und Caches...${NC}"
apt-get clean
apt-get autoremove -y

# Ende der Bereinigung
echo -e "${GRAY}Installation abgeschlossen und Bereinigung durchgeführt.${NC}"
