#!/bin/bash

set -e

# Farben
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Distributionsprüfung: Nur Fedora zulässig
if ! grep -qi "fedora" /etc/os-release; then
    echo -e "${RED}Dieses Skript ist nur für Fedora gedacht. Abbruch...${NC}"
    exit 1
fi

echo -e "${GREEN}Dieses Skript installiert Nextcloud, MariaDB, Redis, NGINX und PHP auf Fedora.${NC}"
read -p "Möchtest du fortfahren? (ja/nein): " confirm
if [ "$confirm" != "ja" ]; then
    echo "Abbruch."
    exit 1
fi

# Paketliste installieren
dnf update -y
dnf install -y nginx mariadb-server redis certbot sudo \
    php php-fpm php-opcache php-gd php-mysqli php-curl php-mbstring php-json \
    php-xml php-dom php-ctype php-session php-iconv php-pdo php-pdo_mysql \
    php-intl php-fileinfo php-xmlreader php-tokenizer php-zip php-pecl-redis \
    unzip curl

# Dienste aktivieren
systemctl enable mariadb redis nginx php-fpm
systemctl start mariadb redis nginx php-fpm

# Root-Passwort generieren (OpenSSL)
ROOT_PASS=$(openssl rand -base64 16)

# Root-Passwort direkt setzen
mysql -e "UPDATE mysql.user SET authentication_string=PASSWORD('$ROOT_PASS') WHERE User='root';"
mysql -e "FLUSH PRIVILEGES;"

# MariaDB Sicherheitskonfiguration ohne Benutzerinteraktion
mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test%';"
mysql -e "DROP USER IF EXISTS ''@'localhost';"
mysql -e "DROP USER IF EXISTS ''@'$(hostname)';"
mysql -e "DELETE FROM mysql.user WHERE User='';"
mysql -e "FLUSH PRIVILEGES;"

# Datenbank und Benutzer anlegen
DB_NAME="nextcloud"
DB_USER="ncuser"
DB_PASS=$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 20)

mysql -e "CREATE DATABASE ${DB_NAME};"
mysql -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Nextcloud herunterladen
mkdir -p /var/www
cd /var/www
curl -LO https://download.nextcloud.com/server/releases/latest.zip
unzip latest.zip
rm latest.zip
chown -R nginx:nginx nextcloud

# PHP- und NGINX-Konfiguration
cat << EOF > /etc/nginx/conf.d/nextcloud.conf
server {
    listen 80;
    server_name _;

    root /var/www/nextcloud;
    index index.php;

    client_max_body_size 512M;
    fastcgi_buffers 64 4K;

    location / {
        try_files \$uri \$uri/ /index.php\$is_args\$args;
    }

    location ~ \.php\$ {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        include fastcgi.conf;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

# Zertifikat für interne IP und Domain erstellen
INTERNAL_IP=$(ip addr show | grep inet | grep -v 127.0.0.1 | awk '{print $2}' | cut -d'/' -f1 | head -n1)
read -p "Bitte gib deine öffentliche Domain ein (z.B. cloud.example.com): " DOMAIN

# Hosts-Datei aktualisieren (optional, z.B. intern DNS simulieren)
echo "127.0.0.1   ${DOMAIN}" >> /etc/hosts

# HTTPS einrichten
certbot certonly --standalone --preferred-challenges http -d "$DOMAIN" || true
certbot certonly --standalone --preferred-challenges http -d "$INTERNAL_IP" || true

# HTTPS in nginx aktivieren
cat << EOF > /etc/nginx/conf.d/ssl.conf
server {
    listen 443 ssl;
    server_name $DOMAIN $INTERNAL_IP;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    root /var/www/nextcloud;
    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php\$is_args\$args;
    }

    location ~ \.php\$ {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        include fastcgi.conf;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF

systemctl restart nginx

# Zugangsdaten
ADMIN_USER="admin"
ADMIN_PASS=$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 20)

/usr/bin/php /var/www/nextcloud/occ maintenance:install \
    --database "mysql" \
    --database-name "$DB_NAME" \
    --database-user "$DB_USER" \
    --database-pass "$DB_PASS" \
    --admin-user "$ADMIN_USER" \
    --admin-pass "$ADMIN_PASS"

# Rechte
chown -R nginx:nginx /var/www/nextcloud

# Zugangsdaten speichern
cat << EOF > /root/nextcloud_credentials.txt
Nextcloud installiert!

URL: https://$DOMAIN oder https://$INTERNAL_IP

Admin-Benutzer: $ADMIN_USER
Admin-Passwort: $ADMIN_PASS

Datenbank-Benutzer: $DB_USER
Datenbank-Passwort: $DB_PASS

MariaDB Root-Passwort: $ROOT_PASS
EOF

chmod 600 /root/nextcloud_credentials.txt

# Abschlussnachricht
echo -e "${GREEN}Nextcloud wurde erfolgreich installiert.${NC}"
echo -e "${GREEN}Zugriff über: https://$DOMAIN oder https://$INTERNAL_IP${NC}"
echo -e "${GREEN}Zugangsdaten findest du in: /root/nextcloud_credentials.txt${NC}"
