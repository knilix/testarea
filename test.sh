#!/bin/bash
#
# Maintainer: @knilix
# Version: 1.0.1
#
# Faulty: 403 Forbidden nginx
#
# Script to install Nextcloud with Nginx, MariaDB and Redis using Docker Compose
# Compatible with Debian and Ubuntu systems
# Script nur einmalig ausführen - - Abfrage einer vorhandenen Nextcloud-Datenbank noch nicht implementiert!
# -----------------------------------------------------------------------------------------------------------------------------
# download and unzip: wget -q -P /opt/ https://github.com/knilix/testarea/archive/refs/heads/main.zip && unzip /opt/main.zip -d /opt/scriptfiles && chmod 700 /opt/scriptfiles/testarea-main/test.sh
# execute (unique): cd /opt/scriptfiles/testarea-main && ./test.sh
# in case of problems: rm -rf /opt/scriptfiles/testarea-main /opt/main.zip 2>/dev/null || true
# -----------------------------------------------------------------------------------------------------------------------------

set -e

# Farbcodierung für die Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="/opt/nextcloud-docker"
DATA_DIR="<span class="math-inline">\{SCRIPT\_DIR\}/nextcloud\_data"
CONFIG\_FILE\="</span>{DATA_DIR}/config/config.php"

# Funktion zur Ausgabe von Nachrichten
info() {
  echo "<span class="math-inline">\{GREEN\}\[INFO\]</span>{NC} <span class="math-inline">1"
\}
warn\(\) \{
echo "</span>{YELLOW}[WARN]${NC} <span class="math-inline">1"
\}
error\(\) \{
echo "</span>{RED}[ERROR]${NC} $1"
}

# Betriebssystem erkennen
info "Überprüfe das Betriebssystem..."
if [[ -f /etc/debian_version ]]; then
  OS="debian"
  info "Betriebssystem erkannt: Debian"
elif [[ -f /etc/os-release && grep -q "Ubuntu" /etc/os-release ]]; then
  OS="ubuntu"
  info "Betriebssystem erkannt: Ubuntu"
else
  error "Unbekanntes Betriebssystem. Das Skript wurde für Debian und Ubuntu entwickelt."
  exit 1
fi

# Docker installieren (falls nicht vorhanden)
if ! command -v docker &> /dev/null; then
  info "Docker ist nicht installiert. Installiere Docker..."
  if [[ "<span class="math-inline">OS" \=\= "debian" \]\]; then
sudo apt update
sudo apt install \-y ca\-certificates curl gnupg
<0\>sudo mkdir \-p /etc/apt/keyrings
curl \-fsSL https\://download\.docker\.com/linux/debian/gpg \| sudo gpg \-\-dearmor \-o /etc/apt/keyrings/docker\.gpg
echo "deb \[arch\=</span>(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian stable docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  elif [[ "<span class="math-inline">OS" \=\= "ubuntu" \]\]; then
sudo apt update
sudo apt install \-y <3\>ca\-certificates curl gnupg
sudo mkdir \-p /etc/apt/keyrings
curl \-fsSL https\://download\.docker\.com/linux/ubuntu/gpg \| sudo gpg \-\-dearmor \-o /etc/apt/keyrings/docker\.gpg</3\>
<0\>echo "deb \[arch\=</span>(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  fi
  sudo groupadd --force docker
  sudo usermod -aG docker "$USER"
  info "Docker wurde installiert. Bitte logge dich einmal aus und wieder ein oder führe 'newgrp docker' aus, um die Docker-Gruppe zu aktivieren."
  read -p "Drücke [Enter] nachdem du dich neu eingeloggt hast..."
fi

# Docker Compose installieren (falls nicht vorhanden)
if ! command -v docker compose &> /dev/null; then
  info "Docker Compose ist nicht installiert. Installiere Docker Compose..."
  if [[ "$OS" == "debian" || "<span class="math-inline">OS" \=\= "ubuntu" \]\]; then
sudo apt update
sudo apt install \-y docker\-compose\-plugin
else
warn "Docker Compose konnte nicht automatisch für dein Betriebssystem installiert werden\. Bitte installiere es manuell\."
fi
fi
\# Generiere zufällige Passwörter
DB\_ROOT\_PASSWORD\=</span>(openssl rand -base64 32)
NEXTCLOUD_ADMIN_PASSWORD=<span class="math-inline">\(openssl rand \-base64 32\)
\# Aktuelle IP\-Adresse ermitteln
IP\_ADDRESS\=</span>(ip addr show | grep -oE 'inet [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | awk '{print $2}' | head -n 1)
if [ -z "$IP_ADDRESS" ]; then
  error "Konnte die IP-Adresse nicht ermitteln. Bitte überprüfe deine Netzwerkverbindung."
  exit 1
fi
info "Deine aktuelle IP-Adresse ist: ${IP_ADDRESS}"

# Erstelle das Verzeichnis für docker-compose.yml
mkdir -p "$SCRIPT_DIR"
cd "<span class="math-inline">SCRIPT\_DIR"
\# Erstelle die docker\-compose\.yml Datei
cat <<EOF \> docker\-compose\.yml
version\: '3\.8'
services\:
db\:
image\: mariadb\:10\.11
restart\: always
volumes\:
\- db\:/var/lib/mysql
environment\:
\- MARIADB\_ROOT\_PASSWORD\=</span>{DB_ROOT_PASSWORD}
      - MARIADB_USER=nextcloud
      - MARIADB_PASSWORD=nextcloud
      - MARIADB_DATABASE=nextcloud

  redis:
    image: redis:alpine
    restart: always

  app:
    image: nextcloud:latest
    restart: always
    ports:
      - 80:80
      - 443:443
    volumes:
      - nextcloud:/var/www/html
      - <span class="math-inline">\{DATA\_DIR\}\:/var/www/html/data
\- \./config\:/var/www/html/config
\- \./apps\:/var/www/html/apps
\- \./themes\:/var/www/html/themes
environment\:
\- NEXTCLOUD\_TRUSTED\_DOMAINS\=</span>{IP_ADDRESS}
      - NEXTCLOUD_DB_TYPE=mysql
      - NEXTCLOUD_DB_HOST=db
      - NEXTCLOUD_DB_NAME=nextcloud
      - NEXTCLOUD_DB_USER=nextcloud
      - NEXTCLOUD_DB_PASSWORD=nextcloud
      - NEXTCLOUD_REDIS_HOST=redis
      - NEXTCLOUD_REDIS_PORT=6379
      - NEXTCLOUD_ADMIN_USER=admin
      - NEXTCLOUD_ADMIN_PASSWORD=<span class="math-inline">\{NEXTCLOUD\_ADMIN\_PASSWORD\}
\- PHP\_MEMORY\_LIMIT\=512M
\- PHP\_UPLOAD\_LIMIT\=20G
depends\_on\:
\- db
\- redis
nginx\:
image\: nginx\:latest
restart\: always
ports\:
\- 8080\:80 \# Port für HTTP \(kann später angepasst werden\)
\- 8443\:443 \# Port für HTTPS \(kann später angepasst werden\)
volumes\:
\- \./nginx/default\.conf\:/etc/nginx/conf\.d/default\.conf\:ro
\- \./cert\:/etc/nginx/certs
depends\_on\:
\- app
environment\:
\- NEXTCLOUD\_IP\=</span>{IP_ADDRESS}

volumes:
  db:
  nextcloud:
EOF

# Erstelle die nginx Konfigurationsdatei
mkdir -p "<span class="math-inline">\{SCRIPT\_DIR\}/nginx"
cat <<EOF \> "</span>{SCRIPT_DIR}/nginx/default.conf"
server {
    listen 80;
    server_name ${IP_ADDRESS};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name <span class="math-inline">\{IP\_ADDRESS\};
ssl\_certificate /etc/nginx/certs/selfsigned\.crt;
ssl\_certificate\_key /etc/nginx/certs/selfsigned\.<4\>key;
location / \{
proxy\_pass http\://app\:80;
<5\>proxy\_set\_header Host \\$host;
proxy\_set\_header X\-Real\-IP \\$remote\_addr;
proxy\_set\_header X\-Forwarded\-For \\$proxy\_add\_x\_forwarded\_for;</4\>
proxy\_set\_header X\-Forwarded\-Proto \\$scheme;</5\>
\}
\}
EOF
\# Erstelle das Verzeichnis für Zertifikate und generiere selbstsigniertes Zertifikat
mkdir \-p "</span>{SCRIPT_DIR}/cert"
cd "<span class="math-inline">\{SCRIPT\_DIR\}/cert"
info "Generiere selbstsigniertes Zertifikat\.\.\."
openssl genrsa \-out selfsigned\.key 2048
openssl req \-new \-key selfsigned\.key \-out selfsigned\.csr \-subj "/CN\=</span>{IP_ADDRESS}"
openssl x509 -req -days 365 -in selfsigned.csr -signkey selfsigned.key -out selfsigned.crt

# Erstelle die Nextcloud Konfigurationsverzeichnisse
mkdir -p "<span class="math-inline">\{DATA\_DIR\}/config" "</span>{DATA_DIR}/apps" "<span class="math-inline">\{DATA\_DIR\}/themes"
\# Erstelle eine leere config\.php, damit sie später angepasst werden kann
touch "</span>{DATA_DIR}/config/config.php"

# Starte Docker Compose
cd "$SCRIPT_DIR"
info "Starte die Docker Container..."
docker compose up -d

# Warte kurz, bis die Container gestartet sind
sleep 30

# PHP Konfiguration anpassen
info "Passe die PHP Konfiguration an..."
docker exec -it app bash -c "sed -i 's/memory_limit = .*/memory_limit = 512M/' /usr/local/etc/php/conf.d/docker-php.ini"
docker exec -it app bash -c "sed -i 's/upload_max_filesize = .*/upload_max_filesize = 20G/' /usr/local/etc/php/conf.d/docker-php.ini"
docker exec -it app bash -c "sed -i 's/post_max_size = .*/post_max_size = 500M/' /usr/local/etc/php/conf.d/docker-php.ini"
docker exec -it app bash -c "sed -i 's/max_execution_time = .*/max_execution_time = 300/' /usr/local/etc/php/conf.d/docker-php.ini"
docker exec -it app bash -c "sed -i 's/;date.timezone =/date.timezone = Europe\/Berlin/' /usr/local/etc/php/conf.d/docker-php.ini"
docker exec -it app bash -c "echo 'opcache.enable=1' >> /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini"
docker exec -it app bash -c "echo 'opcache.interned_strings_buffer=32' >> /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini"
docker exec -it app bash -c "echo 'opcache.max_accelerated_files=10000' >> /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini"
docker exec -it app bash -c "echo 'opcache.memory_consumption=128' >> /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini"
docker exec -it app bash -c "echo 'opcache.save_comments=1' >> /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini"
docker exec -it app bash -c "echo 'opcache.revalidate_freq=1' >> /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini"

# config.php automatisch anpassen, falls vorhanden
info "Passe die Nextcloud Konfiguration an..."
if [ -f "<span class="math-inline">CONFIG\_FILE" \]; then
TMP\_FILE\=</span>(mktemp)
  awk '
    /^\);$/ {
      print "  \'default_phone_region\' => \'DE\',";
      print "  \'enable_previews\' => true,";
      print "  \'enabledPreviewProviders\' => array (";
      print "    0 => \'OC\\\\\\\\Preview\\\\\\\\PNG\',";
      print "    1 => \'OC\\\\\\\\Preview\\\\\\\\JPEG\',";
      print "    2 => \'OC\\\\\\\\Preview\\\\\\\\GIF\',";
      print "    3 => \'OC\\\\\\\\Preview\\\\\\\\BMP\',";
      print "    4 => \'OC\\\\\\\\Preview\\\\\\\\XBitmap\',";
      print "    5 => \'OC\\\\\\\\Preview\\\\\\\\MP3\',";
      print "    6 => \'OC\\\\\\\\Preview\\\\\\\\TXT\',";
      print "    7 => \'OC\\\\\\\\Preview\\\\\\\\MarkDown\',";
      print "    8 => \'OC\\\\\\\\Preview\\\\\\\\OpenDocument\',";
      print "    9 => \'OC\\\\\\\\Preview\\\\\\\\Krita\',";
      print "    10 => \'OC\\\\\\\\Preview\\\\\\\\HEIC\',";
      print "  ),";
      print "  \'maintenance_window_start\' => 1,";
      print "  \'trusted_domains\' => ";
      print "  array (";
      print "    0 => \'"$IP_ADDRESS:80\',";
      print "    1 => \'"$IP_ADDRESS:443\',";
      print "  ),";
      print "  \'datadirectory\' => \'/var/www/html/data\',";
      print "  \'dbtype\' => \'mysql\',";
      print "  \'version\' => \'29.0.1.3\',"; # Bitte ggf. anpassen
      print "  \'overwrite.cli.url\' => \'http://$IP_ADDRESS:80\',";
      print "  \'dbname\' => \'nextcloud\',";
      print "  \'dbhost\' => \'db\',";
      print "  \'dbport\' => \'\',";
      print "  \'dbtableprefix\' => \'oc_\',";
      print "  \'mysql.utf8mb4\' => true,";
      print "  \'dbuser\' => \'nextcloud\',";
      print "  \'dbpassword\' => \'$NEXTCLOUD_DB_PASSWORD\',";
      print "  \'installed\' => true,";
      print "  \'instanceid\' => \'oc_xxxxxxxxxxxx\',"; # Wird beim ersten Start generiert
      print "  \'redis\' => ";
      print "  array (";
      print "    \'host\' => \'redis\',";
      print "    \'port\' => 6379,";
      print "    \'timeout\' => 0.5,";
      print "  ),";
      print "  \'memcache.local\' => \'\\\\OC\\\\Memcache\\\\APCu\',";
      print "  \'memcache.distributed\' => \'\\\\OC\\\\Memcache\\\\Redis\',";
      print "  \'memcache.locking\' => \'\\\\OC\\\\Memcache\\\\Redis\',";
      print "  \'mail_smtpmode\' => \'phpmail\',";
      print "  \'mail_sendmailmode\' => \'smtp\',";
      print "  \'default_language\' => \'de\',";
      print "  \'maintenance\' => false,";
      print "  \'theme\' => \'\',";
      print "  \'loglevel\' => 2,";
      print "  \'mail_domain\' => \'example.com\',"; # Bitte anpassen
      print "  \'mail_from_address\' => \'nextcloud\',"; # Bitte anpassen
    }
    { print }
  ' "$CONFIG_FILE" > "$TMP_FILE"
  cp "<span class="math-inline">CONFIG\_FILE" "</span>{CONFIG_FILE}.bak"
  cp "$TMP_FILE" "$CONFIG_FILE"
  rm "$TMP_FILE"
fi

# Zusätzliche Credentials für Root anlegen (direkt in MariaDB)
info "Lege zusätzliche MariaDB Credentials mit Root-Zugriff an..."
docker exec -it db mariadb -u root -p"$DB_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '$DB_ROOT_PASSWORD';"
docker exec -it db mariadb -u root -p"<span class="math-inline">DB\_ROOT\_PASSWORD" \-e "FLUSH PRIVILEGES;"
\# Ausgabe der Anmeldedaten
echo ""
info "Die Installation ist abgeschlossen\!"
echo "\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-"
echo "Nextcloud ist erreichbar unter\:"
echo "HTTP\: http\://</span>{IP_ADDRESS}:8080"
echo "HTTPS: https://${IP_ADDRESS}:8443 (selbstsigniertes Zertifikat - Warnung im Browser möglich)"
echo ""
echo "Nextcloud Admin Benutzername: admin"
echo "Nextcloud Admin Passwort: ${NEXTCLOUD_ADMIN_PASSWORD}"
echo ""
echo "MariaDB Root Passwort: ${DB_ROOT_PASSWORD}"
echo "MariaDB Benutzer
