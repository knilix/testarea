#!/bin/sh

set -e

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}Dieses Skript installiert Nextcloud mit HTTPS (öffentlich + intern) und Sicherheitsfeatures auf Alpine Linux.${NC}"
printf "Möchten Sie fortfahren? (j/N): "
read -r confirm
if [ "$confirm" != "j" ]; then
  echo -e "${RED}Abgebrochen.${NC}"
  exit 1
fi

read -r -p "Gib die öffentliche Domain für HTTPS ein (z. B. cloud.example.com): " DOMAIN
if [ -z "$DOMAIN" ]; then
  echo -e "${RED}Keine Domain eingegeben. Abbruch.${NC}"
  exit 1
fi

# Alpine prüfen
if [ ! -f /etc/alpine-release ]; then
  echo -e "${RED}Dieses Skript funktioniert nur auf Alpine Linux.${NC}"
  exit 1
fi

# Interne IP ermitteln
INTERNAL_IP=$(ip a | awk '/inet 10\./ || /inet 192\.168\./ {gsub(/\/.*/, "", $2); print $2; exit}')
if [ -z "$INTERNAL_IP" ]; then
  INTERNAL_IP="127.0.0.1"
fi

# Pakete
apk update
apk upgrade
apk add php php-fpm php-opcache php-gd php-mysqli php-zlib php-curl php-mbstring php-json php-xml php-dom php-ctype php-session php-iconv \
    php-pdo php-pdo_mysql php-pecl-redis php-intl php-posix php-fileinfo php-simplexml php-tokenizer php-xmlwriter php-xmlreader \
    mariadb mariadb-client redis nginx curl sudo unzip openssl php-cli php-phar php-zip php-pcntl socat acme.sh iptables denyhosts

rc-update add mariadb default
rc-update add redis default
rc-update add php-fpm7 default
rc-update add nginx default
rc-update add iptables default
rc-update add denyhosts default

# DB vorbereiten
mysql_install_db --user=mysql --basedir=/usr --datadir=/var/lib/mysql
rc-service mariadb start

# Zugangsdaten
NEXTCLOUD_DB="nextcloud"
NEXTCLOUD_USER="nc_user"
NEXTCLOUD_PASS="$(openssl rand -hex 12)"
NEXTCLOUD_ADMIN="admin"
NEXTCLOUD_ADMIN_PASS="$(openssl rand -hex 12)"

mysql -e "CREATE DATABASE ${NEXTCLOUD_DB};"
mysql -e "CREATE USER '${NEXTCLOUD_USER}'@'localhost' IDENTIFIED BY '${NEXTCLOUD_PASS}';"
mysql -e "GRANT ALL PRIVILEGES ON ${NEXTCLOUD_DB}.* TO '${NEXTCLOUD_USER}'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

rc-service redis start
rc-service php-fpm7 start

# Nextcloud holen
cd /var/www/localhost/htdocs || exit 1
curl -o nextcloud.zip https://download.nextcloud.com/server/releases/latest.zip
unzip nextcloud.zip
rm nextcloud.zip
chown -R nginx:nginx nextcloud

# Let's Encrypt Zertifikat
mkdir -p /var/lib/acme
cat > /etc/nginx/conf.d/acme.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    location /.well-known/acme-challenge/ {
        root /var/lib/acme;
    }
}
EOF
rc-service nginx restart

acme.sh --issue -d "$DOMAIN" --webroot /var/lib/acme
CERT_DIR="/etc/ssl/nextcloud"
mkdir -p "$CERT_DIR"
acme.sh --install-cert -d "$DOMAIN" \
  --key-file "$CERT_DIR/privkey.pem" \
  --fullchain-file "$CERT_DIR/fullchain.pem" \
  --reloadcmd "rc-service nginx reload"
acme.sh --install-cronjob

# Self-signed Zertifikat für interne IP
INTERNAL_CERT_DIR="/etc/ssl/nextcloud-internal"
mkdir -p "$INTERNAL_CERT_DIR"
openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
  -keyout "$INTERNAL_CERT_DIR/selfsigned.key" \
  -out "$INTERNAL_CERT_DIR/selfsigned.crt" \
  -subj "/CN=$INTERNAL_IP"

# Nginx extern
cat > /etc/nginx/conf.d/nextcloud.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate     $CERT_DIR/fullchain.pem;
    ssl_certificate_key $CERT_DIR/privkey.pem;

    root /var/www/localhost/htdocs/nextcloud;
    index index.php index.html;

    client_max_body_size 512M;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include fastcgi_params;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

# Nginx intern
cat > /etc/nginx/conf.d/internal.conf <<EOF
server {
    listen 443 ssl;
    server_name $INTERNAL_IP;

    ssl_certificate     $INTERNAL_CERT_DIR/selfsigned.crt;
    ssl_certificate_key $INTERNAL_CERT_DIR/selfsigned.key;

    root /var/www/localhost/htdocs/nextcloud;
    index index.php index.html;

    client_max_body_size 512M;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include fastcgi_params;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

rc-service nginx restart

# Nextcloud Setup
cd /var/www/localhost/htdocs/nextcloud || exit 1
sudo -u nginx php occ maintenance:install \
  --database "mysql" \
  --database-name "$NEXTCLOUD_DB" \
  --database-user "$NEXTCLOUD_USER" \
  --database-pass "$NEXTCLOUD_PASS" \
  --admin-user "$NEXTCLOUD_ADMIN" \
  --admin-pass "$NEXTCLOUD_ADMIN_PASS"

sudo -u nginx php occ config:system:set trusted_domains 1 --value="$DOMAIN"
sudo -u nginx php occ config:system:set trusted_domains 2 --value="$INTERNAL_IP"

# Zugangsdaten speichern
CRED_FILE="/root/nextcloud-credentials.txt"
cat > "$CRED_FILE" <<EOF
Extern: https://${DOMAIN}
Intern: https://${INTERNAL_IP}

Admin-Benutzer: $NEXTCLOUD_ADMIN
Admin-Passwort: $NEXTCLOUD_ADMIN_PASS

Datenbank: $NEXTCLOUD_DB
DB-Benutzer: $NEXTCLOUD_USER
DB-Passwort: $NEXTCLOUD_PASS
EOF

chmod 600 "$CRED_FILE"

# Sicherheit
cat > /etc/iptables/rules-save <<EOF
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A INPUT -p tcp --dport 22 -j ACCEPT
-A INPUT -p tcp --dport 80 -j ACCEPT
-A INPUT -p tcp --dport 443 -j ACCEPT
-A INPUT -p icmp -j ACCEPT
COMMIT
EOF

iptables-restore < /etc/iptables/rules-save
rc-service denyhosts start

echo -e "${GREEN}SSH-Root-Zugriff deaktivieren? (j/N): ${NC}"
read -r disable_ssh
if [ "$disable_ssh" = "j" ]; then
  sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
  sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
  rc-service sshd reload
  echo -e "${GREEN}SSH-Zugang für root deaktiviert.${NC}"
fi

# Cronjob für Updates
echo "0 3 * * * apk update && apk upgrade -y" >> /etc/crontabs/root
echo "0 4 * * * cd /var/www/localhost/htdocs/nextcloud && sudo -u nginx php occ upgrade" >> /etc/crontabs/root

echo -e "\n${GREEN}✅ Fertig! Nextcloud wurde mit HTTPS für Domain & interne IP installiert.${NC}"
echo ""
echo -e "🌐 Extern:  ${GREEN}https://$DOMAIN${NC}"
echo -e "🏠 Intern:  ${GREEN}https://$INTERNAL_IP${NC}"
echo -e "🔐 Zugangsdaten: ${GREEN}$CRED_FILE${NC}"
echo "--------------------------------------------------"
cat "$CRED_FILE"
echo "--------------------------------------------------"
