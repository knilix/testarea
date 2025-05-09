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
# 
set -euo pipefail

echo "=== 🚀 Nextcloud (Snap) Setup für Ubuntu Server ==="

# Root-Check
if [[ "$EUID" -ne 0 ]]; then
  echo "❌ Dieses Skript muss als root ausgeführt werden."
  exit 1
fi

# Snapd installieren (wenn nötig)
if ! command -v snap &> /dev/null; then
  echo "[INFO] snapd wird installiert ..."
  apt update
  apt install -y snapd
  systemctl enable --now snapd.socket
else
  echo "[INFO] snapd ist bereits installiert."
fi

# Nextcloud installieren (Snap)
if ! snap list | grep -q nextcloud; then
  echo "[INFO] Nextcloud wird installiert (Snap) ..."
  snap install nextcloud
else
  echo "[WARNUNG] Nextcloud ist bereits installiert."
fi

# Auf nextcloud.occ warten (max. 150 Sekunden)
echo "[INFO] Warte auf Nextcloud-Dienst ..."
for i in {1..30}; do
  if nextcloud.occ status &>/dev/null; then
    echo "[INFO] Nextcloud ist bereit."
    break
  fi
  echo "[INFO] Noch nicht bereit – warte 5s ($i/30)"
  sleep 5
done

# Prüfung: Nextcloud initialisiert?
if nextcloud.occ status | grep -q "installed: true"; then
  echo "[INFO] Nextcloud ist bereits initialisiert."
  ADMIN_USER=$(nextcloud.occ user:list 2>/dev/null | awk -F: '/^\s+\S/ {print $1}' | head -n1 | xargs)
  PASSWORD="(bestehend)"
else
  echo "[INFO] Nextcloud ist noch nicht initialisiert. Warte auf Snap-Initialisierer ..."

  for i in {1..20}; do
    if nextcloud.manual-install test test 2>&1 | grep -q "Nextcloud is not installed"; then
      echo "[INFO] Nextcloud ist bereit für manuelle Installation."
      break
    fi
    echo "[INFO] Warte auf Installationsbereitschaft (manual-install) ($i/20) ..."
    sleep 5
  done

  ADMIN_USER="admin"
  PASSWORD=$(tr -dc 'A-Za-z0-9!@#$%^&*()_+=-' < /dev/urandom | head -c 24)
  echo "[INFO] Lege Benutzer '$ADMIN_USER' an ..."
  nextcloud.manual-install "$ADMIN_USER" "$PASSWORD"
fi

# IP-Adresse ermitteln
IP=$(hostname -I | awk '{print $1}')
echo "[INFO] Server-IP-Adresse erkannt: $IP"

# Trusted Domain setzen
nextcloud.occ config:system:set trusted_domains 1 --value="$IP"

# Transport-Header-Warnung beheben
nextcloud.occ config:system:set overwrite.cli.url --value="http://$IP"
nextcloud.occ config:system:set overwriteprotocol --value="http"

# Zugangsdaten sicher speichern
CREDENTIAL_FILE="/root/nextcloud_admin_credentials.txt"
{
  echo "Nextcloud URL: http://$IP"
  echo "Benutzer: $ADMIN_USER"
  echo "Passwort: $PASSWORD"
} > "$CREDENTIAL_FILE"
chmod 600 "$CREDENTIAL_FILE"

# Ausgabe
echo -e "\n=== ✅ Nextcloud Setup abgeschlossen ==="
echo "🌐 URL:       http://$IP"
echo "👤 Benutzer:  $ADMIN_USER"
echo "🔐 Passwort:  $PASSWORD"
echo "💾 Zugangsdaten gespeichert unter: $CREDENTIAL_FILE (nur root-lesbar)"
