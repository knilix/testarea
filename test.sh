#!/bin/bash
#
# Maintainer: @knilix
# Version: 1.0
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

# Color codes for better readability
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print colored messages
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Display introduction and ask for confirmation
echo "============================================================="
echo "               Nextcloud Docker Installer                     "
echo "============================================================="
echo ""
echo "This script will install Nextcloud with Nginx, MariaDB, and Redis"
echo "using Docker Compose on your Debian/Ubuntu system."
echo ""
echo "It will:"
echo "  - Install Docker and Docker Compose if not already installed"
echo "  - Set up a complete Nextcloud environment with all components"
echo "  - Configure SSL for secure access"
echo "  - Generate secure random passwords"
echo "  - Provide a management script for maintenance"
echo ""
echo "Press Enter to continue or Ctrl+C to abort..."
read -r

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root. Please use sudo or run as root."
fi

# Check if the system is Debian or Ubuntu
if ! grep -E "Debian|Ubuntu" /etc/issue &> /dev/null && ! grep -E "Debian|Ubuntu" /etc/os-release &> /dev/null; then
    error "This script is designed for Debian or Ubuntu systems only."
fi

# Create installation directory
INSTALL_DIR="/opt/nextcloud-docker"
info "Creating installation directory at $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Check for required utilities and install if needed
info "Checking and installing required dependencies..."

# Check and install Docker if not present
if ! command -v docker &> /dev/null; then
    warn "Docker is not installed. Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    
    # Add current user to docker group
    usermod -aG docker $USER
    
    # Verify Docker installation
    if ! command -v docker &> /dev/null; then
        error "Docker installation failed. Please install Docker manually and try again."
    fi
    info "Docker has been installed successfully."
else
    info "Docker is already installed."
fi

# Check for and install other required utilities
for cmd in curl openssl; do
    if ! command -v $cmd &> /dev/null; then
        warn "$cmd is not installed. Installing..."
        apt-get update
        apt-get install -y $cmd
    fi
done

# Check if Docker Compose is installed
if ! command -v docker compose &> /dev/null; then
    warn "Docker Compose is not available. Installing Docker Compose..."
    
    # For newer Docker versions, Compose is included as docker compose
    if docker compose version &> /dev/null; then
        info "Docker Compose plugin is already installed."
    else
        apt-get update
        apt-get install -y docker-compose-plugin
        
        # Verify Docker Compose installation
        if ! docker compose version &> /dev/null; then
            warn "Docker Compose plugin installation might have failed. Trying alternative method..."
            apt-get install -y docker-compose
        fi
    fi
    
    # Final verification
    if ! (docker compose version &> /dev/null || command -v docker-compose &> /dev/null); then
        error "Docker Compose installation failed. Please install Docker Compose manually and try again."
    fi
    info "Docker Compose has been installed successfully."
else
    info "Docker Compose is already installed."
fi

# Generate random passwords
DB_ROOT_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
DB_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
NEXTCLOUD_ADMIN_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
NEXTCLOUD_ADMIN_USER="admin"

# Get server IP address automatically
SERVER_IP=$(hostname -I | awk '{print $1}')

# Get server domain/IP
echo ""
read -p "Enter your server domain (or press Enter to use IP address $SERVER_IP): " SERVER_DOMAIN
if [ -z "$SERVER_DOMAIN" ]; then
    SERVER_DOMAIN="$SERVER_IP"
    info "Using IP address: $SERVER_DOMAIN"
fi

# Ask for email for Let's Encrypt (optional)
echo ""
read -p "Enter your email for Let's Encrypt certificate (optional, press Enter to use self-signed): " EMAIL
USE_LETSENCRYPT=false
if [ -n "$EMAIL" ]; then
    # Check if the domain is an IP address
    if [[ "$SERVER_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        warn "Let's Encrypt requires a domain name, not an IP address. Reverting to self-signed certificates."
    else
        USE_LETSENCRYPT=true
        info "Will use Let's Encrypt with email: $EMAIL"
    fi
else
    info "Will use self-signed certificates."
fi

# Create SSL certificates directory
mkdir -p "$INSTALL_DIR/ssl"

# Generate SSL certificates (self-signed or Let's Encrypt)
if [ "$USE_LETSENCRYPT" = true ]; then
    info "Setting up Let's Encrypt certificates..."
    
    # Install certbot if not present
    if ! command -v certbot &> /dev/null; then
        apt-get update
        apt-get install -y certbot
    fi
    
    # Create a temporary nginx config for certbot
    mkdir -p "$INSTALL_DIR/letsencrypt"
    mkdir -p "$INSTALL_DIR/letsencrypt-www"
    
    cat > "$INSTALL_DIR/nginx-certbot.conf" << EOF
server {
    listen 80;
    server_name $SERVER_DOMAIN;
    
    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF

    # Start a temporary nginx for certbot verification
    docker run --name certbot-nginx -v "$INSTALL_DIR/nginx-certbot.conf:/etc/nginx/conf.d/default.conf:ro" \
        -v "$INSTALL_DIR/letsencrypt-www:/var/www/letsencrypt" \
        -p 80:80 -d nginx:alpine
    
    # Wait for nginx to start
    sleep 5
    
    # Get certificate
    certbot certonly --webroot -w "$INSTALL_DIR/letsencrypt-www" -d "$SERVER_DOMAIN" --email "$EMAIL" --agree-tos --non-interactive
    
    # Copy certificates
    cp /etc/letsencrypt/live/$SERVER_DOMAIN/fullchain.pem "$INSTALL_DIR/ssl/nginx.crt"
    cp /etc/letsencrypt/live/$SERVER_DOMAIN/privkey.pem "$INSTALL_DIR/ssl/nginx.key"
    
    # Stop and remove temporary nginx
    docker stop certbot-nginx
    docker rm certbot-nginx
    
    # Clean up temporary files
    rm -f "$INSTALL_DIR/nginx-certbot.conf"
    
    # Create renewal hook
    mkdir -p /etc/letsencrypt/renewal-hooks/post
    cat > /etc/letsencrypt/renewal-hooks/post/nextcloud-copy.sh << EOF
#!/bin/bash
cp /etc/letsencrypt/live/$SERVER_DOMAIN/fullchain.pem "$INSTALL_DIR/ssl/nginx.crt"
cp /etc/letsencrypt/live/$SERVER_DOMAIN/privkey.pem "$INSTALL_DIR/ssl/nginx.key"
docker compose -f "$INSTALL_DIR/docker-compose.yml" restart web
EOF
    chmod +x /etc/letsencrypt/renewal-hooks/post/nextcloud-copy.sh
    
    # Add certbot renewal to crontab
    (crontab -l 2>/dev/null || echo "") | grep -v "certbot renew" | { cat; echo "0 3 * * * certbot renew --quiet"; } | crontab -
    
    info "Let's Encrypt certificates have been set up and renewal configured."
else
    # Generate self-signed SSL certificate
    info "Generating self-signed SSL certificate..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
        -keyout "$INSTALL_DIR/ssl/nginx.key" \
        -out "$INSTALL_DIR/ssl/nginx.crt" \
        -subj "/CN=$SERVER_DOMAIN" \
        -addext "subjectAltName=DNS:$SERVER_DOMAIN,IP:$(hostname -I | awk '{print $1}')"
fi

# Set proper permissions for SSL files
chmod 600 "$INSTALL_DIR/ssl/nginx.key"
chmod 644 "$INSTALL_DIR/ssl/nginx.crt"

# Create directories for data persistence
mkdir -p "$INSTALL_DIR/data"
mkdir -p "$INSTALL_DIR/db"
mkdir -p "$INSTALL_DIR/config"
mkdir -p "$INSTALL_DIR/nginx"

# Create custom PHP config
mkdir -p "$INSTALL_DIR/php"
cat > "$INSTALL_DIR/php/custom.ini" << EOF
memory_limit = 512M
upload_max_filesize = 50G
post_max_size = 500M
max_execution_time = 300
date.timezone = Europe/Berlin
opcache.enable=1
opcache.interned_strings_buffer=32
opcache.max_accelerated_files=10000
opcache.memory_consumption=128
opcache.save_comments=1
opcache.revalidate_freq=1
EOF

# Create Nginx configuration
cat > "$INSTALL_DIR/nginx/nginx.conf" << EOF
worker_processes auto;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;
    keepalive_timeout  65;
    types_hash_max_size 2048;
    server_tokens off;
    
    client_max_body_size 500M;

    gzip  on;
    gzip_comp_level 5;
    gzip_min_length 256;
    gzip_proxied any;
    gzip_vary on;
    gzip_types
        application/atom+xml
        application/javascript
        application/json
        application/ld+json
        application/manifest+json
        application/rss+xml
        application/vnd.geo+json
        application/vnd.ms-fontobject
        application/x-font-ttf
        application/x-web-app-manifest+json
        application/xhtml+xml
        application/xml
        font/opentype
        image/bmp
        image/svg+xml
        image/x-icon
        text/cache-manifest
        text/css
        text/plain
        text/vcard
        text/vnd.rim.location.xloc
        text/vtt
        text/x-component
        text/x-cross-domain-policy;

    include /etc/nginx/conf.d/*.conf;
}
EOF

# Create Nginx site configuration
cat > "$INSTALL_DIR/nginx/default.conf" << EOF
upstream php-handler {
    server app:9000;
}

server {
    listen 80;
    listen [::]:80;
    server_name $SERVER_DOMAIN;
    
    # Redirect all HTTP requests to HTTPS
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $SERVER_DOMAIN;

    ssl_certificate /etc/nginx/ssl/nginx.crt;
    ssl_certificate_key /etc/nginx/ssl/nginx.key;

    # Modern SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    
    # OCSP Stapling
    ssl_stapling off;
    ssl_stapling_verify off;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    # Root directory
    root /var/www/html;

    # Set index files
    index index.php index.html index.htm;

    # Optimize asset delivery
    location ~* \.(?:css|js|woff|svg|gif|png|jpg|jpeg|webp|avif|ico|cur|heic|webm|mp4|mov|ogg|mp3|wav)$ {
        expires 7d;
        access_log off;
        add_header Cache-Control "public";
    }

    # Deny access to sensitive files
    location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console) {
        deny all;
    }

    # Nextcloud .well-known URLs
    location ^~ /.well-known {
        location = /.well-known/carddav { return 301 /remote.php/dav/; }
        location = /.well-known/caldav  { return 301 /remote.php/dav/; }
        location ^~ /.well-known/acme-challenge { try_files \$uri \$uri/ =404; }
        try_files \$uri \$uri/ =404;
    }

    # Handle PHP
    location ~ \\.php$ {
        fastcgi_split_path_info ^(.+?\\.php)(\\/.*)$;
        set \$path_info \$fastcgi_path_info;
        try_files \$fastcgi_script_name =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$path_info;
        fastcgi_param HTTPS on;
        fastcgi_param modHeadersAvailable true;
        fastcgi_param front_controller_active true;
        fastcgi_pass php-handler;
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
        fastcgi_read_timeout 3600;
        fastcgi_send_timeout 3600;
        fastcgi_connect_timeout 3600;
    }

    # Main Nextcloud routing
    location / {
        try_files \$uri \$uri/ /index.php\$query_string;
        rewrite ^/\\.well-known/host-meta /public.php?service=host-meta last;
        rewrite ^/\\.well-known/host-meta.json /public.php?service=host-meta-json last;

        # The following rules are only needed with webfinger
        rewrite ^/\\.well-known/webfinger /public.php?service=webfinger last;
    }

    # Prevent Clients from accessing hidden files
    location ~ /\\. {
        deny all;
    }

    # Prevent access to certain directories
    location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:$|/) {
        deny all;
    }

    # Prevent browser access to JSON API
    location ~ ^/(?:index|remote|public|cron|core/ajax/update|status|ocs/v[12]|updater/.+|oc[ms]-provider/.+)\\.php(?:$|/) {
        fastcgi_split_path_info ^(.+?\\.php)(\\/.*)$;
        set \$path_info \$fastcgi_path_info;
        try_files \$fastcgi_script_name =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$path_info;
        fastcgi_param HTTPS on;
        fastcgi_param modHeadersAvailable true;
        fastcgi_param front_controller_active true;
        fastcgi_pass php-handler;
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
        fastcgi_read_timeout 3600;
        fastcgi_send_timeout 3600;
        fastcgi_connect_timeout 3600;
    }

    # Enable DAV for CalDAV/CardDAV
    location ~ ^/(?:updater|oc[ms]-provider)(?:$|/) {
        try_files \$uri \$uri/ =404;
        index index.php;
    }

    # Allow DAV
    location ~ ^/remote(\\.php)(?:$|/) {
        fastcgi_split_path_info ^(.+?\\.php)(\\/.*)$;
        set \$path_info \$fastcgi_path_info;
        try_files \$fastcgi_script_name =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$path_info;
        fastcgi_param HTTPS on;
        fastcgi_param modHeadersAvailable true;
        fastcgi_param front_controller_active true;
        fastcgi_pass php-handler;
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
        fastcgi_read_timeout 3600;
        fastcgi_send_timeout 3600;
        fastcgi_connect_timeout 3600;
    }

    # Serve static files directly
    location ~* ^/(?:updater|oc[ms]-provider)(?:$|/) {
        try_files \$uri/ =404;
        index index.php;
    }
}
EOF

# Create Docker Compose configuration file
cat > "$INSTALL_DIR/docker-compose.yml" << EOF
services:
  db:
    image: mariadb:10.6
    container_name: nextcloud-mariadb
    command: --transaction-isolation=READ-COMMITTED --log-bin=binlog --binlog-format=ROW
    volumes:
      - ./db:/var/lib/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=$DB_ROOT_PASSWORD
      - MYSQL_PASSWORD=$DB_PASSWORD
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
    restart: unless-stopped
    networks:
      - nextcloud_network

  redis:
    image: redis:alpine
    container_name: nextcloud-redis
    restart: unless-stopped
    networks:
      - nextcloud_network

  app:
    image: nextcloud:fpm-alpine
    container_name: nextcloud-app
    volumes:
      - ./data:/var/www/html
      - ./php/custom.ini:/usr/local/etc/php/conf.d/custom.ini
    environment:
      - MYSQL_HOST=db
      - MYSQL_PASSWORD=$DB_PASSWORD
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
      - REDIS_HOST=redis
      - NEXTCLOUD_ADMIN_USER=$NEXTCLOUD_ADMIN_USER
      - NEXTCLOUD_ADMIN_PASSWORD=$NEXTCLOUD_ADMIN_PASSWORD
      - NEXTCLOUD_TRUSTED_DOMAINS=$SERVER_DOMAIN localhost
    depends_on:
      - db
      - redis
    restart: unless-stopped
    networks:
      - nextcloud_network

  web:
    image: nginx:alpine
    container_name: nextcloud-nginx
    ports:
      - 80:80
      - 443:443
    volumes:
      - ./data:/var/www/html:ro
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
    depends_on:
      - app
    restart: unless-stopped
    networks:
      - nextcloud_network

networks:
  nextcloud_network:
    driver: bridge

EOF

# Save configuration info in a file
cat > "$INSTALL_DIR/credentials.txt" << EOF
Nextcloud Installation Information
=================================
Installation Directory: $INSTALL_DIR
Server Domain/IP: $SERVER_DOMAIN
Date Installed: $(date)

Database Information
-------------------
Database: nextcloud
Database User: nextcloud
Database Password: $DB_PASSWORD
Root Password: $DB_ROOT_PASSWORD

Nextcloud Admin Credentials
--------------------------
Username: $NEXTCLOUD_ADMIN_USER
Password: $NEXTCLOUD_ADMIN_PASSWORD

Note: Keep this file secure or delete it after saving the credentials elsewhere.
EOF

# Set proper permissions for the credentials file - only root can access
chmod 600 "$INSTALL_DIR/credentials.txt"
chown root:root "$INSTALL_DIR/credentials.txt"

# Create a management script
cat > "$INSTALL_DIR/nextcloud-manager.sh" << EOF
#!/bin/bash

# Nextcloud Docker Manager Script
INSTALL_DIR="$INSTALL_DIR"
cd "\$INSTALL_DIR"

case "\$1" in
    start)
        echo "Starting Nextcloud..."
        docker compose up -d
        ;;
    stop)
        echo "Stopping Nextcloud..."
        docker compose down
        ;;
    restart)
        echo "Restarting Nextcloud..."
        docker compose restart
        ;;
    status)
        echo "Nextcloud container status:"
        docker compose ps
        ;;
    logs)
        if [ -z "\$2" ]; then
            docker compose logs --tail=100
        else
            docker compose logs --tail=100 "\$2"
        fi
        ;;
    update)
        echo "Updating Nextcloud containers..."
        docker compose pull
        docker compose down
        docker compose up -d
        ;;
    backup)
        BACKUP_DIR="\${2:-/backup}"
        BACKUP_FILE="\$BACKUP_DIR/nextcloud-backup-\$(date +%Y%m%d%H%M%S).tar.gz"
        mkdir -p "\$BACKUP_DIR"
        echo "Backing up Nextcloud to \$BACKUP_FILE..."
        docker compose down
        tar -czf "\$BACKUP_FILE" -C "\$INSTALL_DIR" data db config ssl credentials.txt docker-compose.yml
        docker compose up -d
        echo "Backup completed: \$BACKUP_FILE"
        ;;
    creds)
        # Check if user is root
        if [ "$(id -u)" -ne 0 ]; then
            echo "Error: This command requires root privileges."
            exit 1
        fi
        cat "\$INSTALL_DIR/credentials.txt"
        ;;
    ssl-status)
        if [ -f "\$INSTALL_DIR/ssl/nginx.crt" ]; then
            echo "SSL Certificate Information:"
            openssl x509 -in "\$INSTALL_DIR/ssl/nginx.crt" -text -noout | grep -E 'Subject:|Issuer:|Not Before:|Not After :|DNS:|IP Address:'
        else
            echo "SSL certificate not found."
        fi
        ;;
    renew-ssl)
        if [ -f "/etc/letsencrypt/renewal-hooks/post/nextcloud-copy.sh" ]; then
            echo "Renewing Let's Encrypt certificate..."
            certbot renew
        else
            echo "Let's Encrypt certificate not found. This command only works with Let's Encrypt certificates."
        fi
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status|logs|update|backup|creds|ssl-status|renew-ssl}"
        echo ""
        echo "  start      - Start Nextcloud containers"
        echo "  stop       - Stop Nextcloud containers"
        echo "  restart    - Restart Nextcloud containers"
        echo "  status     - Show container status"
        echo "  logs       - Show logs (optionally specify container name)"
        echo "  update     - Update and restart containers"
        echo "  backup     - Backup Nextcloud (optionally specify backup directory)"
        echo "  creds      - Show stored credentials (requires root)"
        echo "  ssl-status - Show SSL certificate information"
        echo "  renew-ssl  - Force renewal of Let's Encrypt certificate"
        exit 1
        ;;
esac
EOF

# Make the management script executable
chmod +x "$INSTALL_DIR/nextcloud-manager.sh"

# Create symlink for the manager script
ln -sf "$INSTALL_DIR/nextcloud-manager.sh" /usr/local/bin/nextcloud-manager

# Start Docker Compose
info "Starting Nextcloud with Docker Compose..."
cd "$INSTALL_DIR"
docker compose up -d

# Check if containers are running
if [ "$(docker compose ps -q | wc -l)" -eq 4 ]; then
    info "All containers started successfully!"
else
    warn "Some containers may not have started. Please check with 'nextcloud-manager status'"
fi

# Configure Nextcloud with additional settings
info "Configuring Nextcloud with additional settings..."
sleep 10 # Wait for Nextcloud to initialize

# Create a script to add custom configurations
cat > "$INSTALL_DIR/configure_nextcloud.php" << 'EOF'
<?php
$configFile = '/var/www/html/config/config.php';
if (file_exists($configFile)) {
    $config = include($configFile);
    
    // Add custom configurations
    $config['default_phone_region'] = 'DE';
    $config['enable_previews'] = true;
    $config['enabledPreviewProviders'] = [
        'OC\\Preview\\PNG',
        'OC\\Preview\\JPEG',
        'OC\\Preview\\GIF',
        'OC\\Preview\\BMP',
        'OC\\Preview\\XBitmap',
        'OC\\Preview\\MP3',
        'OC\\Preview\\TXT',
        'OC\\Preview\\MarkDown',
        'OC\\Preview\\OpenDocument',
        'OC\\Preview\\Krita',
        'OC\\Preview\\HEIC',
    ];
    $config['maintenance_window_start'] = 1;
    
    // Write back the configuration
    $content = "<?php\nreturn " . var_export($config, true) . ";\n";
    file_put_contents($configFile, $content);
    echo "Nextcloud configuration updated successfully.\n";
} else {
    echo "Nextcloud config file not found.\n";
}
EOF

# Execute the PHP script inside the Nextcloud container
docker compose exec -T app php /var/www/html/configure_nextcloud.php || warn "Could not configure Nextcloud settings. Will try again later."

# Remove the temporary script
rm "$INSTALL_DIR/configure_nextcloud.php"

# Print success message
echo ""
echo "=================================================================="
info "Nextcloud installation completed successfully!"
echo "=================================================================="
echo ""
echo "Access your Nextcloud instance at: https://$SERVER_DOMAIN"
echo ""
echo "Admin credentials:"
echo "  Username: $NEXTCLOUD_ADMIN_USER"
echo "  Password: $NEXTCLOUD_ADMIN_PASSWORD"
echo ""
echo "Database credentials:"
echo "  Database: nextcloud"
echo "  Username: nextcloud"
echo "  Password: $DB_PASSWORD"
echo "  Root Password: $DB_ROOT_PASSWORD"
echo ""
echo "All credentials are saved in: $INSTALL_DIR/credentials.txt"
echo ""
echo "The management script has been installed. Use it with:"
echo "  nextcloud-manager {start|stop|restart|status|logs|update|backup|creds}"
echo ""

if [ "$USE_LETSENCRYPT" = true ]; then
    info "Let's Encrypt SSL certificates are installed and will auto-renew."
else
    warn "Since you're using a self-signed certificate, your browser will show a security warning."
    warn "You can either accept this warning or replace the certificates with valid ones."
fi

echo "=================================================================="

# Clean up any temporary files
rm -rf /opt/scriptfiles/testarea-main /opt/main.zip 2>/dev/null || true
