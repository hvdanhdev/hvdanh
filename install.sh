#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  Android VPS Installer v4.0 (Final Stable)
#  Stack: Nginx + PHP-FPM + MariaDB + Redis + PostgreSQL
#         + WP-CLI + Cloudflare Tunnel
#  Kiến trúc tối ưu: Fix tất cả lỗi proot/auth/menu
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

DEBIAN_ROOT="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/debian"

log()     { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; }
info()    { echo -e "${CYAN}[i]${NC} $1"; }
section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

banner() {
cat << 'EOF'

  ╔══════════════════════════════════════════════════╗
  ║         ANDROID VPS INSTALLER v4.0               ║
  ║  Nginx · PHP-FPM · MariaDB · Redis · WP-CLI      ║
  ║  PostgreSQL · Cloudflare Tunnel                  ║
  ║  Backup Telegram · Health Check · Security       ║
  ║  Multi-site · Subdomain · Monitor · Auto Recovery║
  ╚══════════════════════════════════════════════════╝

EOF
}

# ─── Helper chạy lệnh trong Debian ────────────────────────
run_debian() {
    proot-distro login debian --shared-tmp -- bash -c "$1"
}

# ============================================================
# BƯỚC 1: TERMUX
# ============================================================
step1_termux() {
    section "BƯỚC 1: Cài đặt Termux packages + SSH"

    if command -v proot-distro > /dev/null; then
        warn "Termux tools đã có sẵn, bỏ qua cập nhật package..."
    else
        log "Cập nhật package..."
        pkg update -y && pkg upgrade -y
        log "Cài tools..."
        pkg install -y proot-distro wget curl git openssh python tmux
    fi

    termux-setup-storage || true

    grep -q 'alias debian=' ~/.bashrc 2>/dev/null || \
        echo 'alias debian="proot-distro login debian --shared-tmp"' >> ~/.bashrc

    if ! command -v sshd > /dev/null; then
        pkg install -y openssh
    fi

    if [ ! -f "$HOME/.ssh_password_set" ]; then
        log "Cài đặt SSH server..."
        echo ""
        warn "Đặt password SSH để kết nối từ máy tính (Bitvise):"
        passwd
        touch "$HOME/.ssh_password_set"
    else
        warn "SSH đã cài đặt trước đó."
        read -p "Bạn có muốn đặt lại password SSH? (y/n): " RESET_PW
        if [[ "$RESET_PW" == "y" ]]; then
            passwd
        fi
    fi

    sshd 2>/dev/null || true
    grep -q 'sshd' ~/.bashrc 2>/dev/null || \
        echo 'sshd 2>/dev/null || true' >> ~/.bashrc

    log "Termux + SSH xong!"
}

# ============================================================
# BƯỚC 2: DEBIAN PROOT
# ============================================================
step2_debian() {
    section "BƯỚC 2: Cài Debian proot"

    if [ -d "$DEBIAN_ROOT" ] && [ -f "$DEBIAN_ROOT/etc/debian_version" ]; then
        warn "Debian đã cài, bỏ qua tải xuống..."
    else
        log "Cài Debian..."
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
    if run_debian "command -v nginx > /dev/null"; then
        warn "Dịch vụ đã cài đặt, bỏ qua apt upgrade..."
        run_debian "apt update -qq"
    else
        run_debian "apt update -qq && DEBIAN_FRONTEND=noninteractive apt upgrade -y"
    fi

    log "Tạo thư mục cần thiết..."
    run_debian "mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/nginx/snippets \
        /etc/redis /etc/php \
        /var/log/nginx /var/log/redis /var/log/php \
        /var/www /run/php"

    # Chặn invoke-rc.d tự start service (proot không có systemd)
    log "Cấu hình policy-rc.d..."
    run_debian "echo $'#!/bin/sh\nexit 101' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d"
    run_debian "ln -sf /bin/true /sbin/sysctl 2>/dev/null || true"

    # Thêm repo sury.org cho PHP mới nhất
    log "Cấu hình Repo PHP sury.org..."
    run_debian "DEBIAN_FRONTEND=noninteractive apt install -y lsb-release ca-certificates apt-transport-https curl net-tools psmisc htop procps 2>/dev/null && \
        curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg && \
        sh -c 'echo \"deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ \$(lsb_release -sc) main\" > /etc/apt/sources.list.d/php.list' && \
        apt update -qq"

    if run_debian "command -v nginx > /dev/null"; then
        warn "Nginx đã có sẵn, bỏ qua cài đặt gói..."
    else
        log "Cài Nginx, PHP, MariaDB, Redis..."
        run_debian "DEBIAN_FRONTEND=noninteractive apt install -y \
            nginx \
            php8.4-fpm php8.4-mysql php8.4-curl php8.4-gd php8.4-mbstring \
            php8.4-xml php8.4-zip php8.4-redis php8.4-intl php8.4-bcmath \
            php8.4-imagick php8.4-pgsql \
            mariadb-server redis-server wget git vim tmux \
            python3-pip python3-full python3-yaml \
            cron"
    fi

    log "Cài WP-CLI..."
    run_debian "wget -q https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
        -O /usr/local/bin/wp && chmod +x /usr/local/bin/wp"

    log "Cấu hình Nginx chính..."
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

    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript
               text/xml application/xml image/svg+xml;

    limit_req_zone \$binary_remote_addr zone=wp_login:10m rate=5r/m;
    limit_req_zone \$binary_remote_addr zone=api:10m rate=30r/m;

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
    run_debian "cat > /etc/redis/redis.conf << 'REDIS'
bind 127.0.0.1
port 6379
maxmemory 128mb
maxmemory-policy allkeys-lru
save \"\"
tcp-keepalive 60
loglevel warning
logfile /var/log/redis/redis-server.log
REDIS"
    run_debian "mkdir -p /var/log/redis && chown redis:redis /var/log/redis 2>/dev/null || true"

    run_debian "rm -f /etc/nginx/sites-enabled/default"

    # Snippets fastcgi-php
    run_debian "cat > /etc/nginx/snippets/fastcgi-php.conf << 'SNIP'
fastcgi_split_path_info ^(.+\.php)(/.+)\$;
try_files \$fastcgi_script_name =404;
set \$path_info \$fastcgi_path_info;
fastcgi_param PATH_INFO \$path_info;
fastcgi_index index.php;
include fastcgi.conf;
fastcgi_pass unix:/run/php/php8.4-fpm.sock;
SNIP"

    # ── FIX MARIADB AUTH ──
    log "Cấu hình MariaDB auth đúng cách (trong proot)..."
    run_debian "cat > /root/init_mariadb.sh << 'INITDB'
#!/bin/bash
mkdir -p /var/run/mysqld /var/log/mysql /var/lib/mysql
chown -R mysql:mysql /var/run/mysqld /var/log/mysql /var/lib/mysql 2>/dev/null

if [ ! -d /var/lib/mysql/mysql ]; then
    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null 2>&1
fi

mysqld --user=mysql --skip-networking --skip-grant-tables \
    --socket=/var/run/mysqld/mysqld.sock \
    --pid-file=/var/run/mysqld/mysqld_init.pid > /dev/null 2>&1 &
INIT_PID=\$!
sleep 5

mysql --socket=/var/run/mysqld/mysqld.sock << SQL
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket;
DELETE FROM mysql.user WHERE User='vps_admin';
CREATE USER 'vps_admin'@'localhost' IDENTIFIED BY 'vpsadmin2024';
GRANT ALL PRIVILEGES ON *.* TO 'vps_admin'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL

kill \$INIT_PID 2>/dev/null
sleep 3
pkill -f mysqld 2>/dev/null
sleep 2

echo 'MariaDB auth OK'
INITDB"
    run_debian "chmod +x /root/init_mariadb.sh"
    run_debian "bash /root/init_mariadb.sh"

    # Tạo file .my.cnf
    run_debian "cat > /root/.my.cnf << 'EOF'
[client]
user=vps_admin
password=vpsadmin2024
socket=/var/run/mysqld/mysqld.sock
EOF"
    run_debian "chmod 600 /root/.my.cnf"

    log "Nginx + PHP-FPM + MariaDB + Redis xong!"
}

# ============================================================
# BƯỚC 4: NODE.JS + POSTGRESQL (ChromaDB Removed)
# ============================================================
step4_extra() {
    section "BƯỚC 4: Cài Node.js 20 + PostgreSQL"

    log "Cài Node.js 20..."
    run_debian "curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 2>/dev/null && \
        DEBIAN_FRONTEND=noninteractive apt install -y nodejs"

    log "Cài PostgreSQL..."
    run_debian "DEBIAN_FRONTEND=noninteractive apt install -y postgresql postgresql-contrib"

    log "Khởi tạo PostgreSQL cluster đúng cách..."
    run_debian "cat > /root/init_postgres.sh << 'INITPG'
#!/bin/bash
PG_VER=\$(ls /usr/lib/postgresql/ 2>/dev/null | sort -V | tail -1)
if [ -z \"\$PG_VER\" ]; then
    echo \"Không tìm thấy PostgreSQL\"
    exit 1
fi

PG_DATA=\"/var/lib/postgresql/\$PG_VER/main\"
PG_CONF=\"/etc/postgresql/\$PG_VER/main\"

mkdir -p /var/run/postgresql /var/log/postgresql
chown -R postgres:postgres /var/run/postgresql /var/log/postgresql 2>/dev/null

if [ ! -f \"\$PG_DATA/PG_VERSION\" ]; then
    rm -rf \"\$PG_DATA\"
    mkdir -p \"\$PG_DATA\"
    chown -R postgres:postgres \"\$PG_DATA\"
    su - postgres -c \"pg_ctl initdb -D \$PG_DATA\" 2>&1
fi

sed -i \"s|#unix_socket_directories.*|unix_socket_directories = '/var/run/postgresql'|\" \
    \"\$PG_CONF/postgresql.conf\" 2>/dev/null || true

echo \"PostgreSQL cluster OK: \$PG_VER\"
INITPG"
    run_debian "chmod +x /root/init_postgres.sh"
    run_debian "bash /root/init_postgres.sh"

    log "Node.js + PostgreSQL xong! (Đã loại bỏ ChromaDB để bảo vệ bộ nhớ)"
}

# ============================================================
# BƯỚC 5: CLOUDFLARED
# ============================================================
step5_cloudflared() {
    section "BƯỚC 5: Cài và cấu hình Cloudflare Tunnel"

    log "Tải cloudflared ARM64..."
    run_debian "wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 \
        -O /usr/local/bin/cloudflared && chmod +x /usr/local/bin/cloudflared"
    run_debian "grep -q '/usr/local/bin' /root/.bashrc || \
        echo 'export PATH=\$PATH:/usr/local/bin:/root/.local/bin' >> /root/.bashrc"

    if [ ! -f "$DEBIAN_ROOT/root/.cloudflared/cert.pem" ]; then
        echo ""
        warn "Sắp đăng nhập Cloudflare - copy link hiện ra và mở trên trình duyệt!"
        warn "Sau khi đăng nhập xong, link sẽ tự redirect và Termux sẽ tiếp tục."
        echo ""
        run_debian "cloudflared tunnel login"
    else
        log "Cloudflare certificate đã có sẵn, bỏ qua đăng nhập."
    fi

    echo ""
    read -p "$(echo -e ${CYAN}Nhập tên tunnel [my-server]: ${NC})" TUNNEL_NAME
    TUNNEL_NAME=${TUNNEL_NAME:-my-server}

    log "Xóa tunnel cũ nếu có..."
    run_debian "cloudflared tunnel delete -f '$TUNNEL_NAME' 2>/dev/null || true"

    log "Tạo tunnel: $TUNNEL_NAME"
    CREATE_OUTPUT=$(run_debian "cloudflared tunnel create '$TUNNEL_NAME' 2>&1")
    TUNNEL_ID=$(echo "$CREATE_OUTPUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)

    if [ -z "$TUNNEL_ID" ]; then
        TUNNEL_ID=$(run_debian "cloudflared tunnel list 2>/dev/null" | grep -w "$TUNNEL_NAME" | awk '{print $1}' | head -1)
    fi
    log "Tunnel ID: $TUNNEL_ID"

    if [ -z "$TUNNEL_ID" ]; then
        error "Không lấy được Tunnel ID! Hãy kiểm tra 'cloudflared tunnel list' thủ công."
        return 1
    fi

    run_debian "mkdir -p /root/.cloudflared"
    run_debian "cat > /root/.cloudflared/config.yml << 'EOF'
tunnel: \$TUNNEL_ID
credentials-file: /root/.cloudflared/\$TUNNEL_ID.json

ingress:
  - service: http_status:404
EOF"
    run_debian "sed -i \"s/\\\$TUNNEL_ID/$TUNNEL_ID/g\" /root/.cloudflared/config.yml"

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
        warn "Bỏ qua. Sửa /root/.vps_config trong Debian để thêm sau."
    fi
}

# ============================================================
# BƯỚC 7: TẠO TẤT CẢ SCRIPTS
# ============================================================
step7_scripts() {
    section "BƯỚC 7: Tạo scripts quản lý"

    run_debian "mkdir -p /root/scripts /root/logs /root/backup /root/projects"

    # ── start.sh ──────────────────────────────────────────────
    cat > "$DEBIAN_ROOT/root/scripts/start.sh" << 'SCRIPT'
#!/bin/bash
export PATH=$PATH:/usr/local/bin:/root/.local/bin
source /root/.vps_config 2>/dev/null || true

GREEN='\033[0;32m'; NC='\033[0m'
log() { echo -e "${GREEN}[✓]${NC} $1" | tee -a /root/logs/startup.log; }

mkdir -p /root/logs
echo "--- VPS START: $(date) ---" > /root/logs/startup.log

# MariaDB
log "MariaDB..."
pkill -f mysqld 2>/dev/null; sleep 2
mkdir -p /var/run/mysqld /var/log/mysql
chown -R mysql:mysql /var/run/mysqld /var/log/mysql 2>/dev/null || true

if [ ! -d /var/lib/mysql/mysql ]; then
    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null 2>&1
fi

mysqld --user=mysql \
    --socket=/var/run/mysqld/mysqld.sock \
    --pid-file=/var/run/mysqld/mysqld.pid \
    > /var/log/mysql/error.log 2>&1 &
sleep 3

if ! mysqladmin --defaults-file=/root/.my.cnf ping --silent 2>/dev/null; then
    echo "[!] MariaDB chưa sẵn sàng, đợi thêm..." | tee -a /root/logs/startup.log
    sleep 5
fi

# Redis
log "Redis..."
mkdir -p /var/log/redis /var/run/redis
chown -R redis:redis /var/log/redis /var/run/redis 2>/dev/null || true
redis-server /etc/redis/redis.conf --daemonize no > /root/logs/redis.log 2>&1 &
sleep 1

# PHP-FPM
log "PHP-FPM..."
mkdir -p /run/php
php-fpm8.4 -F -R > /root/logs/php-fpm.log 2>&1 &
sleep 1

# Nginx
log "Nginx..."
mkdir -p /var/log/nginx /run
nginx -g "daemon off;" > /root/logs/nginx.log 2>&1 &
sleep 1

# PostgreSQL
log "PostgreSQL..."
PG_VER=$(ls /usr/lib/postgresql/ 2>/dev/null | sort -V | tail -1)
if [ -n "$PG_VER" ]; then
    PG_DATA="/var/lib/postgresql/$PG_VER/main"
    mkdir -p /var/run/postgresql /var/log/postgresql
    chown -R postgres:postgres /var/run/postgresql /var/log/postgresql 2>/dev/null || true

    if [ ! -f "$PG_DATA/PG_VERSION" ]; then
        su - postgres -c "pg_ctl initdb -D $PG_DATA" >> /root/logs/startup.log 2>&1
    fi

    su - postgres -c "pg_ctl start -D $PG_DATA -l /var/log/postgresql/postgresql.log -w -t 30" >> /root/logs/startup.log 2>&1 &
    sleep 4
else
    echo "[!] PostgreSQL chưa cài" | tee -a /root/logs/startup.log
fi

# Cloudflare Tunnel
log "Cloudflare Tunnel..."
pkill -f cloudflared 2>/dev/null
if [ -n "$TUNNEL_NAME" ] && [ -f "/root/.cloudflared/config.yml" ]; then
    cloudflared tunnel --config /root/.cloudflared/config.yml run "$TUNNEL_NAME" \
        > /root/logs/cloudflared.log 2>&1 &
    sleep 2
else
    echo "[!] Cloudflare chưa cấu hình" | tee -a /root/logs/startup.log
fi

log "Health Check daemon..."
pkill -f health_check.sh 2>/dev/null
nohup bash /root/scripts/health_check.sh > /root/logs/health_check.log 2>&1 &

echo "--- ALL SERVICES STARTED ---" | tee -a /root/logs/startup.log
exec bash /root/scripts/auto_recover.sh
SCRIPT

    # ── stop.sh ───────────────────────────────────────────────
    cat > "$DEBIAN_ROOT/root/scripts/stop.sh" << 'SCRIPT'
#!/bin/bash
echo "Dừng tất cả services..."
pkill -9 -f "nginx" 2>/dev/null || true
pkill -9 -f "php-fpm" 2>/dev/null || true

PG_VER=$(ls /usr/lib/postgresql/ 2>/dev/null | sort -V | tail -1)
if [ -n "$PG_VER" ]; then
    PG_DATA="/var/lib/postgresql/$PG_VER/main"
    su - postgres -c "pg_ctl stop -D $PG_DATA -m fast" 2>/dev/null || true
fi
pkill -9 -f "postgres" 2>/dev/null || true

pkill -9 -f "mysqld" 2>/dev/null || true
pkill -9 -f "redis-server" 2>/dev/null || true
pkill -9 -f "cloudflared" 2>/dev/null || true
pkill -9 -f "auto_recover.sh" 2>/dev/null || true
pkill -9 -f "health_check.sh" 2>/dev/null || true

rm -f /run/nginx.pid /run/php/php8.4-fpm.pid \
      /var/run/mysqld/mysqld.pid /var/run/postgresql/.s.PGSQL.*.lock 2>/dev/null
echo "Đã dừng tất cả!"
SCRIPT

    # ── status.sh ─────────────────────────────────────────────
    cat > "$DEBIAN_ROOT/root/scripts/status.sh" << 'SCRIPT'
#!/bin/bash
GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

check() {
    local NAME=$1 CHECK=$2
    if eval "$CHECK" > /dev/null 2>&1; then
        echo -e "  ${GREEN}● RUNNING${NC}  $1"
    else
        echo -e "  ${RED}○ STOPPED${NC}  $1"
    fi
}

echo ""
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${CYAN}            SERVER STATUS                  ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
check "Nginx"         "pgrep -x nginx"
check "PHP-FPM"       "pgrep -f php-fpm"
check "MariaDB"       "mysqladmin --defaults-file=/root/.my.cnf ping --silent 2>/dev/null"
check "Redis"         "redis-cli ping 2>/dev/null | grep -q PONG"
check "PostgreSQL"    "timeout 2 bash -c 'cat < /dev/null > /dev/tcp/127.0.0.1/5432' 2>/dev/null"
check "Cloudflare"    "pgrep -f cloudflared"
check "AutoRecover"   "pgrep -f auto_recover.sh"
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
export TERM=xterm-256color
CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

while true; do
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          ANDROID VPS MONITOR                 ║${NC}"
    echo -e "${CYAN}║          $(date '+%H:%M:%S  %d/%m/%Y')               ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}"
    echo ""

    RAM_PCT=$(free -m | awk 'NR==2{printf "%.0f", $3*100/$2}')
    RAM=$(free -m | awk 'NR==2{printf "%s/%s MB (%d%%)", $3,$2,$3*100/$2}')
    if [ "${RAM_PCT:-0}" -gt 80 ]; then echo -e "  RAM  : ${RED}$RAM${NC}"
    elif [ "${RAM_PCT:-0}" -gt 60 ]; then echo -e "  RAM  : ${YELLOW}$RAM${NC}"
    else echo -e "  RAM  : ${GREEN}$RAM${NC}"; fi

    echo "  Load : $(uptime | awk -F'load average:' '{print $2}')"
    echo "  Disk : $(df -h ~ | awk 'NR==2{print $3"/"$2" ("$5")"}')"
    echo ""

    echo -e "${CYAN}  SERVICES:${NC}"
    for svc in nginx "php-fpm" mysqld redis-server postgres cloudflared; do
        if pgrep -f "$svc" > /dev/null 2>&1; then echo -e "  ${GREEN}●${NC} $svc"
        else echo -e "  ${RED}○${NC} $svc"; fi
    done

    echo ""
    echo -e "${CYAN}  WEBSITES:${NC}"
    for conf in /etc/nginx/sites-enabled/*; do
        [ -f "$conf" ] || continue
        domain=$(grep -m1 "server_name" "$conf" 2>/dev/null | awk '{print $2}' | tr -d ';')
        [ -n "$domain" ] && echo "  → https://$domain"
    done
    sleep 3
done
SCRIPT

    # ── health_check.sh ───────────────────────────────────────
    cat > "$DEBIAN_ROOT/root/scripts/health_check.sh" << 'SCRIPT'
#!/bin/bash
source /root/.vps_config 2>/dev/null || true
LOG=/root/logs/health_check.log
INTERVAL=300

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG; }
tg_send() {
    [[ "$TG_ENABLED" == "true" ]] || return
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d chat_id="$TG_CHAT_ID" -d text="$1" -d parse_mode="HTML" > /dev/null 2>&1
}

while true; do
    RAM_PCT=$(free -m | awk 'NR==2{printf "%.0f", $3*100/$2}')
    DISK=$(df -h ~ | awk 'NR==2{print $3"/"$2" ("$5")"}')
    SITES=$(ls /etc/nginx/sites-enabled/ 2>/dev/null | wc -l)
    tg_send "💓 <b>VPS Heartbeat</b>: RAM ${RAM_PCT}%, Disk $DISK, Sites $SITES"
    sleep $INTERVAL
done
SCRIPT

    # ── auto_recover.sh ───────────────────────────────────────
    cat > "$DEBIAN_ROOT/root/scripts/auto_recover.sh" << 'SCRIPT'
#!/bin/bash
source /root/.vps_config 2>/dev/null || true
check_restart() {
    local NAME=$1 CHECK=$2 START=$3
    if ! eval "$CHECK" > /dev/null 2>&1; then
        eval "$START" 2>/dev/null
        sleep 4
    fi
}
while true; do
    check_restart "Nginx" "pgrep -x nginx" "nginx -g 'daemon off;' > /root/logs/nginx.log 2>&1 &"
    check_restart "PHP-FPM" "pgrep -f php-fpm" "php-fpm8.4 -F -R > /root/logs/php-fpm.log 2>&1 &"
    check_restart "MariaDB" "mysqladmin --defaults-file=/root/.my.cnf ping --silent 2>/dev/null" \
        "mysqld --user=mysql --socket=/var/run/mysqld/mysqld.sock > /var/log/mysql/error.log 2>&1 &"
    check_restart "Redis" "redis-cli ping | grep -q PONG" "redis-server /etc/redis/redis.conf --daemonize no > /root/logs/redis.log 2>&1 &"
    sleep 45
done
SCRIPT

    # ── create-site.sh ──
    cat > "$DEBIAN_ROOT/root/scripts/create-site.sh" << 'SCRIPT'
#!/bin/bash
source /root/.vps_config 2>/dev/null || true
echo "Tạo Website mới..."
read -p "Domain (vd: example.com): " DOMAIN
[ -z "$DOMAIN" ] && exit 0
SITE_NAME=$(echo "$DOMAIN" | sed 's/\./-/g')
mkdir -p /var/www/$SITE_NAME
echo "<h1>$DOMAIN works!</h1>" > /var/www/$SITE_NAME/index.html
chown -R www-data:www-data /var/www/$SITE_NAME
cat > "/etc/nginx/sites-available/${SITE_NAME}.conf" << NGINX
server {
    listen 8080;
    server_name $DOMAIN;
    root /var/www/$SITE_NAME;
    index index.html;
    location / { try_files \$uri \$uri/ =404; }
}
NGINX
ln -sf /etc/nginx/sites-available/${SITE_NAME}.conf /etc/nginx/sites-enabled/
nginx -s reload 2>/dev/null
echo "Site $DOMAIN đã tạo xong!"
SCRIPT

    run_debian "chmod +x /root/scripts/*.sh"
    log "Tất cả scripts tạo xong!"
}

# ============================================================
# BƯỚC 8: BOOT + COMMAND
# ============================================================
step8_boot() {
    mkdir -p ~/.termux/boot
    cat > ~/.termux/boot/start-vps.sh << 'BOOT'
#!/data/data/com.termux/files/usr/bin/bash
termux-wake-lock
sleep 15
tmux new-session -d -s vps "proot-distro login debian --shared-tmp -- bash /root/scripts/start.sh"
BOOT
    chmod +x ~/.termux/boot/start-vps.sh
}

step9_vps_command() {
    cat > "$PREFIX/bin/vps" << 'VPS'
#!/data/data/com.termux/files/usr/bin/bash
CMD=$1; shift
run() { proot-distro login debian --shared-tmp -- bash -c "$1"; }
case "$CMD" in
    start|restart)
        tmux kill-session -t vps 2>/dev/null || true
        tmux new-session -d -s vps "proot-distro login debian --shared-tmp -- bash /root/scripts/start.sh"
        echo "Đang khởi động Server..."
        sleep 5
        run "bash /root/scripts/status.sh"
        ;;
    stop)    run "bash /root/scripts/stop.sh"; tmux kill-session -t vps 2>/dev/null ;;
    status)  run "bash /root/scripts/status.sh" ;;
    monitor) proot-distro login debian --shared-tmp -- bash /root/scripts/monitor.sh ;;
    create)  run "bash /root/scripts/create-site.sh" ;;
    debug)   run "cat /root/logs/startup.log" ;;
    debian)  proot-distro login debian --shared-tmp ;;
    *)       echo "Gõ 'vps start' hoặc 'vps status' để bắt đầu." ;;
esac
VPS
    chmod +x "$PREFIX/bin/vps"
}

# ============================================================
# MAIN
# ============================================================
main() {
    clear
    banner
    echo "Cài đặt Android VPS Stack v4.0 Final"
    read -p "Bắt đầu? (y/n): " CONFIRM
    [[ "$CONFIRM" != "y" ]] && exit 0

    step1_termux
    step2_debian
    step3_nginx_stack
    step4_extra
    step5_cloudflared
    step6_telegram
    step7_scripts
    step8_boot
    step9_vps_command

    section "CÀI ĐẶT HOÀN TẤT!"
    echo "Sử dụng lệnh 'vps start' để bắt đầu."
}

main
