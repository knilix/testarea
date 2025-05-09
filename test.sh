#!/bin/bash
# Maintainer: @knilix
# Version: 1.1
# Hinweis: Für Ubuntu ab 22.04+ (x64), root erforderlich
#
# Herunterladen: wget -q -P /opt/ https://github.com/knilix/testarea/archive/refs/heads/main.zip && unzip /opt/main.zip -d /opt/scriptfiles && chmod 700 /opt/scriptfiles/testarea-main/test.sh
# Installieren: cd && cd /opt/scriptfiles/testarea-main && ./test.sh
# Bei Problemen, das Heuntergeladene wieder löschen: rm -rf /opt/scriptfiles/testarea-main /opt/main.zip 
#
# Script nur einmalig ausführen - - Abfrage einer vorhandenen Nextcloud-Datenbank noch nicht implementiert!
# Mit MariaDB und Redis Cache
# -----------------------------------------------------------------------------
# Nextcloud Installation Script für Ubuntu-Server
# Dieses Script installiert snapd, Nextcloud, konfiguriert einen Admin-Benutzer,
# behebt das Header-Transport-Problem und richtet den Zugriff korrekt ein

# Funktion für formatierte Ausgaben
print_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Funktion zum Prüfen des Befehls-Erfolgs
check_success() {
    if [ $? -ne 0 ]; then
        print_message "FEHLER: $1"
        exit 1
    else
        print_message "ERFOLG: $1"
    fi
}

# Root-Rechte prüfen
if [ "$(id -u)" -ne 0 ]; then
    print_message "Dieses Script muss mit Root-Rechten ausgeführt werden (sudo)."
    exit 1
fi

# Systemaktualisierung
print_message "System wird aktualisiert..."
apt update && apt upgrade -y
check_success "System-Update"

# Snapd installieren
print_message "Installiere snapd..."
apt install -y snapd
check_success "snapd Installation"

# Sicherstellen, dass snap-Dienst aktiv ist
systemctl enable --now snapd.socket
systemctl start snapd.service
check_success "snapd-Dienste gestartet"

# Warten, bis snap-System bereit ist
sleep 5

# Nextcloud installieren
print_message "Installiere Nextcloud via snap..."
snap install nextcloud
check_success "Nextcloud Installation"

# Sicheres Admin-Passwort generieren (24 Zeichen)
ADMIN_USER="ncadmin"
ADMIN_PASSWORD=$(tr -dc 'A-Za-z0-9!#$%&()*+,-./:;<=>?@[\]^_{|}~' </dev/urandom | head -c 24)

# Admin-Benutzer erstellen
print_message "Konfiguriere Admin-Benutzer..."
nextcloud.manual-install "$ADMIN_USER" "$ADMIN_PASSWORD"
check_success "Admin-Benutzer Konfiguration"

# IP-Adresse ermitteln
IP_ADDRESS=$(hostname -I | awk '{print $1}')
if [ -z "$IP_ADDRESS" ]; then
    print_message "Warnung: IP-Adresse konnte nicht ermittelt werden. Verwende 'localhost'."
    IP_ADDRESS="localhost"
fi

# IP-Adresse als trusted domain hinzufügen
print_message "Füge IP-Adresse $IP_ADDRESS als vertrauenswürdige Domain hinzu..."
nextcloud.occ config:system:set trusted_domains 1 --value="$IP_ADDRESS"
check_success "Vertrauenswürdige Domain hinzugefügt"

# Header-Transport-Problem beheben durch Anpassung der Konfiguration
print_message "Behebe Header-Transport-Problem..."
nextcloud.occ config:system:set overwriteprotocol --value="https"
check_success "Header-Transport-Problem behoben (overwriteprotocol)"

# Zusätzlich trusted_proxies und forwarded_for_headers setzen
nextcloud.occ config:system:set trusted_proxies 0 --value="127.0.0.1"
nextcloud.occ config:system:set trusted_proxies 1 --value="$IP_ADDRESS"
nextcloud.occ config:system:set forwarded_for_headers 0 --value="HTTP_X_FORWARDED_FOR"
check_success "Proxy-Einstellungen konfiguriert"

# Neustart des Apache-Servers
print_message "Starte Nextcloud-Dienste neu..."
snap restart nextcloud
check_success "Nextcloud-Dienste neugestartet"

# Warten, bis der Dienst wieder verfügbar ist
print_message "Warte, bis Nextcloud bereit ist..."
sleep 10

# Credentials in Datei speichern
CREDENTIALS_FILE="/root/nextcloud_credentials.txt"
cat > "$CREDENTIALS_FILE" << EOF
Nextcloud Installation Credentials
=================================
Datum: $(date '+%Y-%m-%d %H:%M:%S')
HTTP-URL: http://$IP_ADDRESS
HTTPS-URL: https://$IP_ADDRESS (Selbstsigniertes Zertifikat - Browserwarnung bestätigen)
Admin-Benutzer: $ADMIN_USER
Admin-Passwort: $ADMIN_PASSWORD
=================================
BITTE SICHER AUFBEWAHREN UND NACH DEM ERSTEN LOGIN LÖSCHEN!
EOF

# Rechte für credentials-Datei einschränken
chmod 600 "$CREDENTIALS_FILE"

# Prüfe, ob Nextcloud erreichbar ist
print_message "Prüfe Zugriff auf Nextcloud..."
if command -v curl &> /dev/null; then
    # Warte ein wenig, bis der Server vollständig gestartet ist
    sleep 15
    if curl -s -k -o /dev/null -w "%{http_code}" "http://$IP_ADDRESS" | grep -q "200\|301\|302"; then
        HTTP_AVAILABLE=true
        print_message "HTTP-Zugriff funktioniert!"
    else
        HTTP_AVAILABLE=false
        print_message "Warnung: HTTP-Zugriff scheint nicht zu funktionieren."
    fi
    
    if curl -s -k -o /dev/null -w "%{http_code}" "https://$IP_ADDRESS" | grep -q "200\|301\|302"; then
        HTTPS_AVAILABLE=true
        print_message "HTTPS-Zugriff funktioniert!"
    else
        HTTPS_AVAILABLE=false
        print_message "Warnung: HTTPS-Zugriff scheint nicht zu funktionieren (selbstsigniertes Zertifikat könnte Warnungen verursachen)."
    fi
else
    HTTP_AVAILABLE=false
    HTTPS_AVAILABLE=false
    print_message "Warnung: curl ist nicht installiert, kann Zugriff nicht überprüfen."
fi

# Erfolgsmeldung ausgeben
echo ""
echo "========================================================="
echo "Nextcloud wurde installiert!"
echo "========================================================="

if [ "$HTTP_AVAILABLE" = true ]; then
    echo "HTTP-URL: http://$IP_ADDRESS"
fi

if [ "$HTTPS_AVAILABLE" = true ]; then
    echo "HTTPS-URL: https://$IP_ADDRESS"
else
    echo "HTTPS-URL: https://$IP_ADDRESS (Selbstsigniertes Zertifikat - Browserwarnung bestätigen)"
fi

echo "Admin-Benutzer: $ADMIN_USER"
echo "Admin-Passwort: $ADMIN_PASSWORD"
echo ""
echo "Diese Informationen wurden gespeichert in: $CREDENTIALS_FILE"
echo "========================================================="
echo "WICHTIG:"
echo "- Ändere das Passwort nach dem ersten Login und lösche"
echo "  die Credentials-Datei aus Sicherheitsgründen!"
echo "- Falls du Verbindungsprobleme hast, prüfe folgendes:"
echo "  * Firewall-Einstellungen (Ports 80 und 443)"
echo "  * Führe 'snap restart nextcloud' aus"
echo "  * Bei HTTPS: Akzeptiere das selbstsignierte Zertifikat"
echo "========================================================="
