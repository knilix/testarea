#!/bin/bash
# Maintainer: @knilix
# Version: 1.0
#
# wget -q -P /opt/ https://github.com/knilix/testarea/archive/refs/heads/main.zip && unzip /opt/main.zip -d /opt/scriptfiles && chmod 700 /opt/scriptfiles/testarea-main/test.sh
# cd && cd /opt/scriptfiles/testarea-main && ./test.sh
#
# Hinweis: Für Debian 12, Ubuntu ab 22.04+ (x64) und Alpine Linux, root erforderlich
# Script nur einmalig ausführen - Abfrage einer vorhandenen Nextcloud-Datenbank noch nicht implementiert!
# Mit MariaDB und Redis Cache
# -----------------------------------------------------------------------------
# 1. Fehler-Handling und Farben
set -e
trap 'echo "Ein Fehler ist aufgetreten. Installation wurde abgebrochen."' ERR
GREEN='\033[0;32m'; BLUE='\033[0;34m'; RED='\033[0;31m'; GRAY='\033[0;37m'; NC='\033[0m'

# 2. Root-Check
[[ "<span class="math-inline">EUID" \-ne 0 \]\] && \{ echo \-e "</span>{RED}Bitte führen Sie das Script als root aus.<span class="math-inline">\{NC\}"; exit 1; \}
\# 3\. OS\-Check
if \[\[ \-f /etc/os\-release \]\]; then
OS\_ID\=</span>(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
  OS_VERSION=<span class="math-inline">\(grep '^VERSION\_ID\=' /etc/os\-release \| cut \-d'\=' \-f2 \| tr \-d '"'\)
else
echo \-e "</span>{RED}Konnte Betriebssystem nicht erkennen. Das Script benötigt Debian 12, Ubuntu 22.04+ oder Alpine Linux.${NC}"; exit 1;
fi

# OS-Typ ermitteln und Version prüfen
case "<span class="math-inline">OS\_ID" in
"ubuntu"\)
OS\_TYPE\="Ubuntu"
OS\_VERSION\=</span>(grep -oP '(?<=VERSION_ID=").*?(?=")' /etc/os-release)
    [[ $(echo "<span class="math-inline">OS\_VERSION < 22\.04" \| bc \-l\) \-eq 1 \]\] && \{ echo \-e "</span>{RED}Dieses Script benötigt Ubuntu 22.04 oder neuer. Erkannte Version: <span class="math-inline">OS\_VERSION</span>{NC}"; exit 1; }
    echo -e "${BLUE}Ubuntu <span class="math-inline">OS\_VERSION erkannt\. Fahre fort\.\.\.</span>{NC}"
    echo -e "<span class="math-inline">\{BLUE\}\[1/10\] System wird aktualisiert\.\.\.</span>{NC}"
    apt update && apt upgrade -y
    echo -e "<span class="math-inline">\{BLUE\}\[2/10\] Benötigte Pakete werden installiert\.\.\.</span>{NC}"
    apt install -y bc apache2 mariadb-server redis-server \
      php php-cli php-common php-fpm php-json php-intl php-imagick \
      php-curl php-mbstring php-zip php-xml php-gd php-mysql \
      php-bz2 php-redis php-apcu unzip curl wget ssl-cert pv libmagickcore-6.q16-6-extra \
      php-gmp
    ;;
  "debian")
    OS_TYPE="Debian"
    OS_VERSION=$(grep -oP '(?<=VERSION_ID=").*?(?=")' /etc/os-release)
    [[ $(echo "<span class="math-inline">OS\_VERSION < 12" \| bc \-l\) \-eq 1 \]\] && \{ echo \-e "</span>{RED}Dieses Script benötigt Debian 12 oder neuer. Erkannte Version: <span class="math-inline">OS\_VERSION</span>{NC}"; exit 1; }
    echo -e "${BLUE}Debian <span class="math-inline">OS\_VERSION erkannt\. Fahre fort\.\.\.</span>{NC}"
    echo -e "<span class="math-inline">\{BLUE\}\[1/10\] System wird aktualisiert\.\.\.</span>{NC}"
    apt update && apt upgrade -y
    echo -e "<span class="math-inline">\{BLUE\}\[2/10\] Benötigte Pakete werden installiert\.\.\.</span>{NC}"
    apt install -y bc apache2 mariadb-server redis-server \
      php php-cli php-common php-fpm php-json php-intl php-imagick \
      php-curl php-mbstring php-zip php-xml php-gd php-mysql \
      php-bz2 php-redis php-apcu unzip curl wget ssl-cert pv libmagickcore-6.q16-6-extra \
      php-gmp
    ;;
  "alpine")
    OS_TYPE="Alpine"
    OS_VERSION=<span class="math-inline">\(grep '^VERSION\_ID\=' /etc/os\-release \| cut \-d'\=' \-f2 \| tr \-d '"'\)
echo \-e "</span>{BLUE}Alpine Linux <span class="math-inline">OS\_VERSION erkannt\. Fahre fort\.\.\.</span>{NC}"
    echo -e "<span class="math-inline">\{BLUE\}\[1/10\] System wird aktualisiert\.\.\.</span>{NC}"
    apk update && apk upgrade --available
    echo -e "<span class="math-inline">\{BLUE\}\[2/10\] Benötigte Pakete werden installiert\.\.\.</span>{NC}"
    apk add --no-cache mariadb mariadb-client redis apache2 php php-fpm \
      php-common php-json php-intl php-imagick php-curl \
      php-mbstring php-zip php-xml php-gd php-mysql \
      php-bz2 php-redis php-apcu unzip curl wget openssl \
      pv imagemagick-dev
    ;;
  *)
    echo -e "${RED}Dieses Script unterstützt nur Debian, Ubuntu oder Alpine. Erkanntes System: <span class="math-inline">OS\_ID</span>{NC}"
    exit 1
    ;;
esac

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
echo \-e "</span>{BLUE}=== Nextcloud Installationsscript für <span class="math-inline">OS\_TYPE \=\=\=\=</span>{NC}"
echo -e "<span class="math-inline">\{BLUE\}Dieses Script installiert Nextcloud mit MariaDB und Redis\.</span>{NC}\n"
echo -e "<span class="math-inline">\{GREEN\}Installationsparameter\:</span>{NC}"
echo -e "IP-Adresse: ${GREEN}<span class="math-inline">SERVER\_IP</span>{NC}"
echo -e "Admin Benutzer: ${GREEN}<span class="math-inline">NEXTCLOUD\_ADMIN\_USER</span>{NC}"
echo -e "Datenbank: ${GREEN}<span class="math-inline">NEXTCLOUD\_DB\_NAME</span>{NC}\n"

# 6. Bestätigung
read -p "Installation starten? (j/n): " CONFIRM
[[ $CONFIRM != "j" && <span class="math-inline">CONFIRM \!\= "J" \]\] && \{ echo "Installation abgebrochen\."; exit 0; \}
\# 9\. Apache für PHP konfigurieren
echo \-e "</span>{BLUE}[3/10] Apache für PHP konfigurieren...${NC}"
case "<span class="math-inline">OS\_TYPE" in
"Debian" \| "Ubuntu"\)
a2enmod rewrite headers env dir mime ssl
PHP\_VERSION\=</span>(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
    if [ -f "/etc/apache2/conf-available/php${PHP_VERSION}-fpm.conf" ]; then
      a2enconf "php${PHP_VERSION}-fpm"
    else
      a2enmod proxy_fcgi setenvif
      a2enconf php${PHP_VERSION}-fpm
    fi
    systemctl restart apache2
    ;;
  "Alpine")
    # Alpine spezifische Apache Konfiguration
    sed -i 's/#LoadModule\s*rewrite_module/LoadModule rewrite_module/' /etc/apache2/httpd.conf
    sed -i 's/#LoadModule\s*headers_module/LoadModule headers_module/' /etc/apache2/httpd.conf
    sed -i 's/#LoadModule\s*env_module/LoadModule env_module/' /etc/apache2/httpd.conf
    sed -i 's/#LoadModule\s*dir_module/LoadModule dir_module/' /etc/apache2/httpd.conf
    sed -i 's/#LoadModule\s*mime_module/LoadModule mime_module/' /etc/apache2/httpd.conf
    sed -i 's/#LoadModule\s*ssl_module/LoadModule ssl_module/' /etc/apache2/httpd.conf

    echo "Include conf/extra/httpd-ssl.conf" >> /etc/apache2/httpd.conf
    sed -i 's/#Include\s*conf\/extra\/httpd-ssl.conf/Include conf\/extra\/httpd-ssl.conf/' /etc/apache2/httpd.conf

    mkdir -p /etc/apache2/ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout /etc/apache2/ssl/apache.key \
      -out /etc/apache2/ssl/apache.crt \
      -subj "/CN=${DOMAIN_NAME}/O=Nextcloud/C=DE"

    cat > /etc/apache2/conf/httpd-ssl.conf <<EOF
Listen 443
<VirtualHost *:443>
  ServerName <span class="math-inline">\{DOMAIN\_NAME\}
DocumentRoot /var/www/nextcloud
SSLEngine on
SSLCertificateFile /etc/apache2/ssl/apache\.crt
SSLCertificateKeyFile /etc/apache2/ssl/apache\.key
<IfModule <1\>mod\_headers\.c\>
Header always set Strict\-Transport\-Security "max\-age\=15552000; includeSubDomains"
</IfModule\>
<Directory /var/www/nextcloud\>
<2\>Options \+FollowSymlinks
AllowOverride All</1\>
Require all granted
<IfModule mod\_dav\.c\>
Dav off
</IfModule\>
SetEnv HOME /var/www/nextcloud
SetEnv HTTP\_HOME /var/www/nextcloud
</Directory\>
ErrorLog</2\> /var/log/apache2/error\_log
CustomLog /var/log/apache2/access\_log combined
</VirtualHost\>
EOF
sed \-i 's/;cgi\.force\_redirect \= 1/cgi\.force\_redirect \= 0/' /etc/php8/php\.ini
sed \-i 's/;fastcgi\.impersonate \= 1/fastcgi\.impersonate \= 0/' /etc/php8/php\.ini
sed \-i 's/;fastcgi\.fastcgi\_finish\_request\_timeout \= 0/fastcgi\.fastcgi\_finish\_request\_timeout \= 0/' /etc/php8/php\.ini
cat \> /etc/apache2/conf\.d/php8\-fpm\.conf <<EOF
<FilesMatch \\\.php</span>>
  SetHandler "proxy:fcgi://127.0.0.1:9000"
</FilesMatch>
EOF

    apachectl restart
    ;;
esac

# 10. MariaDB konfigurieren
echo -e "<span class="math-inline">\{BLUE\}\[4/10\] MariaDB wird konfiguriert\.\.\.</span>{NC}"
case "$OS_TYPE" in
  "Debian" | "Ubuntu")
    # Systemspezifische MariaDB-Konfiguration
    if [ "<span class="math-inline">OS\_TYPE" \= "Debian" \]; <3\>then
mysql \-e "SET PASSWORD FOR root@localhost \= PASSWORD\('</span>{MYSQL_ROOT_PASSWORD}');"
      mysql -e "DELETE FROM mysql.user WHERE User='';"
      mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
      mysql -e "DROP DATABASE IF EXISTS test;"
      mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"

      mysql -e "CREATE DATABASE IF NOT EXISTS <span class="math-inline">\{NEXTCLOUD\_DB\_NAME\} CHARACTER SET utf8mb4 COLLATE utf8mb4\_general\_ci;"
USER\_EXISTS\=</span>(mysql -e "SELECT User FROM mysql.user WHERE User='<span class="math-inline">\{NEXTCLOUD\_DB\_USER\}';" \| grep \-o "</span>{NEXTCLOUD_DB_USER}" || echo "")
      [[ -z "<span class="math-inline">USER\_EXISTS" \]\] && mysql \-e "CREATE USER '</span>{NEXTCLOUD_DB_USER}'@'localhost' IDENTIFIED BY '${NEXTCLOUD_DB_PASSWORD}';"
      mysql -e "GRANT ALL PRIVILEGES ON <span class="math-inline">\{NEXTCLOUD\_DB\_NAME\}\.\* TO '</span>{NEXTCLOUD_DB_USER}'@'localhost';"
      mysql -e "FLUSH PRIVILEGES;"
    else
      # Ubuntu-spezifische Konfiguration
      if mysql -e "SELECT 1;" &>/dev/null; then
        mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '<span class="math-inline">\{MYSQL\_ROOT\_PASSWORD\}';"
else
mysqladmin \-u root password "</span>{MYSQL_ROOT_PASSWORD}" || true
      fi

      mysql -u root -p"<span class="math-inline">\{MYSQL\_ROOT\_PASSWORD\}" \-e "DELETE FROM mysql\.user WHERE User\='';"
mysql \-u root \-p"</span>{MYSQL_ROOT_PASSWORD}" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
      mysql -u root -p"<span class="math-inline">\{MYSQL\_ROOT\_PASSWORD\}"</6\> \-e "DROP DATABASE IF EXISTS test;"
<6\>mysql \-u root \-p"</span>{MYSQL_ROOT_PASSWORD}" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
      mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS <span class="math-inline">\{NEXTCLOUD\_DB\_NAME\} CHARACTER SET utf8mb4 COLLATE utf8mb4\_general\_ci;"
USER\_EXISTS\=</span>(mysql -u root -p"<span class="math-inline">\{MYSQL\_ROOT\_PASSWORD\}" \-e "SELECT User FROM mysql\.user WHERE User\='</span>{NEXTCLOUD_DB_USER}';" | grep -o "${NEXTCLOUD_DB_USER}" || echo "")
      [[ -z "<span class="math-inline">USER\_EXISTS" \]\] && mysql \-u root \-p"</span>{MYSQL_ROOT_PASSWORD}" -e "CREATE USER '<span class="math-inline">\{NEXTCLOUD\_DB\_USER\}'@'localhost' IDENTIFIED BY '</span>{NEXTCLOUD_DB_PASSWORD}';"
      mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON <span class="math-inline">\{NEXTCLOUD\_DB\_NAME\}\.\* TO '</span>{NEXTCLOUD_DB_USER}'@'localhost';"
      mysql -u root -p"<span class="math-inline">\{MYSQL\_ROOT\_PASSWORD\}" \-e "FLUSH PRIVILEGES;"
fi
;;
"Alpine"\)
\# Alpine spezifische MariaDB Konfiguration
<3\>mysql \-e "SET PASSWORD FOR root@localhost \= PASSWORD\('</span>{MYSQL_ROOT_PASSWORD}');"
    mysql -e "DELETE FROM mysql.user WHERE User='';"
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    mysql -e "DROP DATABASE IF EXISTS test;"
    mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"

    mysql -e "CREATE DATABASE IF NOT EXISTS <span class="math-inline">\{NEXTCLOUD\_DB\_NAME\} CHARACTER SET utf8mb4 COLLATE utf8mb4\_general\_ci;"
USER\_EXISTS\=</span>(mysql -e "SELECT User FROM mysql.user WHERE User='<span class="math-inline">\{NEXTCLOUD\_DB\_USER\}';" \| grep \-o "</span>{NEXTCLOUD_DB_USER}" || echo "")
    [[ -z "<span class="math-inline">USER\_EXISTS" \]\] && mysql \-e "CREATE USER '</span>{NEXTCLOUD_DB_USER}'@'localhost' IDENTIFIED BY '${NEXTCLOUD_DB_PASSWORD}';"
    mysql -e "GRANT ALL PRIVILEGES ON <span class="math-inline">\{NEXTCLOUD\_DB\_NAME\}\.\* TO '</span>{NEXTCLOUD_DB_USER}'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    ;;
esac

# MariaDB-Konfigurationspfad
MARIADB_CONF_DIR="/etc/mysql/mariadb.conf.d"
[[ ! -d "<span class="math-inline">MARIADB\_CONF\_DIR" \]\] && \{
\[\[ \-d "/etc/mysql/conf\.d" \]\] && MARIADB\_CONF\_DIR\="/etc/mysql/conf\.d" \|\| mkdir \-p "/etc/mysql/mariadb\.conf\.d";
\}
\# MariaDB\-Konfiguration für Nextcloud
cat \> "</span>{MARIADB_CONF_DIR}/99-nextcloud.cnf" << EOF
[mysqld]
transaction_isolation = READ-COMMITTED
binlog_format = ROW
innodb_large_prefix=on
innodb_file_format=barracuda
innodb_file_per_table=1
max_allowed_packet = 128M
EOF









#!/bin/bash
# Maintainer: @knilix
# Version: 1.0
#
# wget -q -P /opt/ https://github.com/knilix/testarea/archive/refs/heads/main.zip && unzip /opt/main.zip -d /opt/scriptfiles && chmod 700 /opt/scriptfiles/testarea-main/test.sh
# cd && cd /opt/scriptfiles/testarea-main && ./test.sh
#
# Hinweis: Für Debian 12, Ubuntu ab 22.04+ (x64) und Alpine Linux, root erforderlich
# Script nur einmalig ausführen - Abfrage einer vorhandenen Nextcloud-Datenbank noch nicht implementiert!
# Mit MariaDB und Redis Cache
# -----------------------------------------------------------------------------
# 1. Fehler-Handling und Farben
set -e
trap 'echo "Ein Fehler ist aufgetreten. Installation wurde abgebrochen."' ERR
GREEN='\033[0;32m'; BLUE='\033[0;34m'; RED='\033[0;31m'; GRAY='\033[0;37m'; NC='\033[0m'

# 2. Root-Check
[[ "<span class="math-inline">EUID" \-ne 0 \]\] && \{ echo \-e "</span>{RED}Bitte führen Sie das Script als root aus.<span class="math-inline">\{NC\}"; exit 1; \}
\# 3\. OS\-Check
if \[\[ \-f /etc/os\-release \]\]; then
OS\_ID\=</span>(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
  OS_VERSION=<span class="math-inline">\(grep '^VERSION\_ID\=' /etc/os\-release \| cut \-d'\=' \-f2 \| tr \-d '"'\)
else
echo \-e "</span>{RED}Konnte Betriebssystem nicht erkennen. Das Script benötigt Debian 12, Ubuntu 22.04+ oder Alpine Linux.${NC}"; exit 1;
fi

# OS-Typ ermitteln und Version prüfen
case "<span class="math-inline">OS\_ID" in
"ubuntu"\)
OS\_TYPE\="Ubuntu"
OS\_VERSION\=</span>(grep -oP '(?<=VERSION_ID=").*?(?=")' /etc/os-release)
    [[ $(echo "<span class="math-inline">OS\_VERSION < 22\.04" \| bc \-l\) \-eq 1 \]\] && \{ echo \-e "</span>{RED}Dieses Script benötigt Ubuntu 22.04 oder neuer. Erkannte Version: <span class="math-inline">OS\_VERSION</span>{NC}"; exit 1; }
    echo -e "${BLUE}Ubuntu <span class="math-inline">OS\_VERSION erkannt\. Fahre fort\.\.\.</span>{NC}"
    echo -e "<span class="math-inline">\{BLUE\}\[1/10\] System wird aktualisiert\.\.\.</span>{NC}"
    apt update && apt upgrade -y
    echo -e "<span class="math-inline">\{BLUE\}\[2/10\] Benötigte Pakete werden installiert\.\.\.</span>{NC}"
    apt install -y bc apache2 mariadb-server redis-server \
      php php-cli php-common php-fpm php-json php-intl php-imagick \
      php-curl php-mbstring php-zip php-xml php-gd php-mysql \
      php-bz2 php-redis php-apcu unzip curl wget ssl-cert pv libmagickcore-6.q16-6-extra \
      php-gmp
    ;;
  "debian")
    OS_TYPE="Debian"
    OS_VERSION=$(grep -oP '(?<=VERSION_ID=").*?(?=")' /etc/os-release)
    [[ $(echo "<span class="math-inline">OS\_VERSION < 12" \| bc \-l\) \-eq 1 \]\] && \{ echo \-e "</span>{RED}Dieses Script benötigt Debian 12 oder neuer. Erkannte Version: <span class="math-inline">OS\_VERSION</span>{NC}"; exit 1; }
    echo -e "${BLUE}Debian <span class="math-inline">OS\_VERSION erkannt\. Fahre fort\.\.\.</span>{NC}"
    echo -e "<span class="math-inline">\{BLUE\}\[1/10\] System wird aktualisiert\.\.\.</span>{NC}"
    apt update && apt upgrade -y
    echo -e "<span class="math-inline">\{BLUE\}\[2/10\] Benötigte Pakete werden installiert\.\.\.</span>{NC}"
    apt install -y bc apache2 mariadb-server redis-server \
      php php-cli php-common php-fpm php-json php-intl php-imagick \
      php-curl php-mbstring php-zip php-xml php-gd php-mysql \
      php-bz2 php-redis php-apcu unzip curl wget ssl-cert pv libmagickcore-6.q16-6-extra \
      php-gmp
    ;;
  "alpine")
    OS_TYPE="Alpine"
    OS_VERSION=<span class="math-inline">\(grep '^VERSION\_ID\=' /etc/os\-release \| cut \-d'\=' \-f2 \| tr \-d '"'\)
echo \-e "</span>{BLUE}Alpine Linux <span class="math-inline">OS\_VERSION erkannt\. Fahre fort\.\.\.</span>{NC}"
    echo -e "<span class="math-inline">\{BLUE\}\[1/10\] System wird aktualisiert\.\.\.</span>{NC}"
    apk update && apk upgrade --available
    echo -e "<span class="math-inline">\{BLUE\}\[2/10\] Benötigte Pakete werden installiert\.\.\.</span>{NC}"
    apk add --no-cache mariadb mariadb-client redis apache2 php php-fpm \
      php-common php-json php-intl php-imagick php-curl \
      php-mbstring php-zip php-xml php-gd php-mysql \
      php-bz2 php-redis php-apcu unzip curl wget openssl \
      pv imagemagick-dev
    ;;
  *)
    echo -e "${RED}Dieses Script unterstützt nur Debian, Ubuntu oder Alpine. Erkanntes System: <span class="math-inline">OS\_ID</span>{NC}"
    exit 1
    ;;
esac

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
echo \-e "</span>{BLUE}=== Nextcloud Installationsscript für <span class="math-inline">OS\_TYPE \=\=\=\=</span>{NC}"
echo -e "<span class="math-inline">\{BLUE\}Dieses Script installiert Nextcloud mit MariaDB und Redis\.</span>{NC}\n"
echo -e "<span class="math-inline">\{GREEN\}Installationsparameter\:</span>{NC}"
echo -e "IP-Adresse: ${GREEN}<span class="math-inline">SERVER\_IP</span>{NC}"
echo -e "Admin Benutzer: ${GREEN}<span class="math-inline">NEXTCLOUD\_ADMIN\_USER</span>{NC}"
echo -e "Datenbank: ${GREEN}<span class="math-inline">NEXTCLOUD\_DB\_NAME</span>{NC}\n"

# 6. Bestätigung
read -p "Installation starten? (j/n): " CONFIRM
[[ $CONFIRM != "j" && <span class="math-inline">CONFIRM \!\= "J" \]\] && \{ echo "Installation abgebrochen\."; exit 0; \}
\# 9\. Apache für PHP konfigurieren
echo \-e "</span>{BLUE}[3/10] Apache für PHP konfigurieren...${NC}"
case "<span class="math-inline">OS\_TYPE" in
"Debian" \| "Ubuntu"\)
a2enmod rewrite headers env dir mime ssl
PHP\_VERSION\=</span>(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
    if [ -f "/etc/apache2/conf-available/php${PHP_VERSION}-fpm.conf" ]; then
      a2enconf "php${PHP_VERSION}-fpm"
    else
      a2enmod proxy_fcgi setenvif
      a2enconf php${PHP_VERSION}-fpm
    fi
    systemctl restart apache2
    ;;
  "Alpine")
    # Alpine spezifische Apache Konfiguration
    sed -i 's/#LoadModule\s*rewrite_module/LoadModule rewrite_module/' /etc/apache2/httpd.conf
    sed -i 's/#LoadModule\s*headers_module/LoadModule headers_module/' /etc/apache2/httpd.conf
    sed -i 's/#LoadModule\s*env_module/LoadModule env_module/' /etc/apache2/httpd.conf
    sed -i 's/#LoadModule\s*dir_module/LoadModule dir_module/' /etc/apache2/httpd.conf
    sed -i 's/#LoadModule\s*mime_module/LoadModule mime_module/' /etc/apache2/httpd.conf
    sed -i 's/#LoadModule\s*ssl_module/LoadModule ssl_module/' /etc/apache2/httpd.conf

    echo "Include conf/extra/httpd-ssl.conf" >> /etc/apache2/httpd.conf
    sed -i 's/#Include\s*conf\/extra\/httpd-ssl.conf/Include conf\/extra\/httpd-ssl.conf/' /etc/apache2/httpd.conf

    mkdir -p /etc/apache2/ssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout /etc/apache2/ssl/apache.key \
      -out /etc/apache2/ssl/apache.crt \
      -subj "/CN=${DOMAIN_NAME}/O=Nextcloud/C=DE"

    cat > /etc/apache2/conf/httpd-ssl.conf <<EOF
Listen 443
<VirtualHost *:443>
  ServerName <span class="math-inline">\{DOMAIN\_NAME\}
DocumentRoot /var/www/nextcloud
SSLEngine on
SSLCertificateFile /etc/apache2/ssl/apache\.crt
SSLCertificateKeyFile /etc/apache2/ssl/apache\.key
<IfModule <1\>mod\_headers\.c\>
Header always set Strict\-Transport\-Security "max\-age\=15552000; includeSubDomains"
</IfModule\>
<Directory /var/www/nextcloud\>
<2\>Options \+FollowSymlinks
AllowOverride All</1\>
Require all granted
<IfModule mod\_dav\.c\>
Dav off
</IfModule\>
SetEnv HOME /var/www/nextcloud
SetEnv HTTP\_HOME /var/www/nextcloud
</Directory\>
ErrorLog</2\> /var/log/apache2/error\_log
CustomLog /var/log/apache2/access\_log combined
</VirtualHost\>
EOF
sed \-i 's/;cgi\.force\_redirect \= 1/cgi\.force\_redirect \= 0/' /etc/php8/php\.ini
sed \-i 's/;fastcgi\.impersonate \= 1/fastcgi\.impersonate \= 0/' /etc/php8/php\.ini
sed \-i 's/;fastcgi\.fastcgi\_finish\_request\_timeout \= 0/fastcgi\.fastcgi\_finish\_request\_timeout \= 0/' /etc/php8/php\.ini
cat \> /etc/apache2/conf\.d/php8\-fpm\.conf <<EOF
<FilesMatch \\\.php</span>>
  SetHandler "proxy:fcgi://127.0.0.1:9000"
</FilesMatch>
EOF

    apachectl restart
    ;;
esac

# 10. MariaDB konfigurieren
echo -e "<span class="math-inline">\{BLUE\}\[4/10\] MariaDB wird konfiguriert\.\.\.</span>{NC}"
case "$OS_TYPE" in
  "Debian" | "Ubuntu")
    # Systemspezifische MariaDB-Konfiguration
    if [ "<span class="math-inline">OS\_TYPE" \= "Debian" \]; <3\>then
mysql \-e "SET PASSWORD FOR root@localhost \= PASSWORD\('</span>{MYSQL_ROOT_PASSWORD}');"
      mysql -e "DELETE FROM mysql.user WHERE User='';"
      mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
      mysql -e "DROP DATABASE IF EXISTS test;"
      mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"

      mysql -e "CREATE DATABASE IF NOT EXISTS <span class="math-inline">\{NEXTCLOUD\_DB\_NAME\} CHARACTER SET utf8mb4 COLLATE utf8mb4\_general\_ci;"
USER\_EXISTS\=</span>(mysql -e "SELECT User FROM mysql.user WHERE User='<span class="math-inline">\{NEXTCLOUD\_DB\_USER\}';" \| grep \-o "</span>{NEXTCLOUD_DB_USER}" || echo "")
      [[ -z "<span class="math-inline">USER\_EXISTS" \]\] && mysql \-e "CREATE USER '</span>{NEXTCLOUD_DB_USER}'@'localhost' IDENTIFIED BY '${NEXTCLOUD_DB_PASSWORD}';"
      mysql -e "GRANT ALL PRIVILEGES ON <span class="math-inline">\{NEXTCLOUD\_DB\_NAME\}\.\* TO '</span>{NEXTCLOUD_DB_USER}'@'localhost';"
      mysql -e "FLUSH PRIVILEGES;"
    else
      # Ubuntu-spezifische Konfiguration
      if mysql -e "SELECT 1;" &>/dev/null; then
        mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '<span class="math-inline">\{MYSQL\_ROOT\_PASSWORD\}';"
else
mysqladmin \-u root password "</span>{MYSQL_ROOT_PASSWORD}" || true
      fi

      mysql -u root -p"<span class="math-inline">\{MYSQL\_ROOT\_PASSWORD\}" \-e "DELETE FROM mysql\.user WHERE User\='';"
mysql \-u root \-p"</span>{MYSQL_ROOT_PASSWORD}" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
      mysql -u root -p"<span class="math-inline">\{MYSQL\_ROOT\_PASSWORD\}"</6\> \-e "DROP DATABASE IF EXISTS test;"
<6\>mysql \-u root \-p"</span>{MYSQL_ROOT_PASSWORD}" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
      mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS <span class="math-inline">\{NEXTCLOUD\_DB\_NAME\} CHARACTER SET utf8mb4 COLLATE utf8mb4\_general\_ci;"
USER\_EXISTS\=</span>(mysql -u root -p"<span class="math-inline">\{MYSQL\_ROOT\_PASSWORD\}" \-e "SELECT User FROM mysql\.user WHERE User\='</span>{NEXTCLOUD_DB_USER}';" | grep -o "${NEXTCLOUD_DB_USER}" || echo "")
      [[ -z "<span class="math-inline">USER\_EXISTS" \]\] && mysql \-u root \-p"</span>{MYSQL_ROOT_PASSWORD}" -e "CREATE USER '<span class="math-inline">\{NEXTCLOUD\_DB\_USER\}'@'localhost' IDENTIFIED BY '</span>{NEXTCLOUD_DB_PASSWORD}';"
      mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON <span class="math-inline">\{NEXTCLOUD\_DB\_NAME\}\.\* TO '</span>{NEXTCLOUD_DB_USER}'@'localhost';"
      mysql -u root -p"<span class="math-inline">\{MYSQL\_ROOT\_PASSWORD\}" \-e "FLUSH PRIVILEGES;"
fi
;;
"Alpine"\)
\# Alpine spezifische MariaDB Konfiguration
<3\>mysql \-e "SET PASSWORD FOR root@localhost \= PASSWORD\('</span>{MYSQL_ROOT_PASSWORD}');"
    mysql -e "DELETE FROM mysql.user WHERE User='';"
    mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    mysql -e "DROP DATABASE IF EXISTS test;"
    mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"

    mysql -e "CREATE DATABASE IF NOT EXISTS <span class="math-inline">\{NEXTCLOUD\_DB\_NAME\} CHARACTER SET utf8mb4 COLLATE utf8mb4\_general\_ci;"
USER\_EXISTS\=</span>(mysql -e "SELECT User FROM mysql.user WHERE User='<span class="math-inline">\{NEXTCLOUD\_DB\_USER\}';" \| grep \-o "</span>{NEXTCLOUD_DB_USER}" || echo "")
    [[ -z "<span class="math-inline">USER\_EXISTS" \]\] && mysql \-e "CREATE USER '</span>{NEXTCLOUD_DB_USER}'@'localhost' IDENTIFIED BY '${NEXTCLOUD_DB_PASSWORD}';"
    mysql -e "GRANT ALL PRIVILEGES ON <span class="math-inline">\{NEXTCLOUD\_DB\_NAME\}\.\* TO '</span>{NEXTCLOUD_DB_USER}'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    ;;
esac

# MariaDB-Konfigurationspfad
MARIADB_CONF_DIR="/etc/mysql/mariadb.conf.d"
[[ ! -d "<span class="math-inline">MARIADB\_CONF\_DIR" \]\] && \{
\[\[ \-d "/etc/mysql/conf\.d" \]\] && MARIADB\_CONF\_DIR\="/etc/mysql/conf\.d" \|\| mkdir \-p "/etc/mysql/mariadb\.conf\.d";
\}
\# MariaDB\-Konfiguration für Nextcloud
cat \> "</span>{MARIADB_CONF_DIR}/99-nextcloud.cnf" << EOF
[mysqld]
transaction_isolation = READ-COMMITTED
binlog_format = ROW
innodb_large_prefix=on
innodb_file_format=barracuda
innodb_file_per_table=1
max_allowed_packet = 128M
EOF

# MariaDB neustarten
systemctl restart <span class="math-inline">\(systemctl list\-units \-\-type\=service \| grep \-q "mariadb\.service" && echo "mariadb" \|\| echo "mysql"\)
\# 11\. Redis konfigurieren
echo \-e "</span>{BLUE}[5/10] Redis wird konfiguriert...${NC}"

# Redis-Konfigurationspfad
REDIS_CONF="/etc/redis/redis.conf"
[[ ! -f "$REDIS_CONF" && -f "/etc/redis/redis-server.conf" ]] && REDIS_CONF="/etc/redis/redis-server.conf"
[[ ! -f "<span class="math-inline">REDIS\_CONF" \]\] && \{ echo \-e "</span>{RED}Redis-Konfigurationsdatei nicht gefunden.${NC}"; exit 1; }

# Redis konfigurieren
case "$OS_TYPE" in
  "Debian" | "Ubuntu")
    sed -i "s/port 6379/port 0/" $REDIS_CONF
    sed -i "s/# unixsocket/unixsocket/" $REDIS_CONF
    sed -i "s/# unixsocketperm 700/unixsocketperm 770/" $REDIS_CONF
    sed -i "s/^unixsocketperm 700/unixsocketperm 770/" $REDIS_CONF 2>/dev/null || true
    usermod -a -G redis www-data
    ;;
  "Alpine")
    sed -i "s/port 6379/port 0/" $REDIS_CONF
    sed -i "s/# unixsocket \/run\/redis\/redis.sock/unixsocket \/run\/redis\/redis.sock/" $REDIS_CONF
    sed -i "s/# unixsocket-perm 700/unixsocket-perm 770/" $REDIS_CONF
    sed -i "s/^unixsocket-perm 700/unixsocket-perm 770/" <span class="math-inline">REDIS\_CONF 2\>/dev/null \|\| true
\# Add www\-data to the redis group\.  This may need adjustment for Alpine
addgroup www\-data redis
;;
esac
\# Redis neustarten
REDIS\_SERVICE\=</span>(systemctl list-units --type=service | grep -q "redis-server.service" && echo "redis-server" || echo "redis")
systemctl restart <span class="math-inline">REDIS\_SERVICE \|\| \{ echo \-e "</span>{RED}Redis-Service nicht gefunden.<span class="math-inline">\{NC\}"; exit 1; \}
\# 12\. PHP für Nextcloud optimieren
echo \-e "</span>{BLUE}[6/10] PHP-Konfiguration für Nextcloud optimieren...${NC}"
case "<span class="math-inline">OS\_TYPE" in
"Debian" \| "Ubuntu"\)
for sapi in fpm cli apache2; do
if \[ \-d "/etc/php/</span>{PHP_VERSION}/<span class="math-inline">sapi/conf\.d" \]; then
echo \-e "</span>{BLUE}→ PHP-SAPI: <span class="math-inline">sapi wird konfiguriert\.\.\.</span>{NC}"
        cat > /etc/php/${PHP_VERSION}/$sapi/conf.d/99-nextcloud.ini << EOF
memory_limit = 512M
upload_max_filesize = 500M
post_max_size = 500M
max_execution_time = 300
date.timezone = Europe/Berlin

opcache.enable=1
opcache.interned_strings_buffer=32
opcache.max_accelerated_files=10000
opcache.memory_consumption=128
opcache.save_comments=1
opcache.revalidate_freq=1
EOF
      fi
    done
    [[ <span class="math-inline">\(systemctl list\-units \-\-type\=service \| grep \-q "php</span>{PHP_VERSION}-fpm") ]] && systemctl restart php${PHP_VERSION}-fpm
    ;;
  "Alpine")
    # Alpine spezifische PHP Optimierung
    for ini in /etc/php8/php.ini /etc/php8/php-fpm.d/www.conf; do
      sed -i "s/^;memory_limit = 128M/memory_limit = 512M/" $ini
      sed -i "s/^upload_max_filesize = 2M/upload_max_filesize = 500M/" $ini
      sed -i "s/^post_max_size = 8M/post_max_size = 500M/" $ini
      sed -i "s/^max_execution_time = 30/max_execution_time = 300/" $ini
      sed -i "s/^;date.timezone =/date.timezone = Europe\/Berlin/" $ini

      # Enable opcache
      sed -i "s/^;opcache.enable = 1/opcache.enable = 1/" $ini
      sed -i "s/^;opcache.interned_strings_buffer = 8/opcache.interned_strings_buffer = 32/" $ini
      sed -i "s/^;opcache.max_accelerated_files = 1000/opcache.max_accelerated_files = 10000/" $ini
      sed -i "s/^;opcache.memory_consumption = 64/opcache.memory_consumption = 128/" $ini
      sed -i "s/^;opcache.save_comments = 1/opcache.save_comments = 1/" $ini
      sed -i "s/^;opcache.revalidate_freq = 2/opcache.revalidate_freq = 1/" <span class="math-inline">ini
done
systemctl restart php8\-fpm
;;
esac
\# 13\. Apache Virtual Host konfigurieren
echo \-e "</span>{BLUE}[7/10] Apache Virtual Host für Nextcloud wird konfiguriert...${NC}"
case "<span class="math-inline">OS\_TYPE" in
"Debian" \| "Ubuntu"\)
mkdir \-p /etc/ssl/nextcloud/
openssl req \-x509 \-nodes \-days 365 \-newkey rsa\:2048 \\
\-keyout /etc/ssl/nextcloud/nextcloud\.key \\
\-out /etc/ssl/nextcloud/nextcloud\.crt \\
\-subj "/CN\=</span>{DOMAIN_NAME}/O=Nextcloud/C=DE"

    cat > /etc/apache2/sites-available/nextcloud.conf << EOF
<VirtualHost *:80>
    ServerName <span class="math-inline">\{DOMAIN\_NAME\}
Redirect permanent / https\://</span>{DOMAIN_NAME}/
</VirtualHost>

<VirtualHost *:443>
    ServerName <span class="math-inline">\{DOMAIN\_NAME\}
DocumentRoot /var/www/nextcloud</2\>
SSLEngine on
SSLCertificateFile /etc/ssl/nextcloud/nextcloud\.crt
SSLCertificateKeyFile /etc/ssl/nextcloud/nextcloud\.key
<IfModule <3\>mod\_headers\.c\>
Header always set Strict\-Transport\-Security "max\-age\=15552000; includeSubDomains"
</IfModule\>
<Directory /var/www/nextcloud\>
<4\>Options \+FollowSymlinks
AllowOverride All</3\>
Require all granted
<IfModule mod\_dav\.c\>
Dav off
</IfModule\>
<5\>SetEnv HOME /var/www/nextcloud
SetEnv HTTP\_HOME /var/www/nextcloud
</Directory\>
ErrorLog</4\> \\$\{APACHE\_LOG\_DIR\}/nextcloud\_error\.log
CustomLog \\$\{APACHE\_LOG\_DIR\}/nextcloud\_access\.log combined</5\>
</VirtualHost\>
EOF
a2enmod headers ssl
a2ensite nextcloud\.conf
systemctl reload apache2
;;
"Alpine"\)
\# Alpine spezifische Virtual Host Konfiguration
mkdir \-p /<6\>etc/apache2/ssl/
openssl req \-x509 \-nodes \-days 365 \-newkey rsa\:2048 \\
\-keyout /etc/apache2/ssl/apache\.key \\
\-out /etc/apache2/ssl/apache\.crt</6\> \\
\-subj "/CN\=</span>{DOMAIN_NAME}/O=Nextcloud/C=DE"

    cat > /etc/apache2/conf/vhosts/nextcloud.conf <<EOF
<VirtualHost *:80>
    ServerName <span class="math-inline">\{DOMAIN\_NAME\}
Redirect permanent / https\://</span>{DOMAIN_NAME}/
</VirtualHost>

<VirtualHost *:443>
    ServerName <span class="math-inline">\{DOMAIN\_NAME\}
DocumentRoot /var/www/nextcloud</2\>
SSLEngine on
SSLCertificateFile /etc/apache2/ssl/apache\.crt
SSLCertificateKeyFile /etc/apache2/ssl/apache\.key
<IfModule <3\>mod\_headers\.c\>
Header always set Strict\-Transport\-Security "max\-age\=15552000; includeSubDomains"
</IfModule\>
<Directory /var/www/nextcloud\>
<4\>Options \+FollowSymlinks
AllowOverride All</3\>
Require all granted
<IfModule mod\_dav\.c\>
Dav off
</IfModule\>
SetEnv HOME /var/www/nextcloud
SetEnv HTTP\_HOME /var/www/nextcloud
</Directory\>
ErrorLog</4\> /var/log/apache2/error\_log
CustomLog /var/log/apache2/access\_log combined
</VirtualHost\>
EOF
\# Enable the necessary modules and the virtual host\.
sed \-i 's/\#LoadModule\\s\*ssl\_module/LoadModule ssl\_module/' /etc/apache2/httpd\.conf
echo "Include conf/vhosts/nextcloud\.conf" \>\> /etc/apache2/httpd\.conf
apachectl restart
;;
esac
\# 14\. Nextcloud installieren
echo \-e "</span>{BLUE}[8/10] Nextcloud wird heruntergeladen und installiert...${NC}"
case "<span class="math-inline">OS\_TYPE" in
"Debian" \| "Ubuntu"\)
wget \-q https\://download\.nextcloud\.com/server/releases/latest\.zip \-O /tmp/nextcloud\.zip
unzip \-q /tmp/nextcloud\.zip \-d /var/www/
rm /tmp/nextcloud\.zip
mkdir \-p "</span>{NEXTCLOUD_DATA_DIR}"
    chown -R www-data:www-data /var/www/nextcloud/ "<span class="math-inline">\{NEXTCLOUD\_DATA\_DIR\}"
;;
"Alpine"\)
\# Alpine spezifische Nextcloud Installation
wget \-q https\://download\.nextcloud\.com/server/releases/latest\.tar\.bz2 \-O /tmp/nextcloud\.tar\.bz2
tar \-xjf /tmp/nextcloud\.tar\.bz2 \-C /var/www/
rm /tmp/nextcloud\.tar\.bz2
mkdir \-p "</span>{NEXTCLOUD_DATA_DIR}"
    chown -R www-data:www-data /var/www/nextcloud/ "<span class="math-inline">\{NEXTCLOUD\_DATA\_DIR\}"
;;
esac
\# 15\. Initialisieren
echo \-e "</span>{BLUE}[9/10] Nextcloud wird initialisiert...${NC}"
cd /var/www/nextcloud
case "<span class="math-inline">OS\_TYPE" in
"Debian" \| "Ubuntu"\)
sudo \-u www\-data <7\>php occ maintenance\:install \\
\-\-database "mysql" \\
\-\-database\-name "</span>{NEXTCLOUD_DB_NAME}" \
      --database-user "<span class="math-inline">\{NEXTCLOUD\_DB\_USER\}" \\
\-\-<8\>database\-pass "</span>{NEXTCLOUD_DB_PASSWORD}" \
      --admin-user "<span class="math-inline">\{NEXTCLOUD\_ADMIN\_USER\}" \\
\-\-admin\-pass "</span>{NEXTCLOUD_ADMIN_PASSWORD}" \
      --data-dir "<span class="math-inline">\{NEXTCLOUD\_DATA\_DIR\}"</8\>
;;
"Alpine"\)
\# Alpine spezifische Nextcloud Initialisierung
<7\>php occ maintenance\:install \\
\-\-database "mysql" \\
\-\-database\-name "</span>{NEXTCLOUD_DB_NAME}" \
      --database-user "<span class="math-inline">\{NEXTCLOUD\_DB\_USER\}" \\
\-\-<8\>database\-pass "</span>{NEXTCLOUD_DB_PASSWORD}" \
      --admin-user "<span class="math-inline">\{NEXTCLOUD\_ADMIN\_USER\}" \\
\-\-admin\-pass "</span>{NEXTCLOUD_ADMIN_PASSWORD}" \
      --data-dir "${NEXTCLOUD_DATA_DIR}"
    ;;
esac

# Nextcloud Konfiguration
case "<span class="math-inline">OS\_TYPE" in
"Debian" \| "Ubuntu"\)
sudo \-u www\-data php occ config\:system\:set trusted\_domains 0 \-\-value\="</span>{DOMAIN_NAME}" \
    && sudo -u www-data php occ config:system:set trusted_domains 1 --value="<span class="math-inline">\{SERVER\_IP\}" \\
&& sudo \-u www\-data php occ config\:system\:set memcache\.local \-\-value\='\\OC\\Memcache\\APCu' \\
&& sudo \-u www\-data php occ config\:system\:set memcache\.locking \-\-value\='\\OC\\Memcache\\Redis' \\
&& sudo \-u www\-data php occ config\:system\:set redis host \-\-value\='/var/run/redis/redis\-server\.sock' \\
&& sudo \-u www\-data php occ config\:system\:set redis port \-\-value\=0 \\
&& sudo \-u www\-data php occ config\:system\:set redis timeout \-\-value\=0\.0 \\
&& sudo \-u www\-data php occ config\:system\:set trusted\_proxies 0 \-\-value\="127\.0\.0\.1" \\
&& sudo \-u www\-data php occ config\:system\:set overwriteprotocol \-\-value\="https" \\
&& <9\>sudo \-u www\-data php occ config\:system\:set htaccess\.RewriteBase \-\-value\="/" \\
&& sudo \-u www\-data php occ maintenance\:update\:htaccess</9\>
;;
"Alpine"\)
\# Alpine spezifische Nextcloud Konfiguration
php occ config\:system\:set trusted\_domains 0 \-\-value\="</span>{DOMAIN_NAME}" \
    && php occ config:system:set trusted_domains 1 --value="<span class="math-inline">\{SERVER\_IP\}" \\
&& <10\>php occ config\:system\:set memcache\.local \-\-value\='\\OC\\Memcache\\APCu' \\
&& php occ config\:system\:set memcache\.locking \-\-value\='\\OC\\Memcache\\Redis' \\
&& php occ config\:system\:set</10\> redis host \-\-value\='/run/redis/redis\.sock' \\
&& php occ config\:system\:set redis port \-\-value\=0 \\
&& php occ config\:system\:set redis timeout \-\-value\=0\.0 \\
&& php occ config\:system\:set trusted\_proxies 0 \-\-value\="127\.0\.0\.1" \\
&& php occ config\:system\:set overwriteprotocol \-\-value\="https" \\
&& php occ config\:system\:set htaccess\.RewriteBase \-\-value\="/"
;;
esac
\# 16\. Cronjob
echo \-e "</span>{BLUE}Cronjob wird eingerichtet...${NC}"
case "<span class="math-inline">OS\_TYPE" in
"Debian" \| "Ubuntu"\)
echo "\*/5 \* \* \* \* www\-data php \-f /var/www/nextcloud/cron\.php" \> /etc/cron\.d/nextcloud
sudo \-u www\-data php occ background\:cron
;;
"Alpine"\)
\# Alpine spezifische Cronjob Einrichtung
echo "\*/5 \* \* \* \* www\-data php \-f /var/www/nextcloud/cron\.php" \> /etc/crontabs/www\-data
php occ background\:cron
;;
esac
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
echo -e "Root Passwort
: ${GREEN}${MYSQL_ROOT_PASSWORD}${NC}"
echo -e "Datenbank: ${GREEN}${NEXTCLOUD_DB_NAME}${NC}"
echo -e "DB Benutzer: ${GREEN}${NEXTCLOUD_DB_USER}${NC}"
echo -e "DB Passwort: ${GREEN}${NEXTCLOUD_DB_PASSWORD}${NC}"
echo -e "\nInstalliert am: ${GREEN}${INSTALLATION_DATE}${NC}"
EOF
chmod +x /usr/local/bin/nextcloud-credentials

# 19. Zusätzliche Nextcloud-Konfiguration
config_file="/var/www/nextcloud/config/config.php"
if [ -f "$config_file" ]; then
  tmp_file=$(mktemp)
  awk '
    /^\);$/ {
      print "  '\''default_phone_region'\'' => '\''DE'\'',";
      print "  '\''enable_previews'\'' => true,";
      print "  '\''enabledPreviewProviders'\'' => array (";
      print "    0 => '\''OC\\\\\\\\Preview\\\\\\\\PNG'\'',";
      print "    1 => '\''OC\\\\\\\\Preview\\\\\\\\JPEG'\'',";
      print "    2 => '\''OC\\\\\\\\Preview\\\\\\\\GIF'\'',";
      print "    3 => '\''OC\\\\\\\\Preview\\\\\\\\BMP'\'',";
      print "    4 => '\''OC\\\\\\\\Preview\\\\\\\\XBitmap'\'',";
      print "    5 => '\''OC\\\\\\\\Preview\\\\\\\\MP3'\'',";
      print "    6 => '\''OC\\\\\\\\Preview\\\\\\\\TXT'\'',";
      print "    7 => '\''OC\\\\\\\\Preview\\\\\\\\MarkDown'\'',";
      print "    8 => '\''OC\\\\\\\\Preview\\\\\\\\OpenDocument'\'',";
      print "    9 => '\''OC\\\\\\\\Preview\\\\\\\\Krita'\'',";
      print "    10 => '\''OC\\\\\\\\Preview\\\\\\\\HEIC'\'',";
      print "  ),";
      print "  '\''maintenance_window_start'\'' => 1,";
    }
    { print }
  ' "$config_file" > "$tmp_file"
  cp "$config_file" "${config_file}.bak"
  cp "$tmp_file" "$config_file"
  rm "$tmp_file"
fi

# 20. Letzter Feinschliff
case "$OS_TYPE" in
  "Debian" | "Ubuntu")
    sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --on
    sudo -u www-data php occ maintenance:repair --include-expensive
    sudo systemctl restart apache2
    ;;
  "Alpine")
    php /var/www/nextcloud/occ maintenance:mode --on
    php occ maintenance:repair --include-expensive
    apachectl restart
    ;;
esac

# Fortschrittsbalken
echo "Warte, bis der Webserver vollständig hochgefahren ist..."
for i in $(seq 1 10); do echo -n "#"; sleep 1; done
echo

# Log bereinigen
rm -f /var/www/nextcloud/data/nextcloud.log
curl -s -o /dev/null http://localhost || true
case "$OS_TYPE" in
  "Debian" | "Ubuntu")
    sudo -u www-data php /var/www/nextcloud/occ maintenance:mode --off
    ;;
  "Alpine")
    php /var/www/nextcloud/occ maintenance:mode --off
    ;;
esac

# Bereinigen
rm -rf /opt/scriptfiles/testarea-main /opt/main.zip 2>/dev/null || true

# 21. Abschlussmeldung
clear
echo -e "${BLUE}===== Nextcloud Zugangsdaten =====\n${NC}"
echo -e "\n${BLUE}Zugangsdaten:${NC}"
echo -e "Admin Benutzer: ${GREEN}${NEXTCLOUD_ADMIN_USER}${NC}"
echo -e "Admin Passwort: ${GREEN}${NEXTCLOUD_ADMIN_PASSWORD}${NC}"
echo
echo -e "${GREEN}===== Nextcloud Installation abgeschlossen! =====${NC}"
echo -e "Anmeldung unter folgendem Link:\n"
echo -e "IP:  ${BLUE}https://${SERVER_IP}${NC}"
echo -e "\nBenutzen Sie den Befehl ${GREEN}nextcloud-credentials${NC}, um Ihre kompletten Zugangsdaten anzuzeigen."
