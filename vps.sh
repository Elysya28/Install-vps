#!/bin/bash

# Constants
CONFIG_DIR="/etc/data"
LOG_FILE="/root/log-install.txt"
SUPPORTED_OS=("debian:11" "debian:12" "ubuntu:20.04" "ubuntu:22.04" "ubuntu:24.04")
DOMAIN_FILE="$CONFIG_DIR/domain"
USERPANEL_FILE="$CONFIG_DIR/userpanel"
PASSPANEL_FILE="$CONFIG_DIR/passpanel"
MARZBAN_DIR="/opt/marzban"
# Menambahkan konstanta untuk sertifikat dan perintah reload
CERT_FILE="/var/lib/marzban/xray.crt"
KEY_FILE="/var/lib/marzban/xray.key"
RELOAD_CMD="marzban restart"

# Colorized echo function
colorized_echo() {
    local color=$1
    local text=$2
    case $color in
        "red")    printf "\e[91m%s\e[0m\n" "$text";;
        "green")  printf "\e[92m%s\e[0m\n" "$text";;
        "yellow") printf "\e[93m%s\e[0m\n" "$text";;
        "blue")   printf "\e[94m%s\e[0m\n" "$text";;
        "magenta") printf "\e[95m%s\e[0m\n" "$text";;
        "cyan")   printf "\e[96m%s\e[0m\n" "$text";;
        *)        echo "$text";;
    esac
}

# Logging function
log() {
    local level=$1
    local message=$2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
    colorized_echo "$level" "$message"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log red "Error: This script must be run as root."
        exit 1
    fi
}

# Check supported OS
check_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        os_key="${ID}:${VERSION_ID}"
        for supported in "${SUPPORTED_OS[@]}"; do
            if [[ "$os_key" == "$supported" ]]; then
                return 0
            fi
        done
    fi
    log red "Error: This script only supports Debian 11/12 and Ubuntu 20.04/22.04/24.04."
    exit 1
}

# Validate domain
validate_domain() {
    local domain=$1
    if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log red "Error: Invalid domain format."
        return 1
    fi
    return 0
}

# Validate email
validate_email() {
    local email=$1
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log red "Error: Invalid email format."
        return 1
    fi
    return 0
}

# Validate userpanel
validate_userpanel() {
    local userpanel=$1
    if [[ ! "$userpanel" =~ ^[A-Za-z0-9]+$ ]]; then
        log red "Error: UsernamePanel must contain only letters and numbers."
        return 1
    elif [[ "$userpanel" =~ [Aa][Dd][Mm][Ii][Nn] ]]; then
        log red "Error: UsernamePanel cannot contain 'admin'."
        return 1
    fi
    return 0
}

# Install packages
install_packages() {
    log blue "Updating package lists..."
    apt-get update -y || { log red "Failed to update package lists."; exit 1; }
    
    log blue "Installing required packages..."
    apt-get install -y sudo curl socat xz-utils apt-transport-https gnupg gnupg2 gnupg1 dnsutils lsb-release cron bash-completion || { log red "Failed to install required packages."; exit 1; }
    
    log blue "Removing unused packages..."
    apt-get -y --purge remove samba* apache2* sendmail* bind9* > /dev/null 2>&1 || { log yellow "Could not remove some unused packages."; }
    
    log blue "Installing toolkit packages..."
    apt-get install -y libio-socket-inet6-perl libsocket6-perl libcrypt-ssleay-perl \
        libnet-libidn-perl libio-socket-ssl-perl libwww-perl libpcre3 libpcre3-dev \
        zlib1g-dev dbus iftop zip unzip wget net-tools curl nano sed screen \
        build-essential dirmngr sudo at htop vnstat iptables bsdmainutils cron lsof lnav || { log red "Failed to install toolkit packages."; exit 1; }
    
    # Install speedtest
    log blue "Installing speedtest..."
    wget -q https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz || { log red "Failed to download speedtest."; exit 1; }
    tar xzf ookla-speedtest-1.2.0-linux-x86_64.tgz > /dev/null 2>&1 || { log red "Failed to extract speedtest."; exit 1; }
    mv speedtest /usr/bin || { log red "Failed to install speedtest."; exit 1; }
    rm -f ookla-speedtest-1.2.0-linux-x86_64.tgz speedtest.* > /dev/null 2>&1
}

# Configure BBR
configure_bbr() {
    log blue "Configuring BBR..."
    cat <<EOF >> /etc/sysctl.conf
fs.file-max = 500000
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 4096
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mem = 25600 51200 102400
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.core.rmem_max = 4000000
net.ipv4.tcp_mtu_probing = 1
net.ipv4.ip_forward = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
    sysctl -p || { log red "Failed to apply sysctl settings."; exit 1; }
}

# Main installation
main() {
    clear
    check_root
    check_os
    
    mkdir -p "$CONFIG_DIR"
    touch "$LOG_FILE"
    
    # Get user inputs
    while true; do
        read -rp "Enter Domain: " domain
        validate_domain "$domain" && break
    done
    echo "$domain" > "$DOMAIN_FILE"
    
    while true; do
        read -rp "Enter your Email: " email
        validate_email "$email" && break
    done
    
    while true; do
        read -rp "Enter UsernamePanel (letters and numbers only): " userpanel
        validate_userpanel "$userpanel" && break
    done
    echo "$userpanel" > "$USERPANEL_FILE"
    
    read -rp "Enter Password Panel: " passpanel
    echo "$passpanel" > "$PASSPANEL_FILE"
    
    # Preparation
    clear
    cd
    
    install_packages
    configure_bbr
    
    # Set timezone
    log blue "Setting timezone to Asia/Jakarta..."
    timedatectl set-timezone Asia/Jakarta || { log red "Failed to set timezone."; exit 1; }
    
    # Install Marzban
    log blue "Installing Marzban..."
    bash -c "$(curl -sL https://raw.githubusercontent.com/Gozargah/Marzban-scripts/master/marzban.sh)" @ install
    
    # Configure Marzban components
    log blue "Configuring Marzban components..."
    wget -q -N -P /var/lib/marzban/templates/subscription/ https://raw.githubusercontent.com/Elysya28/Install-vps/main/index.html

    # Create custom .env file
    cat > "$MARZBAN_DIR/.env" << 'EOF'
UVICORN_HOST = "0.0.0.0"
UVICORN_PORT = 7879
XRAY_JSON = "/var/lib/marzban/xray_config.json"
XRAY_ASSETS_PATH = "/var/lib/marzban/assets"
SUBSCRIPTION_PAGE_TEMPLATE="subscription/index.html"
CUSTOM_TEMPLATES_DIRECTORY="/var/lib/marzban/templates/"
HOME_PAGE_TEMPLATE="home/index.html"
SQLALCHEMY_DATABASE_URL = "sqlite:////var/lib/marzban/db.sqlite3"
DOCS=true
JWT_ACCESS_TOKEN_EXPIRE_MINUTES = 0
EOF
    mkdir -p /var/lib/marzban/assets

    # Create docker-compose.yml
    cat > "$MARZBAN_DIR/docker-compose.yml" << 'EOF'
services:
  marzban:
    image: gozargah/marzban:latest
    restart: always
    env_file: .env
    network_mode: host
    volumes:
    - /var/lib/marzban:/var/lib/marzban

  nginx:
    image: nginx:latest
    container_name: marzban-nginx
    restart: always
    network_mode: host
    volumes:
    - ./nginx.conf:/etc/nginx/nginx.conf:ro
    - ./xray.conf:/etc/nginx/conf.d/xray.conf:ro
    - /var/lib/marzban/xray.crt:/var/lib/marzban/xray.crt:ro
    - /var/lib/marzban/xray.key:/var/lib/marzban/xray.key:ro
    - /var/log/nginx:/var/log/nginx
EOF

    # Configure Nginx
    log blue "Configuring Nginx..."
    mkdir -p /var/log/nginx /var/www/html
    touch /var/log/nginx/{access.log,error.log}
    
    # Create master nginx.conf
    cat > "$MARZBAN_DIR/nginx.conf" << 'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 4096;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';
    access_log  /var/log/nginx/access.log  main;
    error_log   /var/log/nginx/error.log;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    include /etc/nginx/conf.d/*.conf;
}
EOF
    
    # Create xray.conf for Nginx with variables
    # This configuration redirects HTTP to HTTPS and proxies dashboard traffic
    cat > "$MARZBAN_DIR/xray.conf" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${domain};

    ssl_certificate ${CERT_FILE};
    ssl_certificate_key ${KEY_FILE};
    ssl_ciphers EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+ECDSA+AES128:EECDH+aRSA+AES128:RSA+AES128:EECDH+ECDSA+AES256:EECDH+aRSA+AES256:RSA+AES256:EECDH+ECDSA+3DES:EECDH+aRSA+3DES:RSA+3DES:!MD5;
    ssl_protocols TLSv1.2 TLSv1.3;

    location ~* /(dashboard|statics|api|docs|sub|redoc|openapi.json) {
        proxy_pass http://127.0.0.1:7879;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

    #========================================================================================
    # BAGIAN ACME.SH BARU YANG DIINTEGRASIKAN
    #========================================================================================
    log blue "Memulai instalasi sertifikat SSL dengan acme.sh..."
    
    # 1. Instalasi acme.sh
    log blue "=> Menginstal acme.sh..."
    curl https://get.acme.sh | sh -s email="$email" || { log red "Gagal menginstal acme.sh."; exit 1; }

    # 2. Penerbitan Sertifikat
    log blue "=> Meminta sertifikat untuk $domain..."
    ~/.acme.sh/acme.sh --issue -d "$domain" --standalone -k ec-256 \
                       --reloadcmd "$RELOAD_CMD" --server letsencrypt || { log red "Gagal menerbitkan sertifikat. Pastikan port 80 bebas dan DNS sudah benar."; exit 1; }

    # 3. Instalasi Sertifikat ke Lokasi Tujuan
    log blue "=> Menginstal sertifikat..."
    ~/.acme.sh/acme.sh --install-cert -d "$domain" --ecc \
                       --key-file "$KEY_FILE" \
                       --fullchain-file "$CERT_FILE" || { log red "Gagal menginstal sertifikat."; exit 1; }

    # 4. Verifikasi Akhir
    if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
        log green "✓ Sukses! Sertifikat SSL untuk $domain telah dibuat."
    else
        log red "X Gagal! File sertifikat atau kunci tidak ditemukan."
        exit 1
    fi
    #========================================================================================
    # AKHIR DARI BAGIAN ACME.SH
    #========================================================================================

    # Create xray_config.json
    log blue "Creating xray_config.json..."
    cat > /var/lib/marzban/xray_config.json << 'EOF'
{
  "log": {
    "access": null,
    "error": null,
    "loglevel": "warning"
  },
  "dns": { "servers": [ "1.1.1.1", "localhost" ] },
  "routing": { "domainStrategy": "AsIs", "rules": [] },
  "inbounds": [],
  "outbounds": [
    { "tag": "direct", "protocol": "freedom" },
    { "tag": "block", "protocol": "blackhole" }
  ]
}
EOF
    
    # Configure firewall
    log blue "Configuring firewall..."
    apt-get install -y ufw
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow http
    ufw allow https
    yes | ufw enable || { log yellow "Failed to enable firewall."; }
 
    # Install WARP proxy
    log blue "Installing WARP proxy..."
    wget -q -O /root/warp "https://raw.githubusercontent.com/hamid-gh98/x-ui-scripts/main/install_warp_proxy.sh" && chmod +x /root/warp
    bash /root/warp -y || { log yellow "Failed to install WARP proxy."; }
    
    # Finalize Marzban setup
    log blue "Finalizing Marzban setup..."
    cd "$MARZBAN_DIR"
    sed -i "s/# SUDO_USERNAME = \"admin\"/SUDO_USERNAME = \"${userpanel}\"/" .env
    sed -i "s/# SUDO_PASSWORD = \"admin\"/SUDO_PASSWORD = \"${passpanel}\"/" .env
    marzban down && marzban up -d || { log red "Failed to start Marzban services."; exit 1; }
    marzban cli admin import-from-env -y || { log red "Failed to import admin from env."; exit 1; }
    sed -i "/SUDO_USERNAME/s/.*/# SUDO_USERNAME = \"admin\"/" .env
    sed -i "/SUDO_PASSWORD/s/.*/# SUDO_PASSWORD = \"admin\"/" .env
    marzban restart || { log red "Failed to restart Marzban services."; exit 1; }
    
    # Clean up
    log blue "Cleaning up..."
    apt-get autoremove -y > /dev/null 2>&1
    
    # Log installation details to file and display
    cat <<EOF > "$CONFIG_DIR/install-log.txt"
==================================
Marzban Dashboard Login Details:
==================================
URL: https://${domain}/dashboard
Username: ${userpanel}
Password: ${passpanel}
==================================
EOF
    cat "$CONFIG_DIR/install-log.txt"
    
    log green "Script successfully installed."
    
    # Prompt for reboot
    read -rp "Reboot to apply changes? [default y] (y/n): " answer
    if [[ "$answer" != "n" && "$answer" != "N" ]]; then
        log blue "Rebooting system..."
        cat /dev/null > ~/.bash_history && history -c
        reboot
    fi
}

# Trap errors
trap 'log red "Script terminated due to an error."; exit 1' ERR

# Execute main
main
