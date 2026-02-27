#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  Android VPS Installer v3.0
#  Stack: Nginx + PHP-FPM + MariaDB + Redis + PostgreSQL
#         + ChromaDB + WP-CLI + Cloudflare Tunnel
#  Tính năng: Multi-site, Subdomain, Backup Telegram,
#             Auto Recovery, Health Check, Security, Monitor
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

DEBIAN_ROOT="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/debian"

log()     { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info()    { echo -e "${CYAN}[i]${NC} $1"; }
section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

banner() {
cat << 'EOF'

  ╔═══════════════════════════════════════════════════╗
  ║         ANDROID VPS INSTALLER v3.0               ║
  ║  Nginx · PHP-FPM · MariaDB · Redis · WP-CLI      ║
  ║  PostgreSQL · ChromaDB · Cloudflare Tunnel        ║
  ║  Backup Telegram · Health Check · Security        ║
  ║  Multi-site · Subdomain · Monitor · Auto Recovery ║
  ╚═══════════════════════════════════════════════════╝

EOF
}

run_debian() {
    proot-distro login debian --shared-tmp -- bash -c "$1"
}

# ============================================================
# BƯỚC 1: TERMUX
# ============================================================
step1_termux() {
    section "BƯỚC 1: Cài đặt Termux packages + SSH"
    log "Cập nhật package..."
    pkg update -y && pkg upgrade -y
    log "Cài tools..."
    pkg install -y proot-distro wget curl git openssh python tmux
    termux-setup-storage || true
    grep -q 'alias debian=' ~/.bashrc 2>/dev/null || \
        echo 'alias debian="proot-distro login debian --shared-tmp"' >> ~/.bashrc

    # Cài đặt SSH server
    log "Cài đặt SSH server..."
    echo ""
    warn "Đặt password SSH để kết nối từ máy tính (Bitvise):"
    passwd

    # Khởi động SSH
    sshd 2>/dev/null || true

    # Tự động khởi động SSH khi Termux mở
    grep -q 'sshd' ~/.bashrc 2>/dev/null || \
        echo 'sshd 2>/dev/null || true' >> ~/.bashrc

    log "Termux + SSH xong!"
}

# ============================================================
# BƯỚC 2: UBUNTU
# ============================================================
step2_debian() {
    section "BƯỚC 2: Cài Debian proot"
    if [ -d "$DEBIAN_ROOT" ] && [ -f "$DEBIAN_ROOT/etc/debian_version" ]; then
        warn "Debian đã cài, bỏ qua tải xuống..."
    else
        log "Cài Debian Trixie (testing)..."
        proot-distro install debian || true
    fi
    log "Debian xong!"
}

# ============================================================
# BƯỚC 3: NGINX + PHP-FPM + MARIADB + REDIS
# ============================================================
step3_nginx_stack() {
    section "BƯỚC 3: Cài Nginx + PHP-FPM + MariaDB + Redis"

    log "Cập nhật Debian..."
    run_debian "apt update && apt upgrade -y"

    log "Tạo thư mục cần thiết..."
    run_debian "mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/nginx/snippets \
        /etc/redis /etc/php \
        /var/log/nginx /var/log/redis /var/log/php \
        /var/www /run/php"

    # Chặn invoke-rc.d tự start service khi apt cài (proot không có systemd)
    log "Cấu hình policy-rc.d..."
    run_debian "echo $'#!/bin/sh\nexit 101' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d"

    # Fix lỗi dpkg-realpath và sysctl trigger trong Termux proot
    run_debian "ln -sf /bin/true /sbin/sysctl"
    run_debian "mkdir -p /proc/1 && touch /proc/1/environ 2>/dev/null || true"

    # Thêm repo packages.sury.org/php cho Debian
    log "Thêm Repo sury/php..."
    run_debian "DEBIAN_FRONTEND=noninteractive apt install -y lsb-release ca-certificates apt-transport-https curl && \\
        curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg && \\
        sh -c 'echo \"deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ \$(lsb_release -sc) main\" > /etc/apt/sources.list.d/php.list' && \\
        apt update"

    log "Cài Nginx + PHP-FPM + extensions..."
    run_debian "DEBIAN_FRONTEND=noninteractive apt install -y \
        nginx \
        php8.4-fpm php8.4-mysql php8.4-curl php8.4-gd php8.4-mbstring \
        php8.4-xml php8.4-zip php8.4-redis php8.4-intl php8.4-bcmath \
        php8.4-imagick php8.4-pgsql \
        mariadb-server redis-server \
        unzip wget curl git nano tmux python3 python3-pip python3-yaml \
       "

    log "Cài WP-CLI..."
    run_debian "wget -q https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
        -O /usr/local/bin/wp && chmod +x /usr/local/bin/wp"

    log "Cấu hình Nginx chính..."
    run_debian "mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/nginx/snippets"
    run_debian "cat > /etc/nginx/nginx.conf << 'NGINX'
user www-data;
worker_processes 1;
pid /run/nginx.pid;

events {
    worker_connections 512;
    use epoll;
    multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 64M;
    server_tokens off;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Gzip
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript
               text/xml application/xml image/svg+xml;

    # Rate limiting zones
    limit_req_zone \$binary_remote_addr zone=wp_login:10m rate=5r/m;
    limit_req_zone \$binary_remote_addr zone=api:10m rate=30r/m;

    # Logging
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    include /etc/nginx/sites-enabled/*;
}
NGINX"

    log "Cấu hình PHP-FPM..."
    run_debian "sed -i 's/^listen = .*/listen = \/run\/php\/php8.4-fpm.sock/' \
        /etc/php/8.4/fpm/pool.d/www.conf 2>/dev/null || true"
    run_debian "sed -i 's/^pm.max_children = .*/pm.max_children = 5/' \
        /etc/php/8.4/fpm/pool.d/www.conf 2>/dev/null || true"
    run_debian "sed -i 's/^pm.start_servers = .*/pm.start_servers = 2/' \
        /etc/php/8.4/fpm/pool.d/www.conf 2>/dev/null || true"
    run_debian "sed -i 's/^;pm.max_requests = .*/pm.max_requests = 500/' \
        /etc/php/8.4/fpm/pool.d/www.conf 2>/dev/null || true"

    log "Cấu hình Redis..."
    run_debian "mkdir -p /etc/redis"
    run_debian "cat > /etc/redis/redis.conf << 'REDIS'
bind 127.0.0.1
port 6379
maxmemory 64mb
maxmemory-policy allkeys-lru
save \"\"
tcp-keepalive 60
loglevel warning
logfile /var/log/redis/redis-server.log
REDIS"
    run_debian "mkdir -p /var/log/redis && chown redis:redis /var/log/redis 2>/dev/null || true"
    run_debian "rm -f /etc/nginx/sites-enabled/default"
    # Tạo snippets fastcgi-php nếu chưa có
    run_debian "[ -f /etc/nginx/snippets/fastcgi-php.conf ] || cat > /etc/nginx/snippets/fastcgi-php.conf << 'SNIP'
fastcgi_split_path_info ^(.+\\.php)(/.+)\$;
try_files \$fastcgi_script_name =404;
set \$path_info \$fastcgi_path_info;
fastcgi_param PATH_INFO \$path_info;
fastcgi_index index.php;
include fastcgi.conf;
SNIP"

    log "Nginx + PHP-FPM + MariaDB + Redis + WP-CLI xong!"
}

# ============================================================
# BƯỚC 4: NODE.JS + POSTGRESQL + CHROMADB
# ============================================================
step4_extra() {
    section "BƯỚC 4: Cài Node.js + PostgreSQL + ChromaDB"

    log "Cài Node.js 20..."
    run_debian "curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 2>/dev/null && \
        apt install -y nodejs"

    log "Cài PostgreSQL..."
    run_debian "DEBIAN_FRONTEND=noninteractive apt install -y \
        postgresql postgresql-contrib"

    log "Cài ChromaDB..."
    run_debian "pip3 install chromadb --break-system-packages"

    log "Node.js + PostgreSQL + ChromaDB xong!"
}

# ============================================================
# BƯỚC 5: CLOUDFLARED
# ============================================================
step5_cloudflared() {
    section "BƯỚC 5: Cài và cấu hình Cloudflare Tunnel"

    log "Tải cloudflared ARM64..."
    run_debian "wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 \
        -O /usr/local/bin/cloudflared && chmod +x /usr/local/bin/cloudflared"
    run_debian "grep -q '/usr/local/bin' ~/.bashrc || \
        echo 'export PATH=\$PATH:/usr/local/bin:/root/.local/bin' >> ~/.bashrc"

    echo ""
    warn "Sắp đăng nhập Cloudflare - copy link hiện ra và mở trên trình duyệt!"
    echo ""
    run_debian "cloudflared tunnel login"

    echo ""
    read -p "$(echo -e ${CYAN}Nhập tên tunnel [my-server]: ${NC})" TUNNEL_NAME
    TUNNEL_NAME=${TUNNEL_NAME:-my-server}

    log "Tạo tunnel: $TUNNEL_NAME"
    run_debian "cloudflared tunnel create $TUNNEL_NAME 2>/dev/null || true"

    TUNNEL_ID=$(run_debian "cloudflared tunnel list 2>/dev/null | grep '$TUNNEL_NAME' | awk '{print \$1}'")
    log "Tunnel ID: $TUNNEL_ID"

    run_debian "mkdir -p ~/.cloudflared"
    run_debian "cat > ~/.cloudflared/config.yml << EOF
tunnel: $TUNNEL_ID
credentials-file: /root/.cloudflared/$TUNNEL_ID.json

ingress:
  - service: http_status:404
EOF"

    cat > "$DEBIAN_ROOT/root/.vps_config" << EOF
TUNNEL_NAME=$TUNNEL_NAME
TUNNEL_ID=$TUNNEL_ID
TG_ENABLED=false
EOF
    log "Cloudflare Tunnel xong!"
}

# ============================================================
# BƯỚC 6: TELEGRAM CONFIG
# ============================================================
step6_telegram() {
    section "BƯỚC 6: Cấu hình Telegram"
    echo ""
    info "Cần chuẩn bị:"
    info "1. Nhắn @BotFather → /newbot → lấy Token"
    info "2. Nhắn @userinfobot → lấy Chat ID"
    echo ""

    read -p "$(echo -e ${CYAN}Telegram Bot Token [Enter để bỏ qua]: ${NC})" TG_TOKEN
    read -p "$(echo -e ${CYAN}Telegram Chat ID [Enter để bỏ qua]: ${NC})" TG_CHAT_ID

    if [ -n "$TG_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
        sed -i "s/TG_ENABLED=false/TG_ENABLED=true/" "$DEBIAN_ROOT/root/.vps_config"
        echo "TG_TOKEN=$TG_TOKEN" >> "$DEBIAN_ROOT/root/.vps_config"
        echo "TG_CHAT_ID=$TG_CHAT_ID" >> "$DEBIAN_ROOT/root/.vps_config"
        log "Telegram đã cấu hình!"
    else
        warn "Bỏ qua. Sửa ~/.vps_config trong Debian để thêm sau."
    fi
}

# ============================================================
# BƯỚC 7: TẠO TẤT CẢ SCRIPTS
# ============================================================
step7_scripts() {
    section "BƯỚC 7: Tạo scripts quản lý"
    run_debian "mkdir -p ~/scripts ~/logs ~/backup ~/projects"

    # ── start.sh ──────────────────────────────────────────────
    cat > "$DEBIAN_ROOT/root/scripts/start.sh" << 'SCRIPT'
#!/bin/bash
export PATH=$PATH:/usr/local/bin:/root/.local/bin
source ~/.vps_config 2>/dev/null || true

GREEN='\033[0;32m'; NC='\033[0m'
log() { echo -e "${GREEN}[✓]${NC} $1"; }

log "MariaDB..."
pkill -f mysqld 2>/dev/null; sleep 1
mkdir -p /var/run/mysqld /var/log/mysql
chown -R mysql:mysql /var/run/mysqld /var/log/mysql 2>/dev/null || true
mysqld --user=mysql > /var/log/mysql/error.log 2>&1 &
sleep 3

log "Redis..."
mkdir -p /var/log/redis /var/run/redis
chown -R redis:redis /var/log/redis /var/run/redis 2>/dev/null || true
redis-server /etc/redis/redis.conf --daemonize yes >> ~/logs/startup.log 2>&1 || \
    redis-server --daemonize yes --loglevel warning >> ~/logs/startup.log 2>&1 || true
sleep 1

log "PHP-FPM..."
mkdir -p /run/php
php-fpm8.4 --daemonize >> ~/logs/startup.log 2>&1 || true
sleep 1

log "Nginx..."
mkdir -p /var/log/nginx /run
nginx -g "daemon on;" >> ~/logs/startup.log 2>&1 || true
sleep 1

log "PostgreSQL..."
mkdir -p /var/run/postgresql
chown postgres:postgres /var/run/postgresql 2>/dev/null || true
su - postgres -c "pg_ctlcluster 17 main start >> ~/logs/startup.log 2>&1 || true" >> ~/logs/startup.log 2>&1 || true
sleep 2

log "ChromaDB..."
nohup chroma run --host 127.0.0.1 --port 8000 > ~/logs/chromadb.log 2>&1 &
sleep 2

log "Cloudflare Tunnel..."
nohup cloudflared tunnel run $TUNNEL_NAME > ~/logs/cloudflared.log 2>&1 &
sleep 2

log "Auto Recovery..."
pkill -f auto_recover 2>/dev/null || true
nohup bash ~/scripts/auto_recover.sh > ~/logs/auto_recover.log 2>&1 &

log "Health Check..."
pkill -f health_check 2>/dev/null || true
nohup bash ~/scripts/health_check.sh > ~/logs/health_check.log 2>&1 &

echo ""
bash ~/scripts/status.sh
SCRIPT

    # ── stop.sh ───────────────────────────────────────────────
    cat > "$DEBIAN_ROOT/root/scripts/stop.sh" << 'SCRIPT'
#!/bin/bash
echo "Dừng tất cả services..."
pkill -f nginx 2>/dev/null || true
pkill -f php-fpm 2>/dev/null || true
pkill -f mysqld 2>/dev/null || true
PG_VER=$(ls /etc/postgresql/ 2>/dev/null | head -1)
[ -n "$PG_VER" ] && su - postgres -c "pg_ctlcluster $PG_VER main stop 2>/dev/null || true" 2>/dev/null || true
pkill -f postgres 2>/dev/null || true
pkill -f redis-server 2>/dev/null || true
pkill -f cloudflared 2>/dev/null || true
pkill -f chroma 2>/dev/null || true
pkill -f auto_recover 2>/dev/null || true
pkill -f health_check 2>/dev/null || true
echo "Đã dừng tất cả!"
SCRIPT

    # ── status.sh ─────────────────────────────────────────────
    cat > "$DEBIAN_ROOT/root/scripts/status.sh" << 'SCRIPT'
#!/bin/bash
GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

check() {
    if eval "$2" > /dev/null 2>&1; then
        echo -e "  ${GREEN}● RUNNING${NC}  $1"
    else
        echo -e "  ${RED}○ STOPPED${NC}  $1"
    fi
}

echo ""
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${CYAN}            SERVER STATUS                  ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
check "Nginx"         "pgrep nginx"
check "PHP-FPM"       "pgrep php-fpm"
check "MariaDB"       "pgrep mysqld"
check "Redis"         "redis-cli ping"
check "PostgreSQL"    "pgrep postgres"
check "ChromaDB"      "pgrep -f chroma"
check "Cloudflare"    "pgrep cloudflared"
check "AutoRecover"   "pgrep -f auto_recover"
check "HealthCheck"   "pgrep -f health_check"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo ""
echo "  RAM  : $(free -m | awk 'NR==2{printf "%s/%s MB (%.0f%%)", $3,$2,$3*100/$2}')"
echo "  Disk : $(df -h ~ | awk 'NR==2{print $3"/"$2" ("$5")"}')"
echo "  Load : $(uptime | awk -F'load average:' '{print $2}')"
echo ""
echo -e "${CYAN}  WEBSITES:${NC}"
for conf in /etc/nginx/sites-enabled/*; do
    [ -f "$conf" ] || continue
    domain=$(grep -m1 "server_name" "$conf" 2>/dev/null | awk '{print $2}' | tr -d ';')
    [ -n "$domain" ] && echo "  → https://$domain"
done
echo ""
SCRIPT

    # ── monitor.sh ────────────────────────────────────────────
    cat > "$DEBIAN_ROOT/root/scripts/monitor.sh" << 'SCRIPT'
#!/bin/bash
# Real-time monitor: RAM, CPU, Nginx requests, top processes
CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

echo -e "${CYAN}Monitor đang chạy... Ctrl+C để thoát${NC}"
echo ""

while true; do
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          ANDROID VPS MONITOR                 ║${NC}"
    echo -e "${CYAN}║          $(date '+%H:%M:%S  %d/%m/%Y')               ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo ""

    # RAM
    RAM=$(free -m | awk 'NR==2{printf "%s/%s MB (%.0f%%)", $3,$2,$3*100/$2}')
    RAM_PCT=$(free -m | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [ "$RAM_PCT" -gt 80 ]; then
        echo -e "  RAM  : ${RED}$RAM${NC}"
    elif [ "$RAM_PCT" -gt 60 ]; then
        echo -e "  RAM  : ${YELLOW}$RAM${NC}"
    else
        echo -e "  RAM  : ${GREEN}$RAM${NC}"
    fi

    # CPU Load
    LOAD=$(uptime | awk -F'load average:' '{print $2}')
    echo "  Load :$LOAD"

    # Disk
    echo "  Disk : $(df -h ~ | awk 'NR==2{print $3"/"$2" ("$5")"}')"
    echo ""

    # Nginx stats
    echo -e "${CYAN}  NGINX:${NC}"
    NGINX_PROC=$(pgrep nginx | wc -l)
    echo "  Processes: $NGINX_PROC"

    # Recent requests (last 10)
    if [ -f /var/log/nginx/access.log ]; then
        echo "  Requests/min (last): $(tail -100 /var/log/nginx/access.log 2>/dev/null | \
            awk -v d="$(date '+%d/%b/%Y:%H:%M')" '$0 ~ d {count++} END {print count+0}')"
        echo ""
        echo -e "${CYAN}  RECENT REQUESTS:${NC}"
        tail -5 /var/log/nginx/access.log 2>/dev/null | \
            awk '{print "  " $1" "$7" "$9}' || echo "  (no log)"
    fi
    echo ""

    # Top processes
    echo -e "${CYAN}  TOP PROCESSES:${NC}"
    ps aux --sort=-%mem 2>/dev/null | awk 'NR>1 && NR<=7 {
        printf "  %-20s CPU:%-5s MEM:%-5s\n", $11, $3, $4
    }' || true

    echo ""
    echo -e "${CYAN}  SERVICES:${NC}"
    for svc in nginx "php-fpm" mysqld redis-server postgres cloudflared; do
        if pgrep -f "$svc" > /dev/null 2>&1; then
            echo -e "  ${GREEN}●${NC} $svc"
        else
            echo -e "  ${RED}○${NC} $svc"
        fi
    done

    sleep 3
done
SCRIPT

    # ── health_check.sh ───────────────────────────────────────
    cat > "$DEBIAN_ROOT/root/scripts/health_check.sh" << 'SCRIPT'
#!/bin/bash
# Gửi heartbeat Telegram mỗi 5 phút
# Nếu không nhận được tin nhắn > 10 phút = server có vấn đề
source ~/.vps_config 2>/dev/null || true

LOG=~/logs/health_check.log
INTERVAL=300  # 5 phút

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG; }

tg_send() {
    [[ "$TG_ENABLED" == "true" ]] || return
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d chat_id="$TG_CHAT_ID" \
        -d text="$1" \
        -d parse_mode="HTML" > /dev/null 2>&1
}

log "Health Check daemon started"

# Gửi thông báo khởi động
tg_send "🚀 <b>Android VPS Online</b>
⏰ $(date '+%H:%M %d/%m/%Y')
📱 RAM: $(free -m | awk 'NR==2{printf "%s/%s MB", $3,$2}')
💾 Disk: $(df -h ~ | awk 'NR==2{print $3"/"$2" ("$5")"}')"

LAST_REPORT=$(date +%s)

while true; do
    sleep $INTERVAL

    NOW=$(date +%s)
    UPTIME_MIN=$(( (NOW - LAST_REPORT) / 60 ))

    RAM_USED=$(free -m | awk 'NR==2{print $3}')
    RAM_TOTAL=$(free -m | awk 'NR==2{print $2}')
    RAM_PCT=$(free -m | awk 'NR==2{printf "%.0f", $3*100/$2}')
    DISK=$(df -h ~ | awk 'NR==2{print $3"/"$2" ("$5")"}')

    # Đếm websites đang chạy
    SITES=$(ls /etc/nginx/sites-enabled/ 2>/dev/null | wc -l)

    # Icon RAM theo mức
    if [ "$RAM_PCT" -gt 80 ]; then
        RAM_ICON="🔴"
    elif [ "$RAM_PCT" -gt 60 ]; then
        RAM_ICON="🟡"
    else
        RAM_ICON="🟢"
    fi

    tg_send "💓 <b>VPS Heartbeat</b>
⏰ $(date '+%H:%M %d/%m/%Y')
${RAM_ICON} RAM: ${RAM_USED}/${RAM_TOTAL} MB (${RAM_PCT}%)
💾 Disk: $DISK
🌐 Sites: $SITES đang chạy"

    LAST_REPORT=$NOW
    log "Heartbeat sent. RAM: ${RAM_PCT}%"
done
SCRIPT

    # ── auto_recover.sh ───────────────────────────────────────
    cat > "$DEBIAN_ROOT/root/scripts/auto_recover.sh" << 'SCRIPT'
#!/bin/bash
export PATH=$PATH:/usr/local/bin:/root/.local/bin
source ~/.vps_config 2>/dev/null || true

LOG=~/logs/auto_recover.log
RAM_LIMIT=6000
RAM_CRITICAL=7000

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG; }
tg_send() {
    [[ "$TG_ENABLED" == "true" ]] || return
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d chat_id="$TG_CHAT_ID" -d text="$1" > /dev/null 2>&1
}

check_restart() {
    local NAME=$1 CHECK=$2 START=$3
    if ! eval "$CHECK" > /dev/null 2>&1; then
        log "RESTART: $NAME"
        eval "$START" 2>/dev/null; sleep 3
        if eval "$CHECK" > /dev/null 2>&1; then
            log "OK: $NAME restarted"
            tg_send "🔄 $NAME tự restart thành công"
        else
            log "FAIL: $NAME restart failed"
            tg_send "❌ $NAME restart THẤT BẠI!"
        fi
    fi
}

log "=== Auto Recovery started ==="

while true; do
    RAM_USED=$(free -m | awk 'NR==2{print $3}')

    if [ "$RAM_USED" -gt "$RAM_CRITICAL" ]; then
        log "CRITICAL RAM: ${RAM_USED}MB"
        tg_send "🚨 RAM CRITICAL: ${RAM_USED}MB - đang dọn!"
        redis-cli flushall 2>/dev/null || true
        sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
        sleep 10
    elif [ "$RAM_USED" -gt "$RAM_LIMIT" ]; then
        log "HIGH RAM: ${RAM_USED}MB"
        redis-cli flushall 2>/dev/null || true
    fi

    check_restart "Nginx"      "pgrep nginx"       "nginx -g 'daemon on;' >> ~/logs/startup.log 2>&1"
    check_restart "PHP-FPM"    "pgrep php-fpm"     "php-fpm8.4 --daemonize >> ~/logs/startup.log 2>&1"
    check_restart "MariaDB"    "pgrep mysqld"      "mysqld --user=mysql > /var/log/mysql/error.log 2>&1 &"
    check_restart "Redis"      "redis-cli ping"    "redis-server /etc/redis/redis.conf --daemonize yes >> ~/logs/startup.log 2>&1"
    check_restart "PostgreSQL" "pgrep postgres"    "su - postgres -c \"pg_ctlcluster 17 main start\" >> ~/logs/startup.log 2>&1"
    check_restart "ChromaDB"   "pgrep -f chroma"   "nohup chroma run --host 127.0.0.1 --port 8000 >> ~/logs/chromadb.log 2>&1 &"
    check_restart "Cloudflare" "pgrep cloudflared" "nohup cloudflared tunnel run $TUNNEL_NAME >> ~/logs/cloudflared.log 2>&1 &"

    # Log rotation > 10MB
    for F in ~/logs/*.log; do
        [ -f "$F" ] && [ $(stat -c%s "$F" 2>/dev/null || echo 0) -gt 10485760 ] && \
            mv $F ${F}.old && log "Rotated: $F"
    done

    sleep 45
done
SCRIPT

    # ── backup.sh ─────────────────────────────────────────────
    cat > "$DEBIAN_ROOT/root/scripts/backup.sh" << 'SCRIPT'
#!/bin/bash
source ~/.vps_config 2>/dev/null || true
BACKUP_DIR=~/backup
DATE=$(date +%Y%m%d_%H%M%S)
LOG=~/logs/backup.log

mkdir -p $BACKUP_DIR
log()       { echo "[$(date '+%H:%M:%S')] $1" | tee -a $LOG; }
tg_send()   {
    [[ "$TG_ENABLED" == "true" ]] || return
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d chat_id="$TG_CHAT_ID" -d text="$1" > /dev/null 2>&1
}
tg_upload() {
    local FILE=$1 CAPTION=$2
    [[ "$TG_ENABLED" == "true" ]] || return
    local SIZE=$(stat -c%s "$FILE" 2>/dev/null || echo 0)
    if [ $SIZE -lt 52428800 ]; then
        curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendDocument" \
            -F chat_id="$TG_CHAT_ID" \
            -F document=@"$FILE" \
            -F caption="$CAPTION" > /dev/null 2>&1 && \
            log "  → Telegram: $(basename $FILE)"
    else
        log "  → File quá lớn (>50MB), lưu local"
        tg_send "⚠️ $CAPTION: file $(du -sh $FILE | cut -f1) > 50MB, lưu local"
    fi
}

log "=== BACKUP: $DATE ==="
tg_send "🔄 Backup bắt đầu lúc $(date '+%H:%M %d/%m/%Y')"
COUNT=0

for SITE_DIR in /var/www/*/; do
    SITE_NAME=$(basename $SITE_DIR)
    [[ "$SITE_NAME" == "html" ]] && continue

    log "Backup: $SITE_NAME"
    FILES_BAK=$BACKUP_DIR/${SITE_NAME}_files_${DATE}.tar.gz
    tar -czf $FILES_BAK -C /var/www $SITE_NAME 2>/dev/null
    tg_upload "$FILES_BAK" "📁 $SITE_NAME files"

    WP_CONFIG="$SITE_DIR/wp-config.php"
    if [ -f "$WP_CONFIG" ]; then
        DB_NAME=$(grep "DB_NAME" $WP_CONFIG | grep -oP "'\K[^']+(?=')" | tail -1)
        if [ -n "$DB_NAME" ]; then
            DB_BAK=$BACKUP_DIR/${SITE_NAME}_db_${DATE}.sql.gz
            mariadb-dump --user=root --skip-password "$DB_NAME" 2>/dev/null | gzip > $DB_BAK
            tg_upload "$DB_BAK" "🗄️ $SITE_NAME DB ($DB_NAME)"
        fi
    fi
    COUNT=$((COUNT + 1))
done

# Dọn backup cũ > 7 ngày
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete 2>/dev/null
find $BACKUP_DIR -name "*.sql.gz" -mtime +7 -delete 2>/dev/null

log "=== BACKUP XONG: $COUNT sites ==="
tg_send "✅ Backup xong! $COUNT sites. $(date '+%H:%M %d/%m/%Y')"
SCRIPT

    # ── create-site.sh ────────────────────────────────────────
    cat > "$DEBIAN_ROOT/root/scripts/create-site.sh" << 'SCRIPT'
#!/bin/bash
export PATH=$PATH:/usr/local/bin:/root/.local/bin
source ~/.vps_config 2>/dev/null || true

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
ask()  { echo -e "${CYAN}[?]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║           TẠO WEBSITE MỚI               ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  1) WordPress"
echo "  2) NextJS (reverse proxy)"
echo "  3) Static HTML"
echo ""
read -p "Chọn (1-3): " SITE_TYPE

echo ""
ask "Domain đầy đủ (vd: thoigianranh.com hoặc api.thoigianranh.com):"
read DOMAIN

# Subdomain detection
DOT_COUNT=$(echo "$DOMAIN" | tr -cd '.' | wc -c)
IS_SUBDOMAIN=false
[ "$DOT_COUNT" -ge 2 ] && IS_SUBDOMAIN=true

SITE_NAME=$(echo $DOMAIN | sed 's/\./-/g')

# Hàm thêm vào Cloudflare Tunnel
add_to_tunnel() {
    local SERVICE_URL=$1
    log "Cập nhật Cloudflare Tunnel..."
    python3 << PYTHON
import yaml, os

config_path = os.path.expanduser('~/.cloudflared/config.yml')
try:
    with open(config_path) as f:
        config = yaml.safe_load(f)

    new_rules = [{'hostname': '$DOMAIN', 'service': '$SERVICE_URL'}]

    # Thêm www chỉ cho root domain (không phải subdomain)
    if not $IS_SUBDOMAIN:
        new_rules.append({'hostname': 'www.$DOMAIN', 'service': '$SERVICE_URL'})

    existing = [r for r in config['ingress'] if 'hostname' in r]
    catch_all = [r for r in config['ingress'] if 'hostname' not in r]
    existing_domains = [r['hostname'] for r in existing]

    for rule in new_rules:
        if rule['hostname'] not in existing_domains:
            existing.append(rule)

    config['ingress'] = existing + catch_all
    with open(config_path, 'w') as f:
        yaml.dump(config, f, default_flow_style=False)
    print("  Tunnel config OK!")
except Exception as e:
    print(f"  Lỗi: {e}")
PYTHON

    cloudflared tunnel route dns $TUNNEL_NAME $DOMAIN 2>/dev/null && \
        log "DNS $DOMAIN → OK" || \
        warn "Xóa record DNS cũ trên Cloudflare Dashboard trước!"

    if [ "$IS_SUBDOMAIN" = "false" ]; then
        cloudflared tunnel route dns $TUNNEL_NAME www.$DOMAIN 2>/dev/null || true
    fi

    pkill -HUP cloudflared 2>/dev/null || true
}

# Nginx template WordPress (bảo mật đầy đủ)
create_nginx_wordpress() {
    cat > /etc/nginx/sites-available/${SITE_NAME}.conf << NGINX
server {
    listen 8080;
    server_name $DOMAIN$([ "$IS_SUBDOMAIN" = "false" ] && echo " www.$DOMAIN");
    root /var/www/$SITE_NAME;
    index index.php;

    # Cloudflare real IP
    set_real_ip_from 0.0.0.0/0;
    real_ip_header X-Forwarded-For;

    # Rate limiting wp-login (chống brute force)
    location = /wp-login.php {
        limit_req zone=wp_login burst=3 nodelay;
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.4-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_param HTTPS on;
    }

    # Block xmlrpc.php hoàn toàn
    location = /xmlrpc.php {
        deny all;
        return 444;
    }

    # Block truy cập file nhạy cảm
    location ~* /\.(ht|git|env) { deny all; return 444; }
    location ~* wp-config.php { deny all; return 444; }

    # WordPress permalink
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # PHP-FPM
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.4-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_param HTTPS on;
        fastcgi_read_timeout 300;
    }

    # Cache static files 30 ngày
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff2|svg|webp)$ {
        expires 30d;
        add_header Cache-Control "public, no-transform";
        access_log off;
    }

    # Upload size
    client_max_body_size 64M;
}
NGINX
}

create_wordpress() {
    echo ""
    ask "Tên database:"
    read DB_NAME
    ask "Username database:"
    read DB_USER
    ask "Password database:"
    read -s DB_PASS
    echo ""

    echo ""
    echo "  Type    : WordPress + Redis Cache"
    echo "  Domain  : https://$DOMAIN"
    echo "  Thư mục : /var/www/$SITE_NAME"
    echo "  Database: $DB_NAME"
    read -p "Xác nhận? (y/n): " OK
    [[ "$OK" != "y" ]] && exit 0

    log "Tạo database..."
    mariadb --user=root --skip-password << SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

    log "Tải WordPress..."
    mkdir -p /var/www/$SITE_NAME
    cd /tmp
    wget -q https://wordpress.org/latest.tar.gz -O wp.tar.gz
    tar -xzf wp.tar.gz
    cp -r wordpress/* /var/www/$SITE_NAME/
    chown -R www-data:www-data /var/www/$SITE_NAME
    chmod -R 755 /var/www/$SITE_NAME
    rm -f wp.tar.gz

    log "Cấu hình wp-config.php..."
    cp /var/www/$SITE_NAME/wp-config-sample.php /var/www/$SITE_NAME/wp-config.php
    sed -i "s/database_name_here/$DB_NAME/"   /var/www/$SITE_NAME/wp-config.php
    sed -i "s/username_here/$DB_USER/"        /var/www/$SITE_NAME/wp-config.php
    sed -i "s/password_here/$DB_PASS/"        /var/www/$SITE_NAME/wp-config.php

    # Thêm config bảo mật + Redis + HTTPS fix
    cat >> /var/www/$SITE_NAME/wp-config.php << WPEOF

/* Redis Cache */
define('WP_CACHE', true);
define('WP_REDIS_HOST', '127.0.0.1');
define('WP_REDIS_PORT', 6379);

/* Performance */
define('WP_MEMORY_LIMIT', '128M');
define('WP_MAX_MEMORY_LIMIT', '256M');

/* Security */
define('DISALLOW_FILE_EDIT', true);
define('DISALLOW_FILE_MODS', false);
define('WP_AUTO_UPDATE_CORE', 'minor');

/* Cloudflare HTTPS fix */
if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) &&
    \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    \$_SERVER['HTTPS'] = 'on';
}
define('WP_HOME', 'https://${DOMAIN}');
define('WP_SITEURL', 'https://${DOMAIN}');
WPEOF

    log "Tạo Nginx vhost với bảo mật..."
    create_nginx_wordpress
    ln -sf /etc/nginx/sites-available/${SITE_NAME}.conf /etc/nginx/sites-enabled/
    nginx -t && nginx -s reload 2>/dev/null || true
    PHP_FPM=$(ls /usr/sbin/php-fpm* 2>/dev/null | tail -1); [ -n "$PHP_FPM" ] && $PHP_FPM 2>/dev/null || true

    add_to_tunnel "http://localhost:8080"

    # Cài plugins qua WP-CLI
    log "Cài plugins WordPress..."
    cd /var/www/$SITE_NAME

    # Redis Object Cache
    wp plugin install redis-cache --activate --allow-root 2>/dev/null || true
    wp redis enable --allow-root 2>/dev/null || true

    # Cloudflare Flexible SSL - bắt buộc để tránh redirect loop
    wp plugin install cloudflare-flexible-ssl --activate --allow-root 2>/dev/null || true

    echo ""
    log "WordPress tạo xong!"
    echo ""
    echo "  URL     : https://$DOMAIN"
    echo "  Admin   : https://$DOMAIN/wp-admin"
    echo "  Thư mục : /var/www/$SITE_NAME"
    echo "  DB      : $DB_NAME"
    echo ""
    echo "  Plugins đã cài:"
    echo "    ✓ Redis Object Cache"
    echo "    ✓ Cloudflare Flexible SSL"
    echo ""
    echo "  WP-CLI  : vps wp $DOMAIN <command>"
    echo ""
}

create_nextjs() {
    echo ""
    ask "Port NextJS đang chạy [3000]:"
    read NJS_PORT
    NJS_PORT=${NJS_PORT:-3000}

    echo ""
    echo "  Domain : https://$DOMAIN"
    echo "  Proxy  : 127.0.0.1:$NJS_PORT"
    read -p "Xác nhận? (y/n): " OK
    [[ "$OK" != "y" ]] && exit 0

    cat > /etc/nginx/sites-available/${SITE_NAME}.conf << NGINX
server {
    listen 8080;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:$NJS_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 300;
    }
}
NGINX

    ln -sf /etc/nginx/sites-available/${SITE_NAME}.conf /etc/nginx/sites-enabled/
    nginx -t && nginx -s reload 2>/dev/null || true

    add_to_tunnel "http://localhost:8080"

    echo ""
    log "NextJS proxy tạo xong!"
    echo "  URL   : https://$DOMAIN → localhost:$NJS_PORT"
    warn "Đảm bảo NextJS đang chạy trên port $NJS_PORT"
    echo ""
}

create_static() {
    mkdir -p /var/www/$SITE_NAME
    cat > /var/www/$SITE_NAME/index.html << HTML
<!DOCTYPE html>
<html><head><title>$DOMAIN</title></head>
<body><h1>$DOMAIN đang hoạt động!</h1></body></html>
HTML
    chown -R www-data:www-data /var/www/$SITE_NAME

    cat > /etc/nginx/sites-available/${SITE_NAME}.conf << NGINX
server {
    listen 8080;
    server_name $DOMAIN;
    root /var/www/$SITE_NAME;
    index index.html;

    location / { try_files \$uri \$uri/ =404; }
    location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ { expires 30d; }
}
NGINX

    ln -sf /etc/nginx/sites-available/${SITE_NAME}.conf /etc/nginx/sites-enabled/
    nginx -t && nginx -s reload 2>/dev/null || true

    add_to_tunnel "http://localhost:8080"

    echo ""
    log "Static site tạo xong!"
    echo "  URL     : https://$DOMAIN"
    echo "  Thư mục : /var/www/$SITE_NAME"
    echo ""
}

case "$SITE_TYPE" in
    1) create_wordpress ;;
    2) create_nextjs ;;
    3) create_static ;;
    *) echo "Lựa chọn không hợp lệ"; exit 1 ;;
esac
SCRIPT

    # ── wp.sh - WP-CLI helper ─────────────────────────────────
    cat > "$DEBIAN_ROOT/root/scripts/wp.sh" << 'SCRIPT'
#!/bin/bash
# WP-CLI helper - chạy lệnh WP-CLI trên site chỉ định
# Dùng: wp.sh <domain> <wp-cli command>
# Ví dụ: wp.sh thoigianranh.com plugin list

DOMAIN=$1
shift
CMD="$@"

if [ -z "$DOMAIN" ]; then
    echo ""
    echo "Cách dùng: vps wp <domain> <lệnh>"
    echo ""
    echo "Ví dụ:"
    echo "  vps wp thoigianranh.com plugin list"
    echo "  vps wp thoigianranh.com plugin update --all"
    echo "  vps wp thoigianranh.com theme list"
    echo "  vps wp thoigianranh.com core update"
    echo "  vps wp thoigianranh.com user list"
    echo "  vps wp thoigianranh.com cache flush"
    echo "  vps wp thoigianranh.com db export backup.sql"
    echo ""
    exit 0
fi

SITE_NAME=$(echo $DOMAIN | sed 's/\./-/g')
SITE_DIR="/var/www/$SITE_NAME"

if [ ! -d "$SITE_DIR" ]; then
    echo "Không tìm thấy site: $SITE_DIR"
    exit 1
fi

cd $SITE_DIR
wp $CMD --allow-root --path=$SITE_DIR
SCRIPT

    # ── db.sh - Database helper ───────────────────────────────
    cat > "$DEBIAN_ROOT/root/scripts/db.sh" << 'SCRIPT'
#!/bin/bash
# Database helper
CMD=$1
shift

case "$CMD" in
    shell)
        echo "Vào MariaDB shell..."
        mariadb --user=root --skip-password
        ;;
    list)
        echo ""
        echo "DATABASES:"
        mariadb --user=root --skip-password -e "SHOW DATABASES;" 2>/dev/null | \
            grep -v "^Database\|information_schema\|performance_schema\|mysql\|sys"
        echo ""
        ;;
    create)
        DB=$1 USER=$2 PASS=$3
        [ -z "$DB" ] && read -p "Tên database: " DB
        [ -z "$USER" ] && read -p "Username: " USER
        [ -z "$PASS" ] && { read -sp "Password: " PASS; echo; }
        mariadb --user=root --skip-password << SQL
CREATE DATABASE IF NOT EXISTS \`$DB\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$USER'@'localhost' IDENTIFIED BY '$PASS';
GRANT ALL PRIVILEGES ON \`$DB\`.* TO '$USER'@'localhost';
FLUSH PRIVILEGES;
SQL
        echo "Database $DB tạo xong!"
        ;;
    drop)
        DB=$1
        [ -z "$DB" ] && read -p "Tên database cần xóa: " DB
        read -p "Xóa database '$DB'? (y/n): " OK
        [[ "$OK" != "y" ]] && exit 0
        mariadb --user=root --skip-password -e "DROP DATABASE IF EXISTS \`$DB\`;"
        echo "Đã xóa $DB"
        ;;
    export)
        DB=$1 FILE=${2:-~/backup/${1}_$(date +%Y%m%d).sql.gz}
        mariadb-dump --user=root --skip-password "$DB" 2>/dev/null | gzip > $FILE
        echo "Export: $FILE ($(du -sh $FILE | cut -f1))"
        ;;
    import)
        DB=$1 FILE=$2
        [ ! -f "$FILE" ] && echo "File không tồn tại: $FILE" && exit 1
        if [[ "$FILE" == *.gz ]]; then
            gunzip -c "$FILE" | mariadb --user=root --skip-password "$DB"
        else
            mariadb --user=root --skip-password "$DB" < "$FILE"
        fi
        echo "Import xong!"
        ;;
    *)
        echo ""
        echo "Cách dùng: vps db <lệnh>"
        echo ""
        echo "  vps db shell              Vào MariaDB shell"
        echo "  vps db list               Danh sách databases"
        echo "  vps db create [db] [user] Tạo database mới"
        echo "  vps db drop <db>          Xóa database"
        echo "  vps db export <db> [file] Export database"
        echo "  vps db import <db> <file> Import database"
        echo ""
        ;;
esac
SCRIPT

    run_debian "chmod +x ~/scripts/*.sh"
    log "Tất cả scripts tạo xong!"
}

# ============================================================
# BƯỚC 8: TERMUX BOOT
# ============================================================
step8_boot() {
    section "BƯỚC 8: Cài đặt tự động khởi động"
    mkdir -p ~/.termux/boot

    cat > ~/.termux/boot/start-vps.sh << 'BOOT'
#!/data/data/com.termux/files/usr/bin/bash
termux-wake-lock
sleep 15
proot-distro login debian --shared-tmp -- bash -c '
    export PATH=$PATH:/usr/local/bin:/root/.local/bin
    tmux new-session -d -s vps 2>/dev/null || true
    tmux send-keys -t vps "bash ~/scripts/start.sh" Enter
    tmux new-window -t vps
    tmux send-keys -t vps "bash ~/scripts/auto_recover.sh" Enter
' &
BOOT

    chmod +x ~/.termux/boot/start-vps.sh
    log "Boot script xong!"
}

# ============================================================
# BƯỚC 9: LỆNH VPS
# ============================================================
step9_vps_command() {
    section "BƯỚC 9: Tạo lệnh 'vps'"

    cat > "$PREFIX/bin/vps" << 'VPS'
#!/data/data/com.termux/files/usr/bin/bash
CMD=$1; shift

run() { proot-distro login debian --shared-tmp -- bash -c "$1"; }

case "$CMD" in
    start)
        proot-distro login debian --shared-tmp -- bash -c "
            export PATH=\$PATH:/usr/local/bin:/root/.local/bin
            tmux new-session -d -s vps 2>/dev/null || true
            tmux send-keys -t vps 'bash ~/scripts/start.sh' Enter
            sleep 3
            echo 'Đang khởi động... Dùng: vps attach để xem'
        "
        ;;
    stop)    run "bash ~/scripts/stop.sh" ;;
    restart)
        run "bash ~/scripts/stop.sh"
        sleep 3
        proot-distro login debian --shared-tmp -- bash -c "
            export PATH=\$PATH:/usr/local/bin:/root/.local/bin
            tmux new-session -d -s vps 2>/dev/null || true
            tmux send-keys -t vps 'bash ~/scripts/start.sh' Enter
        "
        ;;
    status)   run "bash ~/scripts/status.sh" ;;
    monitor)  proot-distro login debian --shared-tmp -- bash ~/scripts/monitor.sh ;;
    create)   run "bash ~/scripts/create-site.sh" ;;
    backup)   run "bash ~/scripts/backup.sh" ;;
    attach)   proot-distro login debian --shared-tmp -- tmux attach -t vps ;;
    debian)   proot-distro login debian --shared-tmp ;;
    wp)
        DOMAIN=$1; shift
        run "bash ~/scripts/wp.sh $DOMAIN $*"
        ;;
    db)
        run "bash ~/scripts/db.sh $*"
        ;;
    list)
        echo ""
        echo "WEBSITES:"
        run "for f in /etc/nginx/sites-enabled/*; do
            [ -f \"\$f\" ] && grep -m1 'server_name' \"\$f\" | \
            awk '{print \"  → https://\"\$2}' | tr -d ';'
        done"
        echo ""
        ;;
    delete)
        DOMAIN=$1
        SITE_NAME=$(echo $DOMAIN | sed 's/\./-/g')
        echo "Xóa site: $DOMAIN"
        read -p "Chắc chắn? (y/n): " OK
        [[ "$OK" != "y" ]] && exit 0
        run "
            rm -f /etc/nginx/sites-enabled/${SITE_NAME}.conf
            rm -f /etc/nginx/sites-available/${SITE_NAME}.conf
            nginx -s reload 2>/dev/null || true
            echo 'Nginx config đã xóa.'
            echo 'Xóa thủ công nếu cần: /var/www/$SITE_NAME và database'
        "
        ;;
    logs)
        SERVICE=${1:-cloudflared}
        run "tail -f ~/logs/${SERVICE}.log"
        ;;
    *)
        echo ""
        echo "╔═══════════════════════════════════════════════╗"
        echo "║           VPS COMMAND v3.0                    ║"
        echo "╠═══════════════════════════════════════════════╣"
        echo "║  SERVER                                       ║"
        echo "║  vps start              Khởi động server      ║"
        echo "║  vps stop               Dừng server           ║"
        echo "║  vps restart            Restart               ║"
        echo "║  vps status             Trạng thái            ║"
        echo "║  vps monitor            Real-time monitor     ║"
        echo "╠═══════════════════════════════════════════════╣"
        echo "║  WEBSITES                                     ║"
        echo "║  vps create             Tạo site mới          ║"
        echo "║  vps list               Danh sách sites       ║"
        echo "║  vps delete <domain>    Xóa site              ║"
        echo "╠═══════════════════════════════════════════════╣"
        echo "║  DATABASE                                     ║"
        echo "║  vps db shell           Vào MariaDB           ║"
        echo "║  vps db list            Danh sách databases   ║"
        echo "║  vps db create          Tạo database          ║"
        echo "║  vps db export <db>     Export database       ║"
        echo "║  vps db import <db> <f> Import database       ║"
        echo "╠═══════════════════════════════════════════════╣"
        echo "║  WORDPRESS                                    ║"
        echo "║  vps wp <domain> <cmd>  Chạy WP-CLI           ║"
        echo "╠═══════════════════════════════════════════════╣"
        echo "║  KHÁC                                         ║"
        echo "║  vps backup             Backup lên Telegram   ║"
        echo "║  vps attach             Mở tmux               ║"
        echo "║  vps logs [service]     Xem log               ║"
        echo "║  vps debian             Vào Debian shell      ║"
        echo "╚═══════════════════════════════════════════════╝"
        echo ""
        ;;
esac
VPS

    chmod +x "$PREFIX/bin/vps"
    log "Lệnh 'vps' xong!"
}

# ============================================================
# MAIN
# ============================================================
main() {
    clear
    banner

    echo -e "${YELLOW}Cài đặt Android VPS Stack đầy đủ v3.0${NC}"
    echo ""
    echo "  • Nginx + PHP-FPM (nhẹ hơn Apache)"
    echo "  • MariaDB + Redis + WP-CLI"
    echo "  • Node.js 20 + PostgreSQL + ChromaDB"
    echo "  • Cloudflare Tunnel (SSL + IP động)"
    echo "  • tmux + Auto Recovery + Health Check"
    echo "  • Backup Telegram + Monitor real-time"
    echo "  • Bảo mật: Rate limit, block xmlrpc"
    echo "  • Multi-site + Subdomain tự động"
    echo ""
    read -p "Bắt đầu cài đặt? (y/n): " CONFIRM
    [[ "$CONFIRM" != "y" ]] && echo "Hủy." && exit 0

    step1_termux
    step2_debian
    step3_nginx_stack
    step4_extra
    step5_cloudflared
    step6_telegram
    step7_scripts
    step8_boot
    step9_vps_command

    section "✅ CÀI ĐẶT HOÀN TẤT - v3.0"
    echo ""
    echo -e "${GREEN}Lệnh quan trọng:${NC}"
    echo ""
    echo -e "  ${CYAN}vps start${NC}                   Khởi động server"
    echo -e "  ${CYAN}vps status${NC}                  Trạng thái"
    echo -e "  ${CYAN}vps monitor${NC}                 Real-time monitor"
    echo -e "  ${CYAN}vps create${NC}                  Tạo site mới"
    echo -e "  ${CYAN}vps wp thoigianranh.com help${NC} WP-CLI commands"
    echo -e "  ${CYAN}vps db shell${NC}                Vào MariaDB"
    echo -e "  ${CYAN}vps backup${NC}                  Backup Telegram"
    echo -e "  ${CYAN}vps attach${NC}                  Mở tmux"
    echo ""

    read -p "Khởi động server ngay? (y/n): " START_NOW
    if [[ "$START_NOW" == "y" ]]; then
        proot-distro login debian --shared-tmp -- bash -c "
            export PATH=\$PATH:/usr/local/bin:/root/.local/bin
            tmux new-session -d -s vps 2>/dev/null || true
            tmux send-keys -t vps 'bash ~/scripts/start.sh' Enter
            sleep 3
            bash ~/scripts/status.sh
        "
    fi

    echo ""
    log "Done! Dùng 'vps create' để tạo site đầu tiên."

    # Hiển thị thông tin SSH kết nối
    PHONE_IP=$(ip route get 1 2>/dev/null | awk '{print $7; exit}' || \
               ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -1)
    SSH_USER=$(whoami)

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  THÔNG TIN KẾT NỐI SSH (Bitvise SSH Client)    ${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  Host     : ${GREEN}${PHONE_IP:-<IP điện thoại>}${NC}"
    echo -e "  Port     : ${GREEN}8022${NC}"
    echo -e "  Username : ${GREEN}${SSH_USER}${NC}"
    echo -e "  Password : ${GREEN}<password bạn vừa đặt lúc cài>}${NC}"
    echo ""
    echo -e "  ${YELLOW}Lưu ý: Máy tính và điện thoại phải cùng WiFi${NC}"
    echo -e "  ${YELLOW}IP điện thoại có thể đổi → kiểm tra trong WiFi settings${NC}"
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

main
