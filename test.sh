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
# 1. Fehler-Handling und Farben
#!/bin/bash

set -euo pipefail

echo "=== Nextcloud-Installation über Snap auf Ubuntu Server ==="

# Check root
if [[ "$EUID" -ne 0 ]]; then
  echo "Dieses Skript muss als root ausgeführt werden." >&2
  exit 1
fi

# Installiere snapd, falls nicht vorhanden
if ! command -v snap &> /dev/null; then
  echo "[INFO] snapd wird installiert ..."
  apt update
  apt install -y snapd
  systemctl enable --now snapd.socket
else
  echo "[INFO] snapd ist bereits installiert."
fi

# Installiere Nextcloud über Snap
if ! snap list | grep -q nextcloud; then
  echo "[INFO] Nextcloud (Snap) wird installiert ..."
  snap install nextcloud
else
  echo "[WARNUNG] Nextcloud ist bereits installiert (Snap)."
fi

# Warte auf Initialisierung
echo "[INFO] Warte auf Nextcloud-Dienst (Snap) ..."
sleep 20

# Generiere Admin-Zugangsdaten
ADMIN_USER="admin"
PASSWORD=$(tr -dc 'A-Za-z0-9!#$%&()*+,-.:;<=>?@[]^_{}~' < /dev/urandom | head -c 24)

# Setze Admin-Benutzer (nur falls noch nicht gesetzt)
if ! nextcloud.occ user:info "$ADMIN_USER" &>/dev/null; then
  echo "[INFO] Admin-Benutzer wird eingerichtet ..."
  nextcloud.manual-install "$ADMIN_USER" "$PASSWORD"
else
  echo "[WARNUNG] Admin-Benutzer existiert bereits – Passwort bleibt unverändert."
fi

# Ermittle IP-Adresse
IP=$(hostname -I | awk '{print $1}')
echo "[INFO] Server-IP-Adresse erkannt: $IP"

# Setze Trusted Domain
nextcloud.occ config:system:set trusted_domains 1 --value="$IP"

# Behebe Transport-Header-Warnung
nextcloud.occ config:system:set overwrite.cli.url --value="http://$IP"
nextcloud.occ config:system:set overwriteprotocol --value="http"

# Zugangsdaten speichern
CREDENTIAL_FILE="/root/nextcloud_admin_credentials.txt"
{
  echo "Nextcloud URL: http://$IP"
  echo "Benutzer: $ADMIN_USER"
  echo "Passwort: $PASSWORD"
} > "$CREDENTIAL_FILE"
chmod 600 "$CREDENTIAL_FILE"

# Ausgabe
echo -e "\n=== ✅ Nextcloud erfolgreich installiert ==="
echo "📬 URL:       http://$IP"
echo "👤 Benutzer:  $ADMIN_USER"
echo "🔐 Passwort:  $PASSWORD"
echo "💾 Gespeichert in: $CREDENTIAL_FILE (nur root-lesbar)"

