#!/bin/bash
# Maintainer: @knilix
# Version: 1.0
# Hinweis: Nur für Ubuntu/Debian (x64), root erforderlich

#!/bin/bash

# Variablen definieren
DB_ROOT_USER="root"
DB_ROOT_PASS="root_password"  # Setze hier das Root-Passwort für MariaDB
NC_DB_USER="ncuser"
NC_DB_PASS="ncpassword"  # Setze hier das Passwort für den Nextcloud-Datenbankbenutzer
NC_DB_NAME="nextcloud"
NC_ADMIN_USER="admin"
NC_ADMIN_PASS="admin_password"
DOMAIN="yourdomain.com"  # Dein Domainname (für HTTPS)
EMAIL="youremail@example.com"  # Deine E-Mail-Adresse für Let's Encrypt

# UFW Konfiguration
UFW_ALLOW="22,80,443"

# Installiere benötigte Pakete
echo "Installiere notwendige Pakete..."
apt update && apt upgrade -y
apt install -y apache2 mariadb-server redis-server php php-cli php-fpm php-mysql php-redis php-json php-xml php-mbstring php-curl php-zip unzip curl gnupg2 lsb-release certbot python3-certbot-apache ufw fail2ban

# MariaDB Setup
echo "Einrichten von MariaDB..."
mysql -u"$DB_ROOT_USER" -p"$DB_ROOT_PASS" -e "CREATE DATABASE IF NOT EXISTS $NC_DB_NAME;"
mysql -u"$DB_ROOT_USER" -p"$DB_ROOT_PASS" -e "CREATE USER IF NOT EXISTS '$NC_DB_USER'@'localhost' IDENTIFIED BY '$NC_DB_PASS';"
mysql -u"$DB_ROOT_USER" -p"$DB_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON $NC_DB_NAME.* TO '$NC_DB_USER'@'localhost';"
mysql -u"$DB_ROOT_USER" -p"$DB_ROOT_PASS" -e "FLUSH PRIVILEGES;"

# Überprüfen, ob der Benutzer Zugriff auf die Datenbank hat
echo "Überprüfe Datenbankzugriff für $NC_DB_USER..."
if mysql -u "$NC_DB_USER" -p"$NC_DB_PASS" -e "SHOW TABLES IN $NC_DB_NAME;" &>/dev/null; then
    echo "Datenbankzugriff erfolgreich."
else
    echo "Fehler: Der Benutzer '$NC_DB_USER' hat keinen Zugriff auf die Datenbank '$NC_DB_NAME'."
    exit 1
fi

# Installiere Nextcloud
echo "Installiere Nextcloud..."
cd /var/www
curl -LO https://download.nextcloud.com/server/releases/nextcloud-26.0.0.zip
unzip nextcloud-26.0.0.zip
mv nextcloud /var/www/nextcloud
chown -R www-data:www-data /var/www/nextcloud
chmod -R 755 /var/www/nextcloud

# Apache konfigurieren
echo "Konfiguriere Apache..."
cat <<EOL > /etc/apache2/sites-available/nextcloud.conf
<VirtualHost *:80>
    ServerName $DOMAIN
    DocumentRoot /var/www/nextcloud
    <Directory /var/www/nextcloud>
        Options +FollowSymlinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOL

a2ensite nextcloud.conf
a2enmod rewrite headers env dir mime

# Redis Konfiguration
echo "Konfiguriere Redis für Nextcloud..."
sed -i "s/;session.save_handler = files/session.save_handler = redis/" /etc/php/*/fpm/php.ini
sed -i "s/;session.save_path = \"/var/lib/php/sessions\"/session.save_path = \"\"/g" /etc/php/*/fpm/php.ini
echo "session.save_path = \"tcp://localhost:6379\"" >> /etc/php/*/fpm/php.ini

# HTTPS mit Let's Encrypt
echo "Einrichten von HTTPS mit Let's Encrypt..."
certbot --apache -d $DOMAIN --email $EMAIL --agree-tos --no-eff-email

# UFW einrichten
echo "Einrichten der Firewall (UFW)..."
ufw allow OpenSSH
ufw allow 80,443/tcp
ufw enable

# Fail2Ban einrichten
echo "Einrichten von Fail2Ban..."
systemctl enable fail2ban
systemctl start fail2ban

# Nextcloud installieren und konfigurieren
echo "Installiere und konfiguriere Nextcloud..."
sudo -u www-data php /var/www/nextcloud/occ maintenance:install --database "mysql" --database-name "$NC_DB_NAME" --database-user "$NC_DB_USER" --database-pass "$NC_DB_PASS" --admin-user "$NC_ADMIN_USER" --admin-pass "$NC_ADMIN_PASS" --data-dir "/var/nc_data"

# Weiterleitungen in Apache konfigurieren
echo "Füge Weiterleitungen für HTTPS hinzu..."
cat <<EOL >> /etc/apache2/sites-available/nextcloud.conf
<VirtualHost *:443>
    ServerName $DOMAIN
    DocumentRoot /var/www/nextcloud
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/$DOMAIN/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/$DOMAIN/privkey.pem
    <Directory /var/www/nextcloud>
        Options +FollowSymlinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOL

a2ensite nextcloud.conf
a2enmod ssl

# Apache neu starten
echo "Starte Apache neu..."
systemctl restart apache2

# Bestätigung der Installation
echo "Nextcloud wurde erfolgreich installiert und ist unter https://$DOMAIN erreichbar."
echo "Die Datenbankbenutzerinformationen:"
echo "Datenbank: $NC_DB_NAME"
echo "Benutzer: $NC_DB_USER"
echo "Passwort: $NC_DB_PASS"
echo "Admin Benutzer: $NC_ADMIN_USER"
echo "Admin Passwort: $NC_ADMIN_PASS"
# === Abschluss ===
echo -e "\n${GREEN}Installation abgeschlossen!${NC}"
echo -e "${YELLOW}Zugriff: https://$DOMAIN${NC}"
echo -e "${YELLOW}Admin-Benutzer: $NEXTCLOUD_ADMIN${NC}"
echo -e "${YELLOW}Admin-Passwort: $NEXTCLOUD_ADMIN_PASS${NC}"
echo -e "${YELLOW}DB-Passwort: $NEXTCLOUD_DB_PASS${NC}"
echo

