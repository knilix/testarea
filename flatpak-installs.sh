#!/bin/bash
# Maintener: @knilix
# Only test
#
# root user required (su)
#
# 1. Architektur prüfen
#!/bin/bash

# 1. Architektur prüfen
ARCH=$(uname -m)
if [[ "$ARCH" != "x86_64" ]]; then
  echo "Nur x64-Architekturen werden unterstützt (aktuell: $ARCH)."
  exit 1
fi

# 2. Distribution erkennen
if [ -f /etc/os-release ]; then
  . /etc/os-release
  DISTRO=$ID
else
  echo "Konnte die Distribution nicht erkennen."
  exit 1
fi

# 3. Paketmanager und Befehle bestimmen
case "$DISTRO" in
  debian|ubuntu)
    PM_UPDATE="apt update -y"
    PM_INSTALL="apt install -y"
    PM_QUERY="dpkg-query -W -f='\${Status}'"
    CHECK_INSTALLED_STATUS="install ok installed"
    FLATPAK_INSTALL="apt install flatpak -y"
    ;;
  arch)
    PM_UPDATE="pacman -Sy --noconfirm"
    PM_INSTALL="pacman -S --noconfirm"
    PM_QUERY="pacman -Q"
    CHECK_INSTALLED_STATUS=""
    FLATPAK_INSTALL="sudo pacman -S flatpak"
    ;;
  fedora)
    PM_UPDATE="dnf makecache"
    PM_INSTALL="dnf install -y"
    PM_QUERY="rpm -q"
    CHECK_INSTALLED_STATUS=""
    FLATPAK_INSTALL="dnf install flatpak -y"
    ;;
  alpine)
    PM_UPDATE="apk update"
    PM_INSTALL="apk add"
    PM_QUERY="apk info -e"
    CHECK_INSTALLED_STATUS=""
    FLATPAK_INSTALL="apk add flatpak"
    ;;
  *)
    echo "Distribution $DISTRO wird nicht unterstützt."
    exit 1
    ;;
esac

# 4. Paketmanager Existenz prüfen
PM_BIN=$(echo "$PM_INSTALL" | awk '{print $1}')
if ! command -v "$PM_BIN" >/dev/null 2>&1; then
  echo "Paketmanager $PM_BIN ist nicht vorhanden. Skript abgebrochen."
  exit 1
fi

# 5. Listen für Zusammenfassung
installed_packages=()
skipped_packages=()
failed_packages=()

# 6. Paketquellen updaten
echo "Update der Paketquellen..."
eval "$PM_UPDATE"

# 7. Pakete einzeln prüfen und installieren
for PACKAGE in "$@"; do
  echo -n "Prüfe Paket $PACKAGE... "
  
  if [[ "$DISTRO" == "debian" || "$DISTRO" == "ubuntu" ]]; then
    STATUS=$($PM_QUERY "$PACKAGE" 2>/dev/null || true)
    if [[ "$STATUS" == "$CHECK_INSTALLED_STATUS" ]]; then
      echo "bereits installiert. Überspringe."
      skipped_packages+=("$PACKAGE")
      continue
    fi
  else
    if $PM_QUERY "$PACKAGE" >/dev/null 2>&1; then
      echo "bereits installiert. Überspringe."
      skipped_packages+=("$PACKAGE")
      continue
    fi
  fi

  echo "nicht installiert. Installiere..."
  if eval "$PM_INSTALL $PACKAGE"; then
    echo "$PACKAGE erfolgreich installiert."
    installed_packages+=("$PACKAGE")
  else
    echo "Fehler beim Installieren von $PACKAGE."
    failed_packages+=("$PACKAGE")
  fi
done

# 8. Flatpak prüfen und installieren
echo -n "Prüfe und installiere Flatpak... "
if ! command -v flatpak >/dev/null 2>&1; then
  echo "Flatpak ist nicht installiert. Installiere..."
  eval "$FLATPAK_INSTALL"
else
  echo "Flatpak ist bereits installiert."
fi

# 9. Zusammenfassung
echo
echo "=== Zusammenfassung ==="
echo "Installiert: ${#installed_packages[@]}"
if [ ${#installed_packages[@]} -gt 0 ]; then
  echo " -> ${installed_packages[*]}"
fi
echo "Übersprungen (bereits installiert): ${#skipped_packages[@]}"
if [ ${#skipped_packages[@]} -gt 0 ]; then
  echo " -> ${skipped_packages[*]}"
fi
echo "Fehlgeschlagen: ${#failed_packages[@]}"
if [ ${#failed_packages[@]} -gt 0 ]; then
  echo " -> ${failed_packages[*]}"
fi
echo "========================"

# 10. Flatpak Remote und Flatpak-Anwendungen installieren
echo
if command -v flatpak >/dev/null 2>&1; then
  echo "Füge Flathub-Remote hinzu (falls noch nicht vorhanden)..."
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

  echo "Installiere Flatpak-Anwendungen..."
  flatpak install -y flathub org.gimp.GIMP \
                      flathub com.abisource.AbiWord \
                      flathub org.blender.Blender \
                      flathub net.lutris.Lutris \
                      flathub org.kde.kdenlive \
                      flathub com.obsproject.Studio \
                      flathub org.feichtmeier.Musicpod \
                      flathub sa.sy.bluerecorder \
                      flathub org.flameshot.Flameshot \
                      flathub com.usebottles.bottles
else
  echo "Flatpak konnte nicht installiert werden oder ist nicht verfügbar. Überspringe Flatpak-Anwendungen."
fi

exit 0
#
# Clean up the installation files
rm -r /opt/scriptfiles/testarea-main
rm /opt/main.zip
#
clear
echo #
echo #
echo "- The script has been executed"
echo "- Installation files that are no longer required deleted"
echo "- Reboot system now!"
echo #
echo "- Das Script wurde ausgeführt"
echo "- Nicht mehr benötigte Installationsdateien wieder gelöscht"
echo "- System jetzt neu starten!"
echo #
