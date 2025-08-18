#!/bin/bash
# Universelles automatisches Update für Docker-Compose Services
# Unterstützt: Alpine Linux, Debian, Ubuntu
# Dateipfad: ~/scriptfiles/updatescript.sh
# Logfile: /opt/scriptfiles/updatelog.txt

# Logging-Funktion mit monatlichen Log-Dateien
log_message() {
    local log_dir="/opt/scriptfiles/log"
    local current_month=$(date +%y-%m)
    local log_file="$log_dir/updatelog_$current_month.txt"
    
    # Erstelle Log-Verzeichnis falls nicht vorhanden
    mkdir -p "$log_dir"
    
    echo "$(date +%y-%m-%d_%H:%M:%S) - $1" | tee -a "$log_file"
}

# OS-Erkennung
detect_os() {
    if [ -f /etc/alpine-release ]; then
        echo "alpine"
    elif [ -f /etc/debian_version ]; then
        if grep -qi ubuntu /etc/os-release 2>/dev/null; then
            echo "ubuntu"
        else
            echo "debian"
        fi
    else
        echo "unknown"
    fi
}

# System-Update basierend auf OS
update_system() {
    local os_type=$1
    local kernel_update=0
    
    case $os_type in
        "alpine")
            log_message "Alpine Linux erkannt - führe apk update/upgrade durch"
            apk update || true
            apk upgrade || true
            # Kernel-Update-Check für Alpine
            if apk info -v | grep -q '^linux-lts\|^linux-virt'; then
                kernel_update=1
            fi
            ;;
        "debian"|"ubuntu")
            log_message "$os_type erkannt - führe apt update/upgrade durch"
            export DEBIAN_FRONTEND=noninteractive
            apt-get update || true
            apt-get upgrade -y || true
            apt-get autoremove -y || true
            apt-get autoclean || true
            # Kernel-Update-Check für Debian/Ubuntu
            if dpkg -l | grep -q "^ii.*linux-image.*$(uname -r)"; then
                # Prüfe ob ein neuerer Kernel verfügbar ist
                if apt list --upgradable 2>/dev/null | grep -q linux-image; then
                    kernel_update=1
                fi
            fi
            ;;
        *)
            log_message "Unbekanntes Betriebssystem - überspringe System-Update"
            ;;
    esac
    
    return $kernel_update
}

# Docker-Compose Services updaten
update_docker_services() {
    # Prüfe ob Docker-Volumes-Verzeichnis existiert
    if [ ! -d "/opt/dockervolumes" ]; then
        log_message "/opt/dockervolumes existiert nicht - überspringe Docker-Compose Updates"
        return
    fi
    
    log_message "Starte Docker-Compose Updates"
    
    # Wechsle in Docker-Volumes-Verzeichnis
    cd /opt/dockervolumes || {
        log_message "FEHLER: Kann nicht nach /opt/dockervolumes wechseln"
        return
    }
    
    # Finde alle docker-compose Dateien
    readarray -d '' composeConfigs < <(find . -type f \( -name "docker-compose.yml" -o -name "docker-compose.yaml" \) -print0)
    
    if [ ${#composeConfigs[@]} -eq 0 ]; then
        log_message "Keine docker-compose Dateien gefunden"
        return
    fi
    
    log_message "Gefundene docker-compose Dateien: ${#composeConfigs[@]}"
    
    for cfg in "${composeConfigs[@]}"; do
        log_message "Verarbeite: $cfg"
        
        # Pull neue Images
        timeout 600s docker compose -f "$cfg" pull || {
            log_message "WARNUNG: Pull fehlgeschlagen für $cfg"
            continue
        }
        
        # Starte Services neu
        timeout 600s docker compose -f "$cfg" up -d || {
            log_message "WARNUNG: Up fehlgeschlagen für $cfg"
            continue
        }
        
        # Health-Check für alle Services
        services=$(docker compose -f "$cfg" ps --services 2>/dev/null || true)
        if [ -n "$services" ]; then
            for service in $services; do
                log_message "Prüfe Health-Status für Service: $service"
                container_id=$(docker compose -f "$cfg" ps -q "$service" 2>/dev/null)
                
                if [ -n "$container_id" ]; then
                    # Warte bis zu 60 Sekunden auf healthy Status
                    for i in $(seq 1 12); do
                        health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_id" 2>/dev/null || echo "no-health-check")
                        
                        if [ "$health_status" = "healthy" ] || [ "$health_status" = "no-health-check" ]; then
                            log_message "Service $service ist bereit (Status: $health_status)"
                            break
                        elif [ "$health_status" = "unhealthy" ]; then
                            log_message "WARNUNG: Service $service ist unhealthy"
                            break
                        fi
                        
                        if [ $i -eq 12 ]; then
                            log_message "WARNUNG: Service $service wurde nicht rechtzeitig healthy"
                        fi
                        
                        sleep 5
                    done
                fi
            done
        fi
    done
}

# Cleanup
cleanup_docker() {
    log_message "Führe Docker-Cleanup durch"
    docker image prune -f || true
    docker container prune -f || true
    docker volume prune -f || true
    docker network prune -f || true
}

# Main Script
main() {
    log_message "=== Start Universal Docker Update Script ==="
    
    # OS erkennen
    OS_TYPE=$(detect_os)
    log_message "Erkanntes Betriebssystem: $OS_TYPE"
    
    # System-Update
    update_system "$OS_TYPE"
    KERNEL_UPDATE=$?
    
    # Docker-Services updaten
    update_docker_services
    
    # Cleanup
    cleanup_docker
    
    log_message "=== Docker Update Script beendet ==="
    
    # Neustart falls Kernel-Update
    if [ $KERNEL_UPDATE -eq 1 ]; then
        log_message "Kernel-Update erkannt - System wird neugestartet"
        sleep 5
        reboot
    fi
}

# Script ausführen
main "$@"

# Optional: Alte Log-Dateien bereinigen (älter als 12 Monate)
cleanup_old_logs() {
    local log_dir="/opt/scriptfiles/log"
    if [ -d "$log_dir" ]; then
        find "$log_dir" -name "updatelog_*.txt" -type f -mtime +365 -delete 2>/dev/null || true
    fi
}

# Cleanup alter Logs beim ersten Lauf des Monats
if [ "$(date +%d)" = "01" ]; then
    cleanup_old_logs
fi
