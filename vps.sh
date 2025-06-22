#!/bin/bash

# Constants
CONFIG_DIR="/etc/data"
LOG_FILE="/root/log-install.txt"
SUPPORTED_OS=("debian:11" "debian:12" "ubuntu:20.04" "ubuntu:22.04" "ubuntu:24.04")
DOMAIN_FILE="$CONFIG_DIR/domain"
USERPANEL_FILE="$CONFIG_DIR/userpanel"
PASSPANEL_FILE="$CONFIG_DIR/passpanel"
MARZBAN_DIR="/opt/marzban"

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
                # Configure SSH keep-alive settings
              #  sed -i '/^[[:space:]]*#*ClientAliveInterval[[:space:]]/s/.*/ClientAliveInterval 10/' /etc/ssh/sshd_config
              #  sed -i '/^[[:space:]]*#*ClientAliveCountMax[[:space:]]/s/.*/ClientAliveCountMax 3/' /etc/ssh/sshd_config
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
    apt-get install -y sudo curl || { log red "Failed to install sudo and curl."; exit 1; }
    
    log blue "Removing unused packages..."
    apt-get -y --purge remove samba* apache2* sendmail* bind9* || { log red "Failed to remove unused packages."; }
    
    log blue "Installing toolkit packages..."
    apt-get install -y libio-socket-inet6-perl libsocket6-perl libcrypt-ssleay-perl \
        libnet-libidn-perl libio-socket-ssl-perl libwww-perl libpcre3 libpcre3-dev \
        zlib1g-dev dbus iftop zip unzip wget net-tools curl nano sed screen gnupg \
        gnupg1 bc apt-transport-https build-essential dirmngr dnsutils sudo at htop vnstat \
        iptables bsdmainutils cron lsof lnav || { log red "Failed to install toolkit packages."; exit 1; }
    
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
    bash -c "$(curl -sL https://raw.githubusercontent.com/tabraklari/Install-vps/refs/heads/main/install)" @ install || { log red "Failed to install Marzban."; exit 1; }
    
    # Install subscriptions and environment
    log blue "Configuring Marzban components..."
    wget -q -N -P /var/lib/marzban/templates/subscription/ https://raw.githubusercontent.com/tabraklari/Install-vps/main/index.html || { log red "Failed to download subscription template."; exit 1; }

    # Create custom .env file
    cat > "$MARZBAN_DIR/.env" << 'EOF'
UVICORN_HOST = "0.0.0.0"
UVICORN_PORT = 7879


## We highly recommend add admin using `marzban cli` tool and do not use
## the following variables which is somehow hard codded infrmation.
# SUDO_USERNAME = "admin"
# SUDO_PASSWORD = "admin"

# UVICORN_UDS: "/run/marzban.socket"
# UVICORN_SSL_CERTFILE = "/var/lib/marzban/certs/fullchain.pem"
# UVICORN_SSL_KEYFILE = "/var/lib/marzban/certs/key.pem"


XRAY_JSON = "/var/lib/marzban/xray_config.json"
# XRAY_EXECUTABLE_PATH = "/var/lib/marzban/core/xray"
# XRAY_SUBSCRIPTION_URL_PREFIX = "https://example.com"
# XRAY_EXECUTABLE_PATH = "/var/lib/marzban/core/xray"
XRAY_ASSETS_PATH = "/var/lib/marzban/assets"
# XRAY_FALLBACKS_INBOUND_TAG = "INBOUND_X"


# TELEGRAM_API_TOKEN = 123456789:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
# TELEGRAM_ADMIN_ID = 987654321
# TELEGRAM_PROXY_URL = "http://localhost:8080"


# CLASH_SUBSCRIPTION_TEMPLATE="clash/my-custom-template.yml"
SUBSCRIPTION_PAGE_TEMPLATE="subscription/index.html"
CUSTOM_TEMPLATES_DIRECTORY="/var/lib/marzban/templates/"
HOME_PAGE_TEMPLATE="home/index.html"
# SUBSCRIPTION_PAGE_LANG="en"

SQLALCHEMY_DATABASE_URL = "sqlite:////var/lib/marzban/db.sqlite3"

### for developers
DOCS=true
# DEBUG=true
# WEBHOOK_ADDRESS = "http://127.0.0.1:9000/"
# WEBHOOK_SECRET = "something-very-very-secret"
# VITE_BASE_API="https://example.com/api/"
JWT_ACCESS_TOKEN_EXPIRE_MINUTES = 0
EOF
    mkdir -p /var/lib/marzban/assets

    # Install docker-compose
    cat > "$MARZBAN_DIR/docker-compose.yml" << 'EOF'
services:
  marzban:
    image: gozargah/marzban:latest
    restart: always
    env_file: .env
    network_mode: host
    volumes:
    - /etc/timezone:/etc/timezone:ro
    - /etc/localtime:/etc/localtime:ro
    - /var/lib/marzban:/var/lib/marzban

  nginx:
    image: nginx
    restart: always
    network_mode: host
    volumes:
    - /var/lib/marzban:/var/lib/marzban
    - /var/www/html:/var/www/html
    - /etc/timezone:/etc/timezone:ro
    - /etc/localtime:/etc/localtime:ro
    - /var/log/nginx/access.log:/var/log/nginx/access.log
    - /var/log/nginx/error.log:/var/log/nginx/error.log
    - ./nginx.conf:/etc/nginx/nginx.conf
    - ./default.conf:/etc/nginx/conf.d/default.conf
    - ./xray.conf:/etc/nginx/conf.d/xray.conf
EOF

    # Install nginx
    log blue "Installing nginx..."
    mkdir -p /var/log/nginx /var/www/html
    touch /var/log/nginx/{access.log,error.log}

    # Create Pacman game HTML file
    cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Pacman Server</title>
    <style>
        body {
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #1e3c72, #2a5298);
            color: white;
            font-family: 'Courier New', monospace;
            display: flex;
            flex-direction: column;
            align-items: center;
            min-height: 100vh;
        }
        .header {
            text-align: center;
            margin-bottom: 20px;
        }
        .header h1 {
            color: #ffff00;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.5);
            margin: 10px 0;
        }
        .header p {
            color: #87ceeb;
            margin: 5px 0;
        }
        .game-container {
            border: 3px solid #ffff00;
            border-radius: 10px;
            padding: 10px;
            background: rgba(0,0,0,0.3);
            box-shadow: 0 0 20px rgba(255,255,0,0.3);
        }
        canvas {
            background: #000;
            border: 2px solid #0066cc;
            border-radius: 5px;
        }
        .controls {
            margin-top: 15px;
            text-align: center;
        }
        .controls p {
            margin: 5px 0;
            color: #87ceeb;
        }
        .score {
            font-size: 18px;
            font-weight: bold;
            color: #ffff00;
            margin-bottom: 10px;
            text-align: center;
        }
        .game-over {
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            background: rgba(0,0,0,0.9);
            padding: 30px;
            border-radius: 10px;
            text-align: center;
            color: #ff4444;
            font-size: 24px;
            display: none;
            border: 2px solid #ff4444;
        }
        .restart-btn {
            background: #ffff00;
            color: #000;
            border: none;
            padding: 10px 20px;
            font-size: 16px;
            border-radius: 5px;
            cursor: pointer;
            margin-top: 15px;
            font-weight: bold;
        }
        .restart-btn:hover {
            background: #fff200;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>🎮 PACMAN 🎮</h1>
    </div>
    
    <div class="game-container">
        <div class="score">Score: <span id="score">0</span> | Lives: <span id="lives">3</span></div>
        <canvas id="gameCanvas" width="600" height="400"></canvas>
        <div class="controls">
            <p><strong>Controls:</strong> W (Up) | A (Left) | S (Down) | D (Right)</p>
            <p>Collect yellow dots and avoid the red ghosts!</p>
        </div>
    </div>
    
    <div class="game-over" id="gameOver">
        <h2>GAME OVER!</h2>
        <p>Final Score: <span id="finalScore">0</span></p>
        <button class="restart-btn" onclick="restartGame()">Play Again</button>
    </div>

    <script>
        const canvas = document.getElementById('gameCanvas');
        const ctx = canvas.getContext('2d');
        
        // Game variables
        let score = 0;
        let lives = 3;
        let gameRunning = true;
        
        // Pacman object
        const pacman = {
            x: 30,
            y: 30,
            size: 15,
            dx: 0,
            dy: 0,
            speed: 2,
            direction: 'right',
            mouthAngle: 0
        };
        
        // Ghosts array
        const ghosts = [
            { x: 500, y: 100, dx: -1, dy: 0, color: '#ff0000', speed: 1.5 },
            { x: 300, y: 200, dx: 1, dy: 0, color: '#ff69b4', speed: 1.2 },
            { x: 400, y: 300, dx: 0, dy: -1, color: '#00ffff', speed: 1.3 },
            { x: 150, y: 150, dx: 1, dy: 1, color: '#ffa500', speed: 1.1 }
        ];
        
        // Dots array
        const dots = [];
        
        // Initialize dots
        function initDots() {
            dots.length = 0;
            for (let x = 50; x < canvas.width - 20; x += 30) {
                for (let y = 50; y < canvas.height - 20; y += 30) {
                    // Don't place dots too close to pacman's starting position
                    if (Math.abs(x - pacman.x) > 40 || Math.abs(y - pacman.y) > 40) {
                        dots.push({ x, y, collected: false });
                    }
                }
            }
        }
        
        // Initialize game
        function initGame() {
            score = 0;
            lives = 3;
            gameRunning = true;
            pacman.x = 30;
            pacman.y = 30;
            pacman.dx = 0;
            pacman.dy = 0;
            pacman.direction = 'right';
            initDots();
            document.getElementById('gameOver').style.display = 'none';
        }
        
        // Draw Pacman
        function drawPacman() {
            ctx.save();
            ctx.translate(pacman.x, pacman.y);
            
            // Rotate based on direction
            switch(pacman.direction) {
                case 'up': ctx.rotate(-Math.PI / 2); break;
                case 'down': ctx.rotate(Math.PI / 2); break;
                case 'left': ctx.rotate(Math.PI); break;
            }
            
            // Draw Pacman body
            ctx.fillStyle = '#ffff00';
            ctx.beginPath();
            ctx.arc(0, 0, pacman.size, pacman.mouthAngle, 2 * Math.PI - pacman.mouthAngle);
            ctx.lineTo(0, 0);
            ctx.fill();
            
            // Draw eye
            ctx.fillStyle = '#000';
            ctx.beginPath();
            ctx.arc(-5, -5, 2, 0, 2 * Math.PI);
            ctx.fill();
            
            ctx.restore();
        }
        
        // Draw ghost
        function drawGhost(ghost) {
            ctx.fillStyle = ghost.color;
            ctx.beginPath();
            ctx.arc(ghost.x, ghost.y, 12, 0, Math.PI);
            ctx.rect(ghost.x - 12, ghost.y, 24, 15);
            ctx.fill();
            
            // Ghost bottom wavy part
            ctx.beginPath();
            for (let i = 0; i < 4; i++) {
                ctx.lineTo(ghost.x - 12 + i * 6, ghost.y + 15 - (i % 2) * 4);
            }
            ctx.lineTo(ghost.x + 12, ghost.y + 15);
            ctx.lineTo(ghost.x + 12, ghost.y);
            ctx.fill();
            
            // Eyes
            ctx.fillStyle = '#fff';
            ctx.beginPath();
            ctx.arc(ghost.x - 4, ghost.y - 3, 3, 0, 2 * Math.PI);
            ctx.arc(ghost.x + 4, ghost.y - 3, 3, 0, 2 * Math.PI);
            ctx.fill();
            
            ctx.fillStyle = '#000';
            ctx.beginPath();
            ctx.arc(ghost.x - 4, ghost.y - 3, 1.5, 0, 2 * Math.PI);
            ctx.arc(ghost.x + 4, ghost.y - 3, 1.5, 0, 2 * Math.PI);
            ctx.fill();
        }
        
        // Draw dot
        function drawDot(dot) {
            if (!dot.collected) {
                ctx.fillStyle = '#ffff00';
                ctx.beginPath();
                ctx.arc(dot.x, dot.y, 3, 0, 2 * Math.PI);
                ctx.fill();
            }
        }
        
        // Update game
        function update() {
            if (!gameRunning) return;
            
            // Update Pacman mouth animation
            pacman.mouthAngle = Math.abs(Math.sin(Date.now() * 0.01)) * 0.7;
            
            // Move Pacman
            let newX = pacman.x + pacman.dx;
            let newY = pacman.y + pacman.dy;
            
            // Boundary checking
            if (newX >= pacman.size && newX <= canvas.width - pacman.size) {
                pacman.x = newX;
            }
            if (newY >= pacman.size && newY <= canvas.height - pacman.size) {
                pacman.y = newY;
            }
            
            // Move ghosts
            ghosts.forEach(ghost => {
                ghost.x += ghost.dx * ghost.speed;
                ghost.y += ghost.dy * ghost.speed;
                
                // Bounce off walls
                if (ghost.x <= 15 || ghost.x >= canvas.width - 15) {
                    ghost.dx *= -1;
                }
                if (ghost.y <= 15 || ghost.y >= canvas.height - 15) {
                    ghost.dy *= -1;
                }
                
                // Random direction change
                if (Math.random() < 0.01) {
                    const directions = [
                        { dx: 1, dy: 0 }, { dx: -1, dy: 0 },
                        { dx: 0, dy: 1 }, { dx: 0, dy: -1 }
                    ];
                    const newDir = directions[Math.floor(Math.random() * directions.length)];
                    ghost.dx = newDir.dx;
                    ghost.dy = newDir.dy;
                }
                
                // Check collision with Pacman
                const distance = Math.sqrt(
                    Math.pow(ghost.x - pacman.x, 2) + Math.pow(ghost.y - pacman.y, 2)
                );
                if (distance < 25) {
                    lives--;
                    if (lives <= 0) {
                        gameOver();
                    } else {
                        // Reset Pacman position
                        pacman.x = 30;
                        pacman.y = 30;
                        pacman.dx = 0;
                        pacman.dy = 0;
                    }
                }
            });
            
            // Check dot collection
            dots.forEach(dot => {
                if (!dot.collected) {
                    const distance = Math.sqrt(
                        Math.pow(dot.x - pacman.x, 2) + Math.pow(dot.y - pacman.y, 2)
                    );
                    if (distance < 20) {
                        dot.collected = true;
                        score += 10;
                    }
                }
            });
            
            // Check win condition
            if (dots.every(dot => dot.collected)) {
                score += 500;
                initDots(); // Create new level
            }
            
            // Update UI
            document.getElementById('score').textContent = score;
            document.getElementById('lives').textContent = lives;
        }
        
        // Draw everything
        function draw() {
            // Clear canvas
            ctx.fillStyle = '#001122';
            ctx.fillRect(0, 0, canvas.width, canvas.height);
            
            // Draw dots
            dots.forEach(drawDot);
            
            // Draw Pacman
            drawPacman();
            
            // Draw ghosts
            ghosts.forEach(drawGhost);
        }
        
        // Game loop
        function gameLoop() {
            update();
            draw();
            requestAnimationFrame(gameLoop);
        }
        
        // Game over
        function gameOver() {
            gameRunning = false;
            document.getElementById('finalScore').textContent = score;
            document.getElementById('gameOver').style.display = 'block';
        }
        
        // Restart game
        function restartGame() {
            initGame();
        }
        
        // Keyboard controls
        document.addEventListener('keydown', (e) => {
            if (!gameRunning) return;
            
            const key = e.key.toLowerCase();
            switch(key) {
                case 'w':
                    pacman.dx = 0;
                    pacman.dy = -pacman.speed;
                    pacman.direction = 'up';
                    break;
                case 's':
                    pacman.dx = 0;
                    pacman.dy = pacman.speed;
                    pacman.direction = 'down';
                    break;
                case 'a':
                    pacman.dx = -pacman.speed;
                    pacman.dy = 0;
                    pacman.direction = 'left';
                    break;
                case 'd':
                    pacman.dx = pacman.speed;
                    pacman.dy = 0;
                    pacman.direction = 'right';
                    break;
            }
        });
        
        // Initialize and start game
        initGame();
        gameLoop();
    </script>
</body>
</html>
EOF

        
    # Create nginx.conf
    cat > "$MARZBAN_DIR/nginx.conf" << 'EOF'
user  www-data;
worker_processes  3;

#error_log  logs/error.log;
#error_log  logs/error.log  notice;
#error_log  logs/error.log  info;

#pid        logs/nginx.pid;


events {
    worker_connections  4096;
}


http {
    include       mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    #access_log  logs/access.log  main;

    sendfile       on;
    tcp_nopush     on;
    tcp_nodelay    on;
    keepalive_timeout  65;
    types_hash_max_size 2048;
    #gzip  on;


    # another virtual host using mix of IP-, name-, and port-based configuration
    #
    #server {
    #    listen       8000;
    #    listen       somename:8080;
    #    server_name  somename  alias  another.alias;

    #    location / {
    #        root   html;
    #        index  index.html index.htm;
    #    }
    #}


    # HTTPS server
    #
    #server {
    #    listen       443 ssl;
    #    server_name  localhost;

    #    ssl_certificate      cert.pem;
    #    ssl_certificate_key  cert.key;

    #    ssl_session_cache    shared:SSL:1m;
    #    ssl_session_timeout  5m;

    #    ssl_ciphers  HIGH:!aNULL:!MD5;
    #    ssl_prefer_server_ciphers  on;

    #    location / {
    #        root   html;
    #        index  index.html index.htm;
    #    }
    #}

include conf.d/*.conf;
}
EOF
    
    # Create default.conf
    cat > "$MARZBAN_DIR/default.conf" << 'EOF'
server {
  listen       8081;
  server_name  127.0.0.1 localhost;
  access_log /var/log/nginx/access.log;
  error_log /var/log/nginx/error.log error;
  root   /var/www/html;

  location / {
    index  index.html index.htm index.php;
    try_files $uri $uri/ /index.php?$args;
  }

  location ~ \.php$ {
    include /etc/nginx/fastcgi_params;
    fastcgi_pass  127.0.0.1:9000;
    fastcgi_index index.php;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
  }
}
EOF
    
    # Create xray.conf
    cat > "$MARZBAN_DIR/xray.conf" << 'EOF'
    server {
        listen 80;
        listen [::]:80;
        listen [::]:443 ssl ipv6only=off reuseport;
        listen [::]:443 quic reuseport ipv6only=off;
        http2 on;
        set_real_ip_from 127.0.0.0/8;
#ips-v4:
        set_real_ip_from 103.21.244.0/22;
        set_real_ip_from 103.22.200.0/22;
        set_real_ip_from 103.31.4.0/22;
        set_real_ip_from 104.16.0.0/13;
        set_real_ip_from 104.24.0.0/14;
        set_real_ip_from 108.162.192.0/18;
        set_real_ip_from 131.0.72.0/22;
        set_real_ip_from 141.101.64.0/18;
        set_real_ip_from 162.158.0.0/15;
        set_real_ip_from 172.64.0.0/13;
        set_real_ip_from 173.245.48.0/20;
        set_real_ip_from 188.114.96.0/20;
        set_real_ip_from 190.93.240.0/20;
        set_real_ip_from 197.234.240.0/22;
        set_real_ip_from 198.41.128.0/17;
#ips-v6:
        set_real_ip_from 2400:cb00::/32;
        set_real_ip_from 2606:4700::/32;
        set_real_ip_from 2803:f800::/32;
        set_real_ip_from 2405:b500::/32;
        set_real_ip_from 2405:8100::/32;
        set_real_ip_from 2a06:98c0::/29;
        set_real_ip_from 2c0f:f248::/32;
             server_name 127.0.0.1 localhost;
             real_ip_header X-Forwarded-For;
             ssl_certificate /var/lib/marzban/xray.crt;
             ssl_certificate_key /var/lib/marzban/xray.key;
             ssl_ciphers EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+ECDSA+AES128:EECDH+aRSA+AES128:RSA+AES128:EECDH+ECDSA+AES256:EECDH+aRSA+AES256:RSA+AES256:EECDH+ECDSA+3DES:EECDH+aRSA+3DES:RSA+3DES:!MD5;
             ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;
             root /var/www/html;

location ~* /(dashboard|statics|api|docs|sub|redoc|openapi.json) {
proxy_pass http://127.0.0.1:7879;
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}
location ~ /trojan {
if ($http_upgrade != "Upgrade") {
rewrite /(.*) /trojan break;
    }
proxy_redirect off;
proxy_pass http://127.0.0.1:3001;
proxy_connect_timeout 4s;
proxy_read_timeout 120s;
proxy_send_timeout 12s;
proxy_http_version 1.1;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_set_header Host $http_host;
    }
location ~ /vmess {
if ($http_upgrade != "Upgrade") {
rewrite /(.*) /vmess break;
    }
proxy_redirect off;
proxy_pass http://127.0.0.1:3002;
proxy_http_version 1.1;
proxy_connect_timeout 4s;
proxy_read_timeout 120s;
proxy_send_timeout 12s;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_set_header Host $http_host;
    }
location ~ /vless {
if ($http_upgrade != "Upgrade") {
rewrite /(.*) /vless break;
    }
proxy_redirect off;
proxy_pass http://127.0.0.1:3003;
proxy_connect_timeout 4s;
proxy_read_timeout 120s;
proxy_send_timeout 12s;
proxy_http_version 1.1;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_set_header Host $http_host;
    }
location /xtrojan/ {
client_max_body_size 0;
grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
client_body_timeout 5m;
grpc_read_timeout 315;
grpc_send_timeout 5m;
grpc_pass grpc://127.0.0.1:4001;
        }
location /xvmess/ {
client_max_body_size 0;
grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
client_body_timeout 5m;
grpc_read_timeout 315;
grpc_send_timeout 5m;
grpc_pass grpc://127.0.0.1:4002;
        }
location /xvless/ {
client_max_body_size 0;
grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
client_body_timeout 5m;
grpc_read_timeout 315;
grpc_send_timeout 5m;
grpc_pass grpc://127.0.0.1:4003;
        }
}
EOF

    # Install socat
    log blue "Installing socat and related packages..."
    apt install -y iptables curl socat xz-utils apt-transport-https gnupg gnupg2 gnupg1 dnsutils lsb-release cron bash-completion || { log red "Failed to install socat packages."; exit 1; }
    
    # Install certificates
    log blue "Installing SSL certificates..."
    curl https://get.acme.sh | sh -s email="$email" || { log red "Failed to install acme.sh."; exit 1; }
    ~/.acme.sh/acme.sh --server letsencrypt --register-account -m "$email" --issue -d "$domain" --standalone -k ec-256 --debug || { log red "Failed to issue SSL certificate."; exit 1; }
    ~/.acme.sh/acme.sh --installcert -d "$domain" --fullchainpath /var/lib/marzban/xray.crt --keypath /var/lib/marzban/xray.key --ecc || { log red "Failed to install SSL certificate."; exit 1; }
    
    # Create xray_config.json
    log blue "Creating xray_config.json..."
    cat > /var/lib/marzban/xray_config.json << 'EOF'
{
  "log": {
    "access": "/var/lib/marzban/access.log",
    "error": "/var/lib/marzban/error.log",
    "loglevel": "warning"
  },
  "dns": {
    "servers": [
      "1.1.1.1",
      "1.0.0.1",
      "8.8.8.8",
      "8.8.4.4",
      "127.0.0.1"
    ],
    "tag": "dns-in"
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "inboundTag": [
          "dns-in"
        ],
        "outboundTag": "dns-out"
      },
      {
        "type": "field",
        "protocol": [
          "bittorent"
        ],
        "outboundTag": "block"
      }
    ]
  },
  "inbounds": [
    {
      "tag": "TROJAN_WS",
      "listen": "127.0.0.1",
      "port": 3001,
      "protocol": "trojan",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/trojan"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "fakedns+others",
          "http",
          "tls",
          "quic"
        ],
        "routeOnly": true
      }
    },
    {
      "tag": "VMESS_WS",
      "listen": "127.0.0.1",
      "port": 3002,
      "protocol": "vmess",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/vmess"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "fakedns+others",
          "http",
          "tls",
          "quic"
        ],
        "routeOnly": true
      }
    },
    {
      "tag": "VLESS_WS",
      "listen": "127.0.0.1",
      "port": 3003,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/vless"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "fakedns+others",
          "http",
          "tls",
          "quic"
        ],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4"
      }
    },
    {
      "tag": "block",
      "protocol": "blackhole",
      "settings": {
        "response": {
          "type": "http"
        }
      }
    },
    {
      "tag": "dns-out",
      "protocol": "dns",
      "settings": {
        "nonIPQuery": "skip"
      }
    }
  ]
}
EOF
    
    # Configure firewall
    log blue "Configuring firewall..."
    apt install -y ufw
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow http
    ufw allow https
    ufw allow 8081/tcp
    ufw allow 1080/tcp
    ufw allow 1080/udp
    yes | ufw enable || { log red "Failed to enable firewall."; exit 1; }
 
    # Install WARP proxy
    log blue "Installing WARP proxy..."
    wget -q -O /root/warp "https://raw.githubusercontent.com/hamid-gh98/x-ui-scripts/main/install_warp_proxy.sh" && chmod +x /root/warp
    bash /root/warp -y || { log red "Failed to install WARP proxy."; exit 1; }
    
    # Finalize Marzban setup
    log blue "Finalizing Marzban setup..."
    cd "$MARZBAN_DIR"
    sed -i "s/# SUDO_USERNAME = \"admin\"/SUDO_USERNAME = \"${userpanel}\"/" .env
    sed -i "s/# SUDO_PASSWORD = \"admin\"/SUDO_PASSWORD = \"${passpanel}\"/" .env
    docker compose down && docker compose up -d || { log red "Failed to start Marzban services."; exit 1; }
    marzban cli admin import-from-env -y || { log red "Failed to import admin from env."; exit 1; }
    sed -i "s/SUDO_USERNAME = \"${userpanel}\"/# SUDO_USERNAME = \"admin\"/" .env
    sed -i "s/SUDO_PASSWORD = \"${passpanel}\"/# SUDO_PASSWORD = \"admin\"/" .env
    docker compose down && docker compose up -d || { log red "Failed to restart Marzban services."; exit 1; }
    
    # Generate API token
    log blue "Generating API token..."
    sleep 30
    curl -s -X POST "https://${domain}/api/admin/token" \
        -H 'accept: application/json' \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        -d "grant_type=password&username=${userpanel}&password=${passpanel}&scope=&client_id=string&client_secret=string" > /etc/data/token.json || { log red "Failed to generate API token."; exit 1; }
    
    # Clean up
    log blue "Cleaning up..."
    apt autoremove -y
    
    # Log installation details
    cat <<EOF > "$LOG_FILE"
Marzban Dashboard Login Details:
==================================
URL: https://${domain}/dashboard
Username: ${userpanel}
Password: ${passpanel}
==================================
EOF
    cat "$LOG_FILE"
    
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
