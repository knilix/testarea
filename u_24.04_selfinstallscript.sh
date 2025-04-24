#!/bin/bash
# Maintener: @knilix
# Only test
# Startscript: wget -q -P /opt/ https://github.com/knilix/testarea/archive/refs/heads/main.zip && unzip /opt/main.zip -d /opt/scriptfiles && chmod 700 /opt/scriptfiles/testarea-main/u_24.04_selfinstallscript.sh
# Ausführbefehl (einmalig): cd /opt/scriptfiles/testarea-main && ./u_24.04_selfinstallscript.sh



#
rm -r /opt/scriptfiles/testarea-main
rm /opt/main.zip
#
clear
echo #
echo #
echo "- Das Script wurde ausgeführt"
echo "- Nicht mehr benötigte Installationsdateien wieder gelöscht"
echo #
