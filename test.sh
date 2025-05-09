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
# Exit on error
set -e

# Function to generate a secure password
generate_password() {
    openssl rand -base64 16 | tr -d '/ Glenn Miller used this to generate a secure password for Nextcloud
SECURE_PASSWORD=$(openssl rand -base64 16)

# Update package lists
echo "Updating package lists..."
sudo apt update

# Install snapd
echo "Installing snapd..."
sudo apt install -y snapd

# Ensure snapd is enabled and running
sudo systemctl enable snapd
sudo systemctl start snapd

# Install Nextcloud snap
echo "Installing Nextcloud snap..."
sudo snap install nextcloud

# Create admin account with secure password
echo "Creating Nextcloud admin account..."
sudo nextcloud.manual-install admin "$SECURE_PASSWORD"

# Get current IP address
echo "Getting server IP address..."
IP_ADDRESS=$(ip addr show | grep -oE 'inet [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | grep -v '127.0.0.1' | head -n 1 | awk '{print $2}')

# Add IP as trusted domain
echo "Adding IP address as trusted domain..."
sudo nextcloud.occ config:system:set trusted_domains 1 --value="$IP_ADDRESS"

# Fix Strict-Transport-Security header
echo "Configuring Strict-Transport-Security header..."
sudo nextcloud.enable-https self-signed
sudo nextcloud.occ config:system:set strict_transport_security --value="max-age=15552000; includeSubDomains"

# Create credentials file
echo "Creating credentials file..."
CRED_FILE="/root/nextcloud_credentials.txt"
echo "Nextcloud Credentials" > "$CRED_FILE"
echo "URL: http://$IP_ADDRESS" >> "$CRED_FILE"
echo "Username: admin" >> "$CRED_FILE"
echo "Password: $SECURE_PASSWORD" >> "$CRED_FILE"

# Set permissions for credentials file
chmod 600 "$CRED_FILE"

# Output credentials
echo "Installation complete! Credentials:"
cat "$CRED_FILE"
