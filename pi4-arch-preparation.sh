cat > alarm-rpi4-prepare.sh << 'SCRIPTEOF'
#!/usr/bin/env bash
# Maintener: @knilix
# ============================================================
# Script 1: alarm-rpi4-prepare.sh
# Läuft auf dem Host-PC (Linux). Bereitet eine SD-Karte oder
# SSD für Arch Linux ARM auf dem Raspberry Pi 4 vor.
# Runs on the host PC (Linux). Prepares an SD card or
# SSD for Arch Linux ARM on the Raspberry Pi 4.
#
# Terminal-Pufferung automatisch beheben
if [[ -z "${STDBUF_WRAPPED:-}" ]]; then
    export STDBUF_WRAPPED=1
    exec stdbuf -o0 "$0" "$@"
fi
# ============================================================
set -euo pipefail

ALARM_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-aarch64-latest.tar.gz"
ALARM_FILE="ArchLinuxARM-rpi-aarch64-latest.tar.gz"
MOUNT_ROOT="/mnt/arch"
MOUNT_BOOT="${MOUNT_ROOT}/boot"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED} Dieses Script muss mit sudo oder als root ausgeführt werden.${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}=== Arch Linux ARM – Raspberry Pi 4 – Vorbereitung ===${NC}"
echo ""

echo -e "${YELLOW}Verfügbare Laufwerke:${NC}"
echo ""
lsblk -d -o NAME,SIZE,MODEL,TRAN | grep -v loop || true
echo ""

echo -n "Ziel-Laufwerk (z.B. sdb, nvme0n1): "
read -r TARGET
TARGET="/dev/${TARGET}"

if [[ ! -b "${TARGET}" ]]; then
    echo -e "${RED} ${TARGET} existiert nicht. Abbruch.${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}  ALLE DATEN AUF ${TARGET} WERDEN UNWIDERRUFLICH GELÖSCHT!${NC}"
echo -n "Fortfahren? (ja/Nein): "
read -r confirm
[[ "${confirm}" != "ja" ]] && { echo "Abgebrochen."; exit 0; }

if [[ "${TARGET}" == *"nvme"* ]]; then
    PART1="${TARGET}p1"; PART2="${TARGET}p2"
else
    PART1="${TARGET}1";  PART2="${TARGET}2"
fi

echo ""
echo -e "${GREEN}[1/8] Image herunterladen ...${NC}"
if [[ -f "${ALARM_FILE}" ]]; then
    echo -n "${ALARM_FILE} existiert bereits. Neu herunterladen? (j/N): "
    read -r redl
    [[ "${redl}" == "j" ]] && { rm -f "${ALARM_FILE}"; wget "${ALARM_URL}"; }
else
    wget "${ALARM_URL}"
fi

echo ""
echo -e "${GREEN}[2/8] Partitionstabelle bereinigen ...${NC}"
dd if=/dev/zero of="${TARGET}" bs=1M count=50 status=progress

echo ""
echo -e "${GREEN}[3/8] Partitionen anlegen ...${NC}"
sfdisk "${TARGET}" <<EOF
label: dos
size=256MiB, type=c
type=83
EOF
sleep 2
partprobe "${TARGET}" 2>/dev/null || true

echo ""
echo -e "${GREEN}[4/8] Dateisysteme erstellen ...${NC}"
mkfs.vfat -F 32 "${PART1}"
mkfs.ext4 -F "${PART2}"

echo ""
echo -e "${GREEN}[5/8] Partitionen mounten ...${NC}"
mkdir -p "${MOUNT_ROOT}"
mount "${PART2}" "${MOUNT_ROOT}"
mkdir -p "${MOUNT_BOOT}"
mount "${PART1}" "${MOUNT_BOOT}"

echo ""
echo -e "${GREEN}[6/8] Root-Dateisystem entpacken ...${NC}"
bsdtar -xpf "${ALARM_FILE}" -C "${MOUNT_ROOT}"
sync

echo ""
echo -e "${GREEN}[7/8] UUIDs auslesen und fstab/cmdline schreiben ...${NC}"
UUID_BOOT=$(blkid -s UUID -o value "${PART1}")
UUID_ROOT=$(blkid -s UUID -o value "${PART2}")
echo "  UUID Boot: ${UUID_BOOT}"
echo "  UUID Root: ${UUID_ROOT}"

cat > "${MOUNT_ROOT}/etc/fstab" <<EOF
UUID=${UUID_ROOT}  /       ext4    defaults        0       1
UUID=${UUID_BOOT}  /boot   vfat    defaults        0       2
EOF
echo "console=tty0 root=UUID=${UUID_ROOT} rw rootwait" > "${MOUNT_BOOT}/cmdline.txt"
echo -e "  ${GREEN} fstab und cmdline.txt geschrieben${NC}"

echo ""
echo -e "${GREEN}[8/8] Sauber aushängen ...${NC}"
sync
umount "${MOUNT_BOOT}"
umount "${MOUNT_ROOT}"

echo ""
echo -e "${GREEN}═══ Fertig! ═══${NC}"
echo -e "${YELLOW}SSD in den Pi 4 stecken, LAN an, Strom an.${NC}"
echo -e "${YELLOW}Danach Script 2 per SSH ausführen.${NC}"
SCRIPTEOF

chmod +x alarm-rpi4-prepare.sh
