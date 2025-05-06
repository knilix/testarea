#!/bin/sh

set -e

# Farben
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Dieses Skript installiert Nextcloud, MariaDB, Redis, NGINX und PHP auf Alpine Linux.${NC}"
read -p "Möchtest du fortfahren? (ja/nein): " confirm
if [ "$confirm" != "ja" ]; then
    echo "Abbruch."
    exit 1
fi

# Distributionsprüfung
if ! grep -qi "alpine" /etc/os-release; then
    echo -e "${RED}Dieses Skript ist nur für Alpine Linux gedacht.${NC}"
    exit 1
fi

# Paketliste
apk update
apk upgrade
apk add nginx mariadb mariadb-client redis curl unzip certbot sudo

# PHP-FPM-Version automatisch erkennen
PHP_VERSION=$(apk info | grep -E '^php[0-9]{2}-fpm$' | head -n1 | cut -d'-' -f1)

if [ -z "$PHP_VERSION" ]; then
    echo -e "${RED}Keine passende PHP-FPM-Version gefunden. Installiere z. B. php82-fpm und starte das Skript erneut.${NC}"
    exit 1
fi

# PHP und Module installieren
apk add "$PHP_VERSION" \
    "$PHP_VERSION"-fpm "$PHP_VERSION"-opcache "$PHP_VERSION"-gd "$PHP_VERSION"-mysqli "$PHP_VERSION"-zlib \
    "$PHP_VERSION"-curl "$PHP_VERSION"-mbstring "$PHP_VERSION"-json "$PHP_VERSION"-xml "$PHP_VERSION"-dom \
    "$PHP_VERSION"-ctype "$PHP_VERSION"-session "$PHP_VERSION"-iconv "$PHP_VERSION"-pdo "$PHP_VERSION"-pdo_mysql \
    "$PHP_VERSION"-intl "$PHP_VERSION"-fileinfo "$PHP_VERSION"-simplexml "$PHP_VERSION"-tokenizer \
    "$PHP_VERSION"-xmlwriter "$PHP_VERSION"-xmlreader "$PHP_VERSION"-phar "$PHP_VERSION"-zip "$PHP_VERSION"-pcntl \
    php-cli php-pecl-redis

# Dienste aktivieren
rc-update add mariadb default
rc-update add redis default
rc-update add nginx default

# PHP-FPM als OpenRC-Dienst registrieren
PHP_FPM_BIN="/usr/sbin/${PHP_VERSION}-fpm"

if [ ! -f /etc/init.d/php-fpm ]; then
cat << EOF > /etc/init.d/php-fpm
#!/sbin/openrc-run

command=${PHP_FPM_BIN}
command_args="-y /etc/${PHP_VERSION}/php-fpm.conf --nodaemonize"
pidfile=/run/php-fpm.pid
name="PHP-FPM"
description="PHP FastCGI Process Manager"

depend() {
    need net
    use mysql
    after firewall
}
EOF
chmod +x /etc/init.d/php-fpm
fi

rc-update add php-fpm default

# Dienste starten
/etc/init.d/mariadb setup
rc-service mariadb start
rc-service redis start
rc-service php-fpm start
rc-service nginx start

# Nextcloud herunterladen
mkdir -p /var/www
cd /var/www
curl -LO https://download.nextcloud.com/server/releases/latest.zip
unzip latest.zip
rm latest.zip
chown -R nginx:nginx nextcloud

# MariaDB vorbereiten
DB_NAME="nextcloud"
DB_USER="ncuser"
DB_PASS=$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 20)

mysql -e "CREATE DATABASE ${DB_NAME};"
mysql -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# PHP- und NGINX-Konfiguration
cat << EOF > /etc/nginx/http.d/nextcloud.conf
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
cat << EOF > /etc/nginx/http.d/ssl.conf
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

rc-service nginx restart

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
EOF

chmod 600 /root/nextcloud_credentials.txt

# Abschlussnachricht
echo -e "${GREEN}Nextcloud wurde erfolgreich installiert.${NC}"
echo -e "${GREEN}Zugriff über: https://$DOMAIN oder https://$INTERNAL_IP${NC}"
echo -e "${GREEN}Zugangsdaten findest du in: /root/nextcloud_credentials.txt${NC}"
