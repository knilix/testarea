#!/bin/bash
# Maintainer: @knilix
# Angepasst für Alpine Linux
# Version: 1.0-alpine
# Hinweis: Für Alpine Linux (x64), root erforderlich
# Script nur einmalig ausführen - - Abfrage einer vorhandenen Nextcloud-Datenbank noch nicht implementiert!
# Mit MariaDB und Redis Cache
# -----------------------------------------------------------------------------
# 1. Fehler-Handling und Farben
set -e
trap 'echo "Ein Fehler ist aufgetreten. Installation wurde abgebrochen."' ERR
GREEN='\033[0;32m'; BLUE='\033[0;34m'; RED='\033[0;31m'; GRAY='\033[0;37m'; NC='\033[0m'

# 2. Root-Check
[[ "<span class="math-inline">EUID" \-ne 0 \]\] && \{ echo \-e "</span>{RED}Bitte führen Sie das Script als root aus.<span class="math-inline">\{NC\}"; exit 1; \}
\# 3\. OS\-Check
if \! grep \-q "Alpine Linux" /etc/os\-release; then
echo \-e "</span>{RED}Dieses Script ist für Alpine Linux gedacht. Erkannte System: <span class="math-inline">\(grep \-oP '\(?<\=^ID\=\)\.\+' /etc/os\-release\)</span>{NC}"
    exit 1
fi
OS_VERSION=<span class="math-inline">\(grep \-oP '\(?<\=VERSION\_ID\="\)\.\*?\(?\="\)' /etc/os\-release\)
echo \-e "</span>{BLUE}Alpine Linux <span class="math-inline">OS\_VERSION erkannt\. Fahre fort\.\.\.</span>{NC}"

# 4. Konfigurationsparameter
MYSQL_ROOT_PASSWORD=<span class="math-inline">\(openssl rand \-base64 32\)
NEXTCLOUD\_DB\_PASSWORD\=</span>(openssl rand -base64 32)
NEXTCLOUD_DB_NAME="nextcloud"
NEXTCLOUD_DB_USER="nextcloud"
NEXTCLOUD_ADMIN_USER="admin"
NEXTCLOUD_ADMIN_PASSWORD=<span class="math-inline">\(openssl rand \-base64 24\)
NEXTCLOUD\_DATA\_DIR\="/var/www/nextcloud/data"
CREDENTIALS\_FILE\="/root/\.nextcloud\_credentials"
SERVER\_IP\=</span>(hostname -I | awk '{print <span class="math-inline">1\}'\)
DOMAIN\_NAME\=</span>(hostname -f)
[[ "$DOMAIN_NAME" = "localhost" || -z "$DOMAIN_NAME" ]] && DOMAIN_NAME=<span class="math-inline">SERVER\_IP
clear
\# 5\. Installationsparameter anzeigen
echo \-e "</span>{BLUE}=== Nextcloud Installationsscript für Alpine Linux ====<span class="math-inline">\{NC\}"
echo \-e "</span>{BLUE}Dieses Script installiert Nextcloud mit MariaDB und Redis.<span class="math-inline">\{NC\}\\n"
echo \-e "</span>{GREEN}Installationsparameter:${NC}"
echo -e "IP-Adresse: ${GREEN}<span class="math-inline">SERVER\_IP</span>{NC}"
echo -e "Admin Benutzer: ${GREEN}<span class="math-inline">NEXTCLOUD\_ADMIN\_USER</span>{NC}"
echo -e "Datenbank: ${GREEN}<span class="math-inline">NEXTCLOUD\_DB\_NAME</span>{NC}\n"

# 6. Bestätigung
read -p "Installation starten? (j/n): " CONFIRM
[[ $CONFIRM != "j" && <span class="math-inline">CONFIRM \!\= "J" \]\] && \{ echo "Installation abgebrochen\."; exit 0; \}
\# 7\. System aktualisieren
echo \-e "</span>{BLUE}[1/10] System wird aktualisiert...<span class="math-inline">\{NC\}"
apk update && apk upgrade \-y
\# 8\. Benötigte Pakete installieren
echo -e "${BLUE}[2/10] Benötigte Pakete werden installiert...${NC}"
apk add --no-cache apache2 mariadb mariadb-client redis \
    php php-fpm php-mysqli php-pdo_mysql php-json php-intl php-imagick \
    php-curl php-mbstring php-zip php-xml php-gd php-bz2 php-redis \
    php-apcu php-gmp libmagic
\# 9\. Apache für PHP konfigurieren
echo \-e "</span>{BLUE}[3/10] Apache für PHP konfigurieren...<span class="math-inline">\{NC\}"
sed \-i 's/\#LoadModule rewrite\_module/LoadModule rewrite\_module/' /etc/apache2/httpd\.conf
sed \-i 's/\#LoadModule headers\_module/LoadModule headers\_module/' /etc/apache2/httpd\.conf
sed \-i 's/\#LoadModule env\_module/LoadModule env\_module/' /etc/apache2/httpd\.conf
sed \-i 's/\#LoadModule dir\_module/LoadModule dir\_module/' /etc/apache2/httpd\.conf
sed \-i 's/\#LoadModule mime\_module/LoadModule mime\_module/' /etc/apache2/httpd\.conf
sed \-i 's/\#LoadModule ssl\_module/LoadModule ssl\_module/' /etc/apache2/httpd\.conf
sed \-i 's/\#Include conf\\/extra\\/httpd\-ssl\.conf/\#Include conf\\/extra\\/httpd\-ssl\.conf/' /etc/apache2/httpd\.conf
sed \-i 's/\#LoadModule proxy\_module/LoadModule proxy\_module/' /etc/apache2/httpd\.conf
sed \-i 's/\#LoadModule proxy\_fcgi\_module/LoadModule proxy\_fcgi\_module/' /etc/apache2/httpd\.conf
sed \-i 's/Listen 80/Listen 80\\nListen 443/' /etc/apache2/httpd\.conf
\# PHP\-FPM Konfiguration
echo "
<FilesMatch \\\.php</span>>
    SetHandler application/x-httpd-php
</FilesMatch>
" > /etc/apache2/conf.d/php.conf

rc-update add apache2 default
rc-service apache2 restart

# 10. MariaDB konfigurieren
echo -e "<span class="math-inline">\{BLUE\}\[4/10\] MariaDB wird konfiguriert\.\.\.</span>{NC}"
rc-update add mariadb default
rc-service mariadb start

mysql -e "SET PASSWORD FOR root@localhost = PASSWORD('${MYSQL_ROOT_PASSWORD}');"
mysql -e "DELETE FROM mysql.user WHERE User='';"
mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -e "DROP DATABASE IF EXISTS test;"
mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"

mysql -e "CREATE DATABASE IF NOT EXISTS <span class="math-inline">\{NEXTCLOUD\_DB\_NAME\} CHARACTER SET utf8mb4 COLLATE utf8mb4\_general\_ci;"
USER\_EXISTS\=</span>(mysql -e "SELECT User FROM mysql.user WHERE User='<span class="math-inline">\{NEXTCLOUD\_DB\_USER\}';" \| grep \-o "</span>{NEXTCLOUD_DB_USER}" || echo "")
[[ -z "<span class="math-inline">USER\_EXISTS" \]\] && mysql \-e "CREATE USER '</span>{NEXTCLOUD_DB_USER}'@'localhost' IDENTIFIED BY '${NEXTCLOUD_DB_PASSWORD}';"
mysql -e "GRANT ALL PRIVILEGES ON <span class="math-inline">\{NEXTCLOUD\_DB\_NAME\}\.\* TO '</span>{NEXTCLOUD_DB_USER}'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# MariaDB-Konfiguration für Nextcloud
cat > /etc/mysql/my.cnf.d/99-nextcloud.cnf << EOF
[mysqld]
transaction-isolation = READ-COMMITTED
binlog_format = ROW
innodb_large_prefix=on
innodb_file_format=barracuda
innodb_file_per_table=1
max_allowed_packet = 128M
EOF

# MariaDB neustarten
rc-service mariadb restart

# 11. Redis konfigurieren
echo -e "<span class="math-inline">\{BLUE\}\[5/10\] Redis wird konfiguriert\.\.\.</span>{NC}"
rc-update add redis default
rc-service redis start

# Redis konfigurieren
sed -i "s/port 6379/port 0/" /etc/redis/redis.conf
sed -i "s/# unixsocket/unixsocket/" /etc/redis/redis.conf
sed -i "s/# unixsocketperm 700/unixsocketperm 770/" /etc/redis/redis.conf
sed -i "s/^unixsocketperm 700/unixsocketperm 770/" /etc/redis/redis.conf 2>/dev/null || true
adduser -G redis www-data

# Redis neustarten
rc-service redis restart

# 12. PHP für Nextcloud optimieren
echo -e "<span class="math-inline">\{BLUE\}\[6/10\] PHP\-Konfiguration für Nextcloud optimieren\.\.\.</span>{NC}"
for sapi in fpm cli apache2; do
    if [ "<span class="math-inline">sapi" \= "fpm" \]; then
PHP\_INI\_DIR\="/etc/php</span>{PHP_VERSION}/fpm"
    elif [ "<span class="math-inline">sapi" \= "cli" \]; then
PHP\_INI\_DIR\="/etc/php</span>{PHP_VERSION}/cli"
    elif [ "<span class="math-inline">sapi" \= "apache2" \]; then
PHP\_INI\_DIR\="/etc/php</span>{PHP_VERSION}/apache2"
    else
        continue
    fi

    if [ -d "<span class="math-inline">PHP\_INI\_DIR/conf\.d" \]; then
echo \-e "</span>{BLUE}→ PHP-SAPI: <span class="math-inline">sapi wird konfiguriert\.\.\.</span>{NC}"
        cat > "<span class="math-inline">PHP\_INI\_DIR/conf\.d/99\-nextcloud\.ini" << EOF
memory\_limit \= 512M
upload\_max\_filesize \= 500M
post\_max\_size \= 500M
max\_execution\_time \= 300
date\.timezone \= Europe/Berlin
opcache\.enable\=1
opcache\.interned\_strings\_buffer\=32
opcache\.max\_accelerated\_files\=10000
opcache\.memory\_consumption\=128
opcache\.save\_comments\=1
opcache\.revalidate\_freq\=1
EOF
fi
done
\# PHP\-FPM neustarten
rc\-service php\-fpm82 restart
\# 13\. Apache Virtual Host konfigurieren
echo \-e "</span>{BLUE}[7/10] Apache Virtual Host für Nextcloud wird konfiguriert...<span class="math-inline">\{NC\}"
mkdir \-p /etc/ssl/nextcloud/
openssl req \-x509 \-nodes \-days 365 \-newkey rsa\:2048 \\
\-keyout /etc/ssl/nextcloud/nextcloud\.key \\
\-out /etc/ssl/nextcloud/nextcloud\.crt \\
\-subj "/CN\=</span>{DOMAIN_NAME}/O=Nextcloud/C=DE"

cat > /etc/apache2/conf.d/nextcloud.conf << EOF
<VirtualHost *:80>
    ServerName <span class="math-inline">\{DOMAIN\_NAME\}
Redirect permanent / https\://</span>{DOMAIN_NAME}/
</VirtualHost>

<VirtualHost *:443>
    ServerName <span class="math-inline">\{DOMAIN\_NAME\}
DocumentRoot /var/www/nextcloud
SSLEngine on
SSLCertificateFile /etc/ssl/nextcloud/nextcloud\.crt
SSLCertificateKeyFile /etc/ssl/nextcloud/nextcloud\.key
<IfModule mod\_headers\.c\>
Header always set Strict\-Transport\-Security "max\-age\=15552000; includeSubDomains"
</IfModule\>
<Directory /var/www/nextcloud\>
Options \+FollowSymlinks
AllowOverride All
Require all granted
<IfModule mod\_dav\.c\>
Dav off
</IfModule\>
SetEnv HOME /var/www/nextcloud
SetEnv HTTP\_HOME /var/www/nextcloud
</Directory\>
ErrorLog /var/log/apache2/nextcloud\_error\.log
CustomLog /var/log/apache2/nextcloud\_access\.log combined
</VirtualHost\>
EOF
rc\-service apache2 reload
\# 14\. Nextcloud installieren
echo \-e "</span>{BLUE}[8/10] Nextcloud wird heruntergeladen und installiert...<span class="math-inline">\{NC\}"
wget \-q https\://download\.nextcloud\.com/server/releases/latest\.zip \-O /tmp/nextcloud\.zip
unzip \-q /tmp/nextcloud\.zip \-d /var/www/
rm /tmp/nextcloud\.zip
mkdir \-p "</span>{NEXTCLOUD_DATA_DIR}"
chown -R www-data:www-data /var/www/nextcloud/ "<span class="math-inline">\{NEXTCLOUD\_DATA\_DIR\}"
\# 15\. Initialisieren
echo \-e "</span>{BLUE}[9/10] Nextcloud wird initialisiert...<span class="math-inline">\{NC\}"
cd /var/www/nextcloud
sudo \-u www\-data php occ maintenance\:install \\
\-\-database "mysql" \\
\-\-database\-name "</span>{NEXTCLOUD_DB_NAME}" \
    --database-user "<span class="math-inline">\{NEXTCLOUD\_DB\_USER\}" \\
\-\-database\-pass "</span>{NEXTCLOUD_DB_PASSWORD}" \
    --admin-user "<span class="math-inline">\{NEXTCLOUD\_ADMIN\_USER\}" \\
\-\-admin\-pass "</span>{NEXTCLOUD_ADMIN_PASSWORD}" \
    --data-dir "<span class="math-inline">\{NEXTCLOUD\_DATA\_DIR\}"
\# Nextcloud Konfiguration
sudo \-u www\-data php occ config\:system\:set trusted\_domains 0 \-\-value\="</span>{DOMAIN_NAME}" \
&& sudo -u www-data php occ config:system:set trusted_domains 1 --value="<span class="math-inline">\{SERVER\_IP\}" \\
&& sudo \-u www\-data php occ config\:system\:set memcache\.local \-\-value\='\\OC\\Memcache\\APCu' \\
&& sudo \-u www\-data php occ config\:system\:set memcache\.locking \-\-value\='\\OC\\Memcache\\Redis' \\
&& sudo \-u www\-data php occ config\:system\:set redis host \-\-value\='/run/redis/redis\.sock' \\
&& sudo \-u www\-data php occ config\:system\:set redis port \-\-value\=0 \\
&& sudo \-u www\-data php occ config\:system\:set redis timeout \-\-value\=0\.0 \\
&& sudo \-u www\-data php occ config\:system\:set trusted\_proxies 0 \-\-value\="127\.0\.0\.1" \\
&& sudo \-u www\-data php occ config\:system\:set overwriteprotocol \-\-value\="https" \\
&& sudo \-u www\-data php occ config\:system\:set htaccess\.RewriteBase \-\-value\="/" \\
&& sudo \-u www\-data php occ maintenance\:update\:htaccess
\# 16\. Cronjob
echo "\*/5 \* \* \* \* www\-data php \-f /var/www/nextcloud/cron\.php" \> /etc/crontabs/www\-data
crontab /etc/crontabs/www\-data
\# 17\. Zugangsdaten speichern
cat \> "</span>{CREDENTIALS_FILE}" << EOF
NEXTCLOUD_URL_DOMAIN=https://<span class="math-inline">\{DOMAIN\_NAME\}
NEXTCLOUD\_URL\_IP\=https\://</span>{SERVER_IP}
NEXTCLOUD_ADMIN_USER=<span class="math-inline">\{NEXTCLOUD\_ADMIN\_USER\}
NEXTCLOUD\_ADMIN\_PASSWORD\=</span>{NEXTCLOUD_ADMIN_PASSWORD}
MYSQL_ROOT_PASSWORD=<span class="math-inline">\{MYSQL\_ROOT\_PASSWORD\}
NEXTCLOUD\_DB\_NAME\=</span>{NEXTCLOUD_DB_NAME}
NEXTCLOUD_DB_USER=<span class="math-inline">\{NEXTCLOUD\_DB\_USER\}
NEXTCLOUD\_DB\_PASSWORD\=</span>{NEXTCLOUD_DB_PASSWORD}
INSTALLATION_DATE=<span class="math-inline">\(date \+"%Y\-%m\-%d %H\:%M\:%S"\)
EOF
chmod 600 "</span>{CREDENTIALS_FILE}"

# 18. Anmeldedaten anzeigen Befehl
cat > /usr/local/bin/nextcloud-credentials << 'EOF'
#!/bin/bash
[[ "$EUID" -ne 0 ]] && { echo "Bitte als root ausführen (sudo nextcloud-credentials)"; exit 1; }

CRED_FILE="/root/.nextcloud_credentials"
[[ ! -f "$CRED_FILE" ]] && { echo "Keine Nextcloud-Anmeldedaten gefunden!"; exit 1; }

source "<span class="math-inline">CRED\_FILE"
GREEN\='\\033\[0;32m'
BLUE\='\\033\[0;34m'
NC\='\\033\[0m'
echo \-e "</span>{BLUE}===== Nextcloud Zugangsdaten =====\n${NC}"
echo -e "Nextcloud URL (Domain): <span class="math-inline">\{GREEN\}</span>{NEXTCLOUD_URL_DOMAIN}${NC}"
echo -e "Nextcloud URL (IP): <span class="math-inline">\{GREEN\}</span>{NEXTCLOUD_URL_IP}${NC}"
echo -e "Admin Benutzer: <span class="math-inline">\{GREEN\}</span>{NEXTCLOUD_ADMIN_USER}${NC}"
echo -e "Admin Passwort: <span class="math-inline">\{GREEN\}</span>{NEXTCLOUD_ADMIN_PASSWORD}<span class="math-inline">\{NC\}"
echo \-e "\\n</span>{BLUE}MariaDB Datenbank:${NC}"
echo -e "Root Passwort: <span class="math-inline">\{GREEN\}</span>{MYSQL_ROOT_PASSWORD}${NC}"
echo -e "Datenbank: <span class="math-inline">\{GREEN\}</span>{NEXTCLOUD_DB_NAME}${NC}"
echo -e "DB Benutzer: <span class="math-inline">\{GREEN\}</span>{NEXTCLOUD_DB_USER}${NC}"
echo -e "DB Passwort: <span class="math-inline">\{GREEN\}</span>{NEXTCLOUD_DB_PASSWORD}${NC}"
echo -e "\nInstalliert am: <span class="math-inline">\{GREEN\}</span>{INSTALLATION_DATE}${NC}"
EOF
chmod +x /usr/local/bin/nextcloud-credentials

# 19. Zusätzliche Nextcloud-Konfiguration
config_file="/var/www/nextcloud/config/config.php"
if [ -f "<span class="math-inline">config\_file" \]; then
tmp\_file\=</span>(mktemp)
    awk '
        /^\);$/ {
            print "  '\''default_phone_region'\'' => '\''DE'\'',";
            print "  '\''enable_previews'\'' => true,";
            print "  '\''enabledPreviewProviders'\'' => array (";
            print
