#!/bin/bash
# Maintainer: @knilix
# Only test - Final Version!
# For Debian/Ubuntu & Alpine Linux
# V4.0.1
# Startscript: wget -q -P /opt/ https://github.com/knilix/testareaalpine/archive/refs/heads/main.zip && unzip /opt/main.zip -d /opt/scriptfiles && chmod 700 /opt/scriptfiles/testareaalpine-main/install_updatescript.sh
# Ausführbefehl (einmalig): cd && cd /opt/scriptfiles/testareaalpine-main && ./install_updatescript.sh

cd

#==============================================================================
# VORBEREITUNG: Ordnerstruktur und Basis-Setup
#==============================================================================

# Ordnerstruktur anlegen
mkdir -p /opt/scriptfiles

#==============================================================================
# UPDATESCRIPT ERSTELLEN: Haupt-Update-Logik
#==============================================================================

# Script-Header und Logging-Setup
echo '#!/bin/bash' | tee /opt/scriptfiles/updatescript.sh >/dev/null
echo 'LOG_DIR="/opt/scriptfiles/log"' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'mkdir -p "$LOG_DIR"' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'LOGFILE="$LOG_DIR/update_$(date +%Y-%m).log"' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') - Update gestartet" >> "$LOGFILE"' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null

# Kernel-Update Überwachung initialisieren
echo '# Flag für Kernel-Update' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'KERNEL_UPDATE=0' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'old_kernel=$(uname -r)' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null

# System-Updates: Paketmanager-spezifische Update-Logik
echo '# Check if running on Alpine, Debian, or Ubuntu' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'if command -v apk >/dev/null 2>&1; then' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    # Alpine Linux' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    apk update >/dev/null 2>&1' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    apk upgrade -a >/dev/null 2>&1' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    apk cache clean >/dev/null 2>&1' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') - System Updates beendet (Alpine)" >> "$LOGFILE"' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'elif command -v apt-get >/dev/null 2>&1; then' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    # Debian/Ubuntu' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    apt-get update >/dev/null 2>&1' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    apt-get upgrade -y >/dev/null 2>&1' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    apt-get autoremove -y >/dev/null 2>&1' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    apt-get autoclean >/dev/null 2>&1' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') - System Updates beendet (Debian/Ubuntu)" >> "$LOGFILE"' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'else' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') - Kein unterstütztes Paketmanagementsystem gefunden" >> "$LOGFILE"' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    exit 1' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'fi' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null

# Kernel-Update Erkennung
echo '# Prüfen, ob ein Kernel-Update installiert wurde' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'new_kernel=$(uname -r)' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'if [ "$old_kernel" != "$new_kernel" ]; then' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') - Kernel-Update installiert, Neustart wird durchgefuehrt" >> "$LOGFILE"' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') - Kernel-Update erkannt - Neustart erforderlich" >> "$LOGFILE"' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    KERNEL_UPDATE=1' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'else' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') - Kernel-Ueberpruefung beendet (kein Update)" >> "$LOGFILE"' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'fi' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null

# Docker-Compose Updates: Container-Updates verwalten
echo '# Update Docker-Compose if /opt/dockervolumes exists' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'if [ -d "/opt/dockervolumes" ] && command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') - Docker-Compose-Update gestartet" >> "$LOGFILE"' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    cd /opt/dockervolumes' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    readarray -d "" composeConfigs < <(find . -type f -name "docker-compose.y*" -print0)' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    if [ ${#composeConfigs[@]} -eq 0 ]; then' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '        echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') - Keine docker-compose.y* Dateien gefunden" >> "$LOGFILE"' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    else' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '        for cfg in "${composeConfigs[@]}"; do' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '            echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') - Docker-Compose Pull für $cfg durchgefuehrt" >> "$LOGFILE"' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '            docker compose -f "$cfg" pull >> "$LOGFILE" 2>&1 || echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') - Fehler beim Pull von $cfg" >> "$LOGFILE"' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '            docker compose -f "$cfg" up -d >> "$LOGFILE" 2>&1 || echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') - Fehler beim Up von $cfg" >> "$LOGFILE"' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '        done' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    fi' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    # Alte Images automatisch löschen' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    docker image prune -f >> "$LOGFILE" 2>&1 || echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') - Fehler beim Bereinigen alter Docker-Images" >> "$LOGFILE"' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') - Docker-Compose-Update abgeschlossen" >> "$LOGFILE"' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'elif [ -d "/opt/dockervolumes" ]; then' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') - Docker oder docker compose nicht verfügbar" >> "$LOGFILE"' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'else' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') - Docker Updates uebersprungen (Kein /opt/dockervolumes Verzeichnis)" >> "$LOGFILE"' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'fi' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null

# Wartung: Alte Logs und temporäre Dateien bereinigen
echo '# Delete log files older than 6 months' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'find "$LOG_DIR" -name "update_*.log" -mtime +180 -delete' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') - Log-Bereinigung beendet" >> "$LOGFILE"' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '# Log completion' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') - Update abgeschlossen" >> "$LOGFILE"' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '# Delete temporary installation files' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'rm -r /opt/scriptfiles/testareaalpine-main 2>/dev/null' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'rm /opt/main.zip 2>/dev/null' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'echo "$(date '\''+%Y-%m-%d %H:%M:%S'\'') - Temporaere Dateien bereinigt" >> "$LOGFILE"' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null

# Benutzer-Information: Status und Verwendungshinweise ausgeben
echo '# Final output' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'clear' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'echo ""' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'echo "================================================="' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'echo "           UPDATE ABGESCHLOSSEN"' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'echo "================================================="' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'echo ""' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'if [ $KERNEL_UPDATE -eq 1 ]; then' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo '    reboot' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null
echo 'fi' | tee -a /opt/scriptfiles/updatescript.sh >/dev/null

#==============================================================================
# FINALISIERUNG: Rechte setzen und Script ausführen
#==============================================================================

# Rechte setzen
chmod 700 /opt/scriptfiles/updatescript.sh

# Skript einmalig ausführen
cd /opt/scriptfiles
{
    if ! ./updatescript.sh; then
        echo "$(date): Fehler beim Ausführen von updatescript.sh (Exit-Code: $?)" >&2
    fi
}

#==============================================================================
# AUFRÄUMEN: Temporäre Dateien entfernen
#==============================================================================

# Temporäre Installationsdateien löschen
rm -r /opt/scriptfiles/testareaalpine-main 2>/dev/null
rm /opt/main.zip 2>/dev/null

#==============================================================================
# ABSCHLUSS: Benutzerinformation anzeigen
#==============================================================================

clear
echo ""
echo "================================================="
echo "        INSTALLATION ABGESCHLOSSEN"
echo "================================================="
echo ""
echo "✓ Das Updatescript wurde erstellt"
echo "✓ Nicht mehr benötigte Installationsdateien wurden gelöscht"
echo ""
echo "Für automatische Updates (täglich um 02:10 Uhr):"
echo "crontab -e"
echo "10 2 * * * /opt/scriptfiles/updatescript.sh >/dev/null 2>&1"
echo ""
echo "Manueller Startbefehl:"
echo "cd /opt/scriptfiles && ./updatescript.sh"
echo ""
