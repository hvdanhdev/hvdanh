#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  Android VPS Installer v4.0
#  Stack: Nginx + PHP-FPM + MariaDB + Redis + PostgreSQL
#         + ChromaDB + WP-CLI + Cloudflare Tunnel
#  Kiến trúc mới: Fix gốc rễ tất cả lỗi proot/auth/menu
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
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

banner() {
cat << 'EOF'

  ╔═══════════════════════════════════════════════════╗
  ║         ANDROID VPS INSTALLER v4.0               ║
  ║  Nginx · PHP-FPM · MariaDB · Redis · WP-CLI      ║
  ║  PostgreSQL · ChromaDB · Cloudflare Tunnel        ║
  ║  Backup Telegram · Health Check · Security        ║
  ║  Multi-site · Subdomain · Monitor · Auto Recovery ║
  ╚═══════════════════════════════════════════════════╝

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

    # ── FIX MARIADB AUTH (gốc rễ lỗi ERROR 1698) ──────────
    # Vấn đề cũ: mysqld_safe chạy từ Termux nhưng socket trong proot → khác môi trường
    # Giải pháp: tạo script init-mariadb.sh chạy TRONG proot, dùng --skip-grant-tables
    # đúng cách, sau đó dùng unix_socket plugin cho root (không cần password)
    log "Cấu hình MariaDB auth đúng cách (trong proot)..."
    run_debian "cat > /root/init_mariadb.sh << 'INITDB'
#!/bin/bash
# Đảm bảo thư mục và quyền
mkdir -p /var/run/mysqld /var/log/mysql /var/lib/mysql
chown -R mysql:mysql /var/run/mysqld /var/log/mysql /var/lib/mysql 2>/dev/null

# Khởi tạo data dir nếu chưa có
if [ ! -d /var/lib/mysql/mysql ]; then
    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null 2>&1
fi

# Khởi động tạm với skip-grant-tables để sửa auth
mysqld --user=mysql --skip-networking --skip-grant-tables \
    --socket=/var/run/mysqld/mysqld.sock \
    --pid-file=/var/run/mysqld/mysqld_init.pid > /dev/null 2>&1 &
INIT_PID=$!
sleep 5

# Fix auth: root dùng unix_socket (không cần password khi root)
# vps_admin là user để script dùng (native password)
mysql --socket=/var/run/mysqld/mysqld.sock << SQL
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket;
DELETE FROM mysql.user WHERE User='vps_admin';
CREATE USER 'vps_admin'@'localhost' IDENTIFIED BY 'vpsadmin2024';
GRANT ALL PRIVILEGES ON *.* TO 'vps_admin'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL

# Dừng instance tạm
kill $INIT_PID 2>/dev/null
sleep 3
pkill -f mysqld 2>/dev/null
sleep 2

echo "MariaDB auth OK"
INITDB"
    run_debian "chmod +x /root/init_mariadb.sh"
    run_debian "bash /root/init_mariadb.sh"

    # Tạo file .my.cnf dùng vps_admin (để mariadb command tự authenticate)
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
# BƯỚC 4: NODE.JS + POSTGRESQL + CHROMADB
# ============================================================
step4_extra() {
    section "BƯỚC 4: Cài Node.js + PostgreSQL + ChromaDB"

    log "Cài Node.js 20..."
    run_debian "curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 2>/dev/null && \
        DEBIAN_FRONTEND=noninteractive apt install -y nodejs"

    log "Cài PostgreSQL..."
    run_debian "DEBIAN_FRONTEND=noninteractive apt install -y postgresql postgresql-contrib"

    # ── FIX POSTGRESQL (gốc rễ lỗi khởi động trong proot) ──
    # Vấn đề: pg_ctlcluster cần kernel features không có trong proot
    # Giải pháp: dùng pg_ctl trực tiếp với su - postgres
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

# Khởi tạo cluster nếu chưa có
if [ ! -f \"\$PG_DATA/PG_VERSION\" ]; then
    rm -rf \"\$PG_DATA\"
    mkdir -p \"\$PG_DATA\"
    chown -R postgres:postgres \"\$PG_DATA\"
    su - postgres -c \"pg_ctl initdb -D \$PG_DATA\" 2>&1
fi

# Cấu hình listen trên unix socket
sed -i \"s|#unix_socket_directories.*|unix_socket_directories = '/var/run/postgresql'|\" \
    \"\$PG_CONF/postgresql.conf\" 2>/dev/null || true

echo \"PostgreSQL cluster OK: \$PG_VER\"
INITPG"
    run_debian "chmod +x /root/init_postgres.sh"
    run_debian "bash /root/init_postgres.sh"

    log "Cài ChromaDB..."
    run_debian "pip3 install chromadb --break-system-packages --quiet"

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
    # Lấy ID trực tiếp từ output của tunnel create (nếu thành công)
    CREATE_OUTPUT=$(run_debian "cloudflared tunnel create '$TUNNEL_NAME' 2>&1")
    TUNNEL_ID=$(echo "$CREATE_OUTPUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)

    # Fallback: lấy từ danh sách nếu create báo đã tồn tại
    if [ -z "$TUNNEL_ID" ]; then
        TUNNEL_ID=$(run_debian "cloudflared tunnel list 2>/dev/null" | grep -w "$TUNNEL_NAME" | awk '{print $1}' | head -1)
    fi
    log "Tunnel ID: $TUNNEL_ID"

    if [ -z "$TUNNEL_ID" ]; then
        error "Không lấy được Tunnel ID! Hãy kiểm tra 'cloudflared tunnel list' thủ công."
        return 1
    fi

    run_debian "mkdir -p /root/.cloudflared"
    # Ghi config.yml theo cách an toàn hơn, tránh lỗi expansion của local shell
    run_debian "cat > /root/.cloudflared/config.yml << 'EOF'
tunnel: $TUNNEL_ID
credentials-file: /root/.cloudflared/$TUNNEL_ID.json

ingress:
  - service: http_status:404
EOF"
    # Sửa ID trong config.yml (vì heredoc 'EOF' không expand biến)
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

# ─── MariaDB ───────────────────────────────────────────────
log "MariaDB..."
pkill -f mysqld 2>/dev/null; sleep 2
mkdir -p /var/run/mysqld /var/log/mysql
chown -R mysql:mysql /var/run/mysqld /var/log/mysql 2>/dev/null || true

# Khởi tạo datadir nếu chưa có
if [ ! -d /var/lib/mysql/mysql ]; then
    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null 2>&1
fi

mysqld --user=mysql \
    --socket=/var/run/mysqld/mysqld.sock \
    --pid-file=/var/run/mysqld/mysqld.pid \
    > /var/log/mysql/error.log 2>&1 &
sleep 3

# Kiểm tra MariaDB khởi động thành công
if ! mysqladmin --defaults-file=/root/.my.cnf ping --silent 2>/dev/null; then
    echo "[!] MariaDB chưa sẵn sàng, đợi thêm..." | tee -a /root/logs/startup.log
    sleep 5
fi

# ─── Redis ─────────────────────────────────────────────────
log "Redis..."
mkdir -p /var/log/redis /var/run/redis
chown -R redis:redis /var/log/redis /var/run/redis 2>/dev/null || true
redis-server /etc/redis/redis.conf --daemonize no > /root/logs/redis.log 2>&1 &
sleep 1

# ─── PHP-FPM ───────────────────────────────────────────────
log "PHP-FPM..."
mkdir -p /run/php
php-fpm8.4 -F -R > /root/logs/php-fpm.log 2>&1 &
sleep 1

# ─── Nginx ─────────────────────────────────────────────────
log "Nginx..."
mkdir -p /var/log/nginx /run
nginx -g "daemon off;" > /root/logs/nginx.log 2>&1 &
sleep 1

# ─── PostgreSQL ────────────────────────────────────────────
# FIX: dùng pg_ctl trực tiếp, không dùng pg_ctlcluster (cần systemd)
log "PostgreSQL..."
PG_VER=$(ls /usr/lib/postgresql/ 2>/dev/null | sort -V | tail -1)
if [ -n "$PG_VER" ]; then
    PG_DATA="/var/lib/postgresql/$PG_VER/main"
    mkdir -p /var/run/postgresql /var/log/postgresql
    chown -R postgres:postgres /var/run/postgresql /var/log/postgresql 2>/dev/null || true

    # Khởi tạo nếu chưa có
    if [ ! -f "$PG_DATA/PG_VERSION" ]; then
        mkdir -p "$PG_DATA"
        chown -R postgres:postgres "$PG_DATA"
        su - postgres -c "pg_ctl initdb -D $PG_DATA" >> /root/logs/startup.log 2>&1
        # Cấu hình socket
        PG_CONF="/etc/postgresql/$PG_VER/main/postgresql.conf"
        sed -i "s|#unix_socket_directories.*|unix_socket_directories = '/var/run/postgresql'|" \
            "$PG_CONF" 2>/dev/null || true
    fi

    # Start PostgreSQL
    su - postgres -c "pg_ctl start -D $PG_DATA \
        -l /var/log/postgresql/postgresql.log \
        -w -t 30" >> /root/logs/startup.log 2>&1 &
    sleep 4
else
    echo "[!] PostgreSQL chưa cài" | tee -a /root/logs/startup.log
fi

# ─── PostgreSQL + ChromaDB ────────────────────────────────
# Chạy ở Termux native, Debian chỉ log thông tin
log "PostgreSQL + ChromaDB: Được quản lý bởi Termux boot script."
echo "[i] Kiểm tra trạng thái bằng 'vps status'" | tee -a /root/logs/startup.log

# ─── Cloudflare Tunnel ─────────────────────────────────────
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

# Auto Recovery chạy foreground để giữ proot session sống
exec bash /root/scripts/auto_recover.sh
SCRIPT

    # ── stop.sh ───────────────────────────────────────────────
    cat > "$DEBIAN_ROOT/root/scripts/stop.sh" << 'SCRIPT'
#!/bin/bash
echo "Dừng tất cả services..."
pkill -9 -f "nginx" 2>/dev/null || true
pkill -9 -f "php-fpm" 2>/dev/null || true

# PostgreSQL: dừng đúng cách
PG_VER=$(ls /usr/lib/postgresql/ 2>/dev/null | sort -V | tail -1)
if [ -n "$PG_VER" ]; then
    PG_DATA="/var/lib/postgresql/$PG_VER/main"
    su - postgres -c "pg_ctl stop -D $PG_DATA -m fast" 2>/dev/null || true
fi
pkill -9 -f "postgres" 2>/dev/null || true

pkill -9 -f "mysqld" 2>/dev/null || true
pkill -9 -f "redis-server" 2>/dev/null || true
pkill -9 -f "cloudflared" 2>/dev/null || true
pkill -9 -f "chroma" 2>/dev/null || true
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
check "ChromaDB"      "curl -sf http://127.0.0.1:8000/api/v1/heartbeat > /dev/null"
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

echo -e "${CYAN}Monitor đang chạy... Ctrl+C để thoát${NC}"

while true; do
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          ANDROID VPS MONITOR                 ║${NC}"
    echo -e "${CYAN}║          $(date '+%H:%M:%S  %d/%m/%Y')               ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo ""

    RAM_PCT=$(free -m | awk 'NR==2{printf "%.0f", $3*100/$2}')
    RAM_PCT=${RAM_PCT:-0}
    RAM=$(free -m | awk 'NR==2{printf "%s/%s MB (%d%%)", $3,$2,$3*100/$2}')
    if [ "$RAM_PCT" -gt 80 ]; then
        echo -e "  RAM  : ${RED}$RAM${NC}"
    elif [ "$RAM_PCT" -gt 60 ]; then
        echo -e "  RAM  : ${YELLOW}$RAM${NC}"
    else
        echo -e "  RAM  : ${GREEN}$RAM${NC}"
    fi

    echo "  Load : $(uptime | awk -F'load average:' '{print $2}')"
    echo "  Disk : $(df -h ~ | awk 'NR==2{print $3"/"$2" ("$5")"}')"
    echo ""

    echo -e "${CYAN}  SERVICES:${NC}"
    for svc in nginx "php-fpm" mysqld redis-server postgres cloudflared chroma; do
        if pgrep -f "$svc" > /dev/null 2>&1; then
            echo -e "  ${GREEN}●${NC} $svc"
        else
            echo -e "  ${RED}○${NC} $svc"
        fi
    done

    echo ""
    if [ -f /var/log/nginx/access.log ]; then
        echo -e "${CYAN}  RECENT REQUESTS:${NC}"
        tail -5 /var/log/nginx/access.log 2>/dev/null | \
            awk '{print "  " $1" "$7" "$9}' || echo "  (no log)"
    fi

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
INTERVAL=300  # 5 phút

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG; }

tg_send() {
    [[ "$TG_ENABLED" == "true" ]] || return
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d chat_id="$TG_CHAT_ID" \
        -d text="$1" \
        -d parse_mode="HTML" > /dev/null 2>&1
}

log "Health Check started"
tg_send "🚀 <b>Android VPS Online</b>
⏰ $(date '+%H:%M %d/%m/%Y')
📱 RAM: $(free -m | awk 'NR==2{printf "%s/%s MB", $3,$2}')
💾 Disk: $(df -h ~ | awk 'NR==2{print $3"/"$2" ("$5")"}')"

while true; do
    sleep $INTERVAL

    RAM_USED=$(free -m | awk 'NR==2{print $3}')
    RAM_TOTAL=$(free -m | awk 'NR==2{print $2}')
    RAM_PCT=$(free -m | awk 'NR==2{printf "%.0f", $3*100/$2}')
    DISK=$(df -h ~ | awk 'NR==2{print $3"/"$2" ("$5")"}')
    SITES=$(ls /etc/nginx/sites-enabled/ 2>/dev/null | wc -l)

    if [ "${RAM_PCT:-0}" -gt 80 ]; then
        RAM_ICON="🔴"
    elif [ "${RAM_PCT:-0}" -gt 60 ]; then
        RAM_ICON="🟡"
    else
        RAM_ICON="🟢"
    fi

    tg_send "💓 <b>VPS Heartbeat</b>
⏰ $(date '+%H:%M %d/%m/%Y')
${RAM_ICON} RAM: ${RAM_USED}/${RAM_TOTAL} MB (${RAM_PCT}%)
💾 Disk: $DISK
🌐 Sites: $SITES đang chạy"

    log "Heartbeat sent. RAM: ${RAM_PCT}%"
done
SCRIPT

    # ── auto_recover.sh ───────────────────────────────────────
    cat > "$DEBIAN_ROOT/root/scripts/auto_recover.sh" << 'SCRIPT'
#!/bin/bash
export PATH=$PATH:/usr/local/bin:/root/.local/bin
source /root/.vps_config 2>/dev/null || true

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a /root/logs/auto_recover.log; }

tg_send() {
    [[ "$TG_ENABLED" == "true" ]] || return
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d chat_id="$TG_CHAT_ID" -d text="$1" > /dev/null 2>&1
}

check_restart() {
    local NAME=$1 CHECK=$2 START=$3
    if ! eval "$CHECK" > /dev/null 2>&1; then
        log "WARN: $NAME stopped → restarting..."
        eval "$START" 2>/dev/null
        sleep 4
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
RAM_LIMIT=6500
RAM_CRITICAL=7500

PG_VER=$(ls /usr/lib/postgresql/ 2>/dev/null | sort -V | tail -1)
PG_DATA="/var/lib/postgresql/${PG_VER}/main"

while true; do
    RAM_USED=$(free -m | awk 'NR==2{print $3}')

    if [ "${RAM_USED:-0}" -gt "$RAM_CRITICAL" ]; then
        log "CRITICAL RAM: ${RAM_USED}MB"
        tg_send "🚨 RAM CRITICAL: ${RAM_USED}MB - đang dọn!"
        redis-cli flushall 2>/dev/null || true
        sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
        sleep 10
    elif [ "${RAM_USED:-0}" -gt "$RAM_LIMIT" ]; then
        log "HIGH RAM: ${RAM_USED}MB - flush Redis cache"
        redis-cli flushall 2>/dev/null || true
    fi

    check_restart "Nginx" \
        "pgrep -x nginx" \
        "nginx -g 'daemon off;' > /root/logs/nginx.log 2>&1 &"

    check_restart "PHP-FPM" \
        "pgrep -f php-fpm" \
        "php-fpm8.4 -F -R > /root/logs/php-fpm.log 2>&1 &"

    check_restart "MariaDB" \
        "mysqladmin --defaults-file=/root/.my.cnf ping --silent 2>/dev/null" \
        "mysqld --user=mysql --socket=/var/run/mysqld/mysqld.sock \
            --pid-file=/var/run/mysqld/mysqld.pid \
            > /var/log/mysql/error.log 2>&1 &"

    check_restart "Redis" \
        "redis-cli ping 2>/dev/null | grep -q PONG" \
        "redis-server /etc/redis/redis.conf --daemonize no > /root/logs/redis.log 2>&1 &"

    # PostgreSQL + ChromaDB: Chạy ở Termux native, không restart từ Debian proot
    # (Tránh lỗi command not found trong auto_recover.log)

    check_restart "Cloudflare" \
        "pgrep -f cloudflared" \
        "cloudflared tunnel --config /root/.cloudflared/config.yml run \$TUNNEL_NAME \
            > /root/logs/cloudflared.log 2>&1 &"

    # Log rotation > 10MB
    for F in /root/logs/*.log; do
        [ -f "$F" ] && [ "$(stat -c%s "$F" 2>/dev/null || echo 0)" -gt 10485760 ] && \
            mv "$F" "${F}.old" && log "Rotated: $F"
    done

    sleep 45
done
SCRIPT

    # ── backup.sh ─────────────────────────────────────────────
    cat > "$DEBIAN_ROOT/root/scripts/backup.sh" << 'SCRIPT'
#!/bin/bash
source /root/.vps_config 2>/dev/null || true
BACKUP_DIR=/root/backup
DATE=$(date +%Y%m%d_%H%M%S)
LOG=/root/logs/backup.log

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
    if [ "$SIZE" -lt 52428800 ]; then
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
    tar -czf "$FILES_BAK" -C /var/www "$SITE_NAME" 2>/dev/null
    tg_upload "$FILES_BAK" "📁 $SITE_NAME files"

    WP_CONFIG="$SITE_DIR/wp-config.php"
    if [ -f "$WP_CONFIG" ]; then
        DB_NAME=$(grep "DB_NAME" "$WP_CONFIG" | grep -oP "'\K[^']+(?=')" | tail -1)
        if [ -n "$DB_NAME" ]; then
            DB_BAK=$BACKUP_DIR/${SITE_NAME}_db_${DATE}.sql.gz
            mariadb-dump --defaults-file=/root/.my.cnf "$DB_NAME" 2>/dev/null | gzip > "$DB_BAK"
            tg_upload "$DB_BAK" "🗄️ $SITE_NAME DB ($DB_NAME)"
        fi
    fi
    COUNT=$((COUNT + 1))
done

find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete 2>/dev/null
find $BACKUP_DIR -name "*.sql.gz" -mtime +7 -delete 2>/dev/null

log "=== BACKUP XONG: $COUNT sites ==="
tg_send "✅ Backup xong! $COUNT sites. $(date '+%H:%M %d/%m/%Y')"
SCRIPT

    # ── create-site.sh ────────────────────────────────────────
    # FIX QUAN TRỌNG:
    # 1. Tất cả hàm dùng `return` thay vì `exit` → không văng ra menu
    # 2. MariaDB dùng --defaults-file=/root/.my.cnf (vps_admin user)
    # 3. WP-CLI check DB trước khi install plugin → dùng subshell tránh lỗi
    cat > "$DEBIAN_ROOT/root/scripts/create-site.sh" << 'SCRIPT'
#!/bin/bash
export PATH=$PATH:/usr/local/bin:/root/.local/bin
source /root/.vps_config 2>/dev/null || true

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()   { echo -e "${GREEN}[✓]${NC} $1"; }
ask()   { echo -e "${CYAN}[?]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[✗]${NC} $1"; }

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
ask "Domain đầy đủ (vd: example.com hoặc api.example.com):"
read -r DOMAIN

if [ -z "$DOMAIN" ]; then
    err "Domain không được để trống!"
    exit 0
fi

DOT_COUNT=$(echo "$DOMAIN" | tr -cd '.' | wc -c)
IS_SUBDOMAIN=false
[ "$DOT_COUNT" -ge 2 ] && IS_SUBDOMAIN=true

SITE_NAME=$(echo "$DOMAIN" | sed 's/\./-/g')

# ── Hàm cập nhật Cloudflare Tunnel config ─────────────────
add_to_tunnel() {
    local SERVICE_URL=$1
    log "Cập nhật Cloudflare Tunnel..."

    python3 << PYTHON
import yaml, os, sys

config_path = os.path.expanduser('~/.cloudflared/config.yml')
try:
    with open(config_path) as f:
        config = yaml.safe_load(f)
except Exception as e:
    print(f"  Không đọc được config: {e}")
    sys.exit(0)

new_rules = [{'hostname': '${DOMAIN}', 'service': '${SERVICE_URL}'}]

if "${IS_SUBDOMAIN}" == "false":
    new_rules.append({'hostname': 'www.${DOMAIN}', 'service': '${SERVICE_URL}'})

existing = [r for r in config.get('ingress', []) if 'hostname' in r]
catch_all = [r for r in config.get('ingress', []) if 'hostname' not in r]
existing_domains = [r['hostname'] for r in existing]

for rule in new_rules:
    if rule['hostname'] not in existing_domains:
        existing.append(rule)

config['ingress'] = existing + catch_all
with open(config_path, 'w') as f:
    yaml.dump(config, f, default_flow_style=False, allow_unicode=True)
print("  Tunnel config cập nhật OK!")
PYTHON

    cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN" 2>/dev/null && \
        log "DNS $DOMAIN → OK" || \
        warn "Xóa record DNS cũ trên Cloudflare Dashboard nếu bị lỗi!"

    if [ "$IS_SUBDOMAIN" = "false" ]; then
        cloudflared tunnel route dns "$TUNNEL_NAME" "www.$DOMAIN" 2>/dev/null || true
    fi

    pkill -HUP cloudflared 2>/dev/null || true
}

# ── Nginx config cho WordPress ─────────────────────────────
create_nginx_wordpress() {
    local EXTRA_SERVER_NAME=""
    [ "$IS_SUBDOMAIN" = "false" ] && EXTRA_SERVER_NAME=" www.$DOMAIN"

    cat > "/etc/nginx/sites-available/${SITE_NAME}.conf" << NGINX
server {
    listen 8080;
    server_name ${DOMAIN}${EXTRA_SERVER_NAME};
    root /var/www/${SITE_NAME};
    index index.php;

    set_real_ip_from 0.0.0.0/0;
    real_ip_header X-Forwarded-For;

    location = /wp-login.php {
        limit_req zone=wp_login burst=3 nodelay;
        include snippets/fastcgi-php.conf;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_param HTTPS on;
    }

    location = /xmlrpc.php { deny all; return 444; }
    location ~* /\.(ht|git|env) { deny all; return 444; }
    location ~* wp-config.php { deny all; return 444; }

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_param HTTPS on;
        fastcgi_read_timeout 300;
    }

    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff2|svg|webp)\$ {
        expires 30d;
        add_header Cache-Control "public, no-transform";
        access_log off;
    }

    client_max_body_size 64M;
}
NGINX
}

# ── Tạo WordPress ──────────────────────────────────────────
create_wordpress() {
    echo ""
    ask "Tên database (vd: myblog_db):"
    read -r DB_NAME
    ask "Username database (vd: myblog_user):"
    read -r DB_USER
    ask "Password database:"
    read -rs DB_PASS
    echo ""

    if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASS" ]; then
        err "Database info không được để trống!"
        return 1
    fi

    echo ""
    echo "  Type    : WordPress + Redis Cache"
    echo "  Domain  : https://$DOMAIN"
    echo "  Thư mục : /var/www/$SITE_NAME"
    echo "  Database: $DB_NAME / $DB_USER"
    read -p "Xác nhận? (y/n): " OK
    [ "$OK" != "y" ] && return 0

    # ── Tạo database (FIX: dùng .my.cnf → vps_admin có quyền đầy đủ) ──
    log "Tạo database..."
    if mariadb --defaults-file=/root/.my.cnf << SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
    then
        log "Database tạo thành công!"
    else
        err "Lỗi tạo database! Kiểm tra MariaDB đang chạy: pgrep mysqld"
        return 1
    fi

    log "Tải WordPress..."
    mkdir -p /var/www/$SITE_NAME
    cd /tmp || return 1
    wget -q https://wordpress.org/latest.tar.gz -O wp.tar.gz
    tar -xzf wp.tar.gz
    cp -r wordpress/. /var/www/$SITE_NAME/
    chown -R www-data:www-data /var/www/$SITE_NAME
    chmod -R 755 /var/www/$SITE_NAME
    rm -rf /tmp/wordpress /tmp/wp.tar.gz

    log "Cấu hình wp-config.php..."
    cp /var/www/$SITE_NAME/wp-config-sample.php /var/www/$SITE_NAME/wp-config.php
    sed -i "s/database_name_here/$DB_NAME/"   /var/www/$SITE_NAME/wp-config.php
    sed -i "s/username_here/$DB_USER/"        /var/www/$SITE_NAME/wp-config.php
    sed -i "s/password_here/$DB_PASS/"        /var/www/$SITE_NAME/wp-config.php

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

    log "Tạo Nginx vhost..."
    create_nginx_wordpress
    ln -sf /etc/nginx/sites-available/${SITE_NAME}.conf /etc/nginx/sites-enabled/
    nginx -t 2>/dev/null && nginx -s reload 2>/dev/null || warn "Nginx reload lỗi, kiểm tra lại"

    add_to_tunnel "http://localhost:8080"

    # ── Cài plugins qua WP-CLI ─────────────────────────────
    # FIX: chạy trong subshell, dùng --skip-check nếu WP chưa install
    # Không để lỗi WP-CLI làm văng script ra ngoài
    log "Cài plugins WordPress..."
    cd /var/www/$SITE_NAME || true

    # Chờ MariaDB sẵn sàng
    local RETRY=0
    while [ $RETRY -lt 5 ]; do
        if wp db check --allow-root --quiet 2>/dev/null; then
            break
        fi
        RETRY=$((RETRY + 1))
        warn "DB chưa sẵn sàng, thử lại lần $RETRY/5..."
        sleep 3
    done

    if wp db check --allow-root --quiet 2>/dev/null; then
        # Cài redis-cache
        if wp plugin install redis-cache --activate --allow-root 2>/dev/null; then
            wp redis enable --allow-root 2>/dev/null || true
            log "Plugin redis-cache đã cài!"
        else
            warn "Không cài được redis-cache (bỏ qua)"
        fi

        # Cài cloudflare-flexible-ssl
        if wp plugin install cloudflare-flexible-ssl --activate --allow-root 2>/dev/null; then
            log "Plugin cloudflare-flexible-ssl đã cài!"
        else
            warn "Không cài được cloudflare-flexible-ssl (bỏ qua)"
        fi
    else
        warn "WP chưa được install (chưa chạy wp core install). Cài plugin sau qua: vps wp $DOMAIN plugin install redis-cache --activate"
    fi

    echo ""
    log "WordPress tạo xong!"
    echo ""
    echo "  URL     : https://$DOMAIN"
    echo "  Admin   : https://$DOMAIN/wp-admin"
    echo "  Thư mục : /var/www/$SITE_NAME"
    echo "  DB      : $DB_NAME | User: $DB_USER"
    echo ""
    echo "  WP-CLI  : vps wp $DOMAIN <command>"
    echo ""
}

# ── Tạo NextJS ────────────────────────────────────────────
create_nextjs() {
    echo ""
    ask "Port NextJS đang chạy [3000]:"
    read -r NJS_PORT
    NJS_PORT=${NJS_PORT:-3000}

    echo ""
    echo "  Domain : https://$DOMAIN"
    echo "  Proxy  : 127.0.0.1:$NJS_PORT"
    read -p "Xác nhận? (y/n): " OK
    [ "$OK" != "y" ] && return 0

    cat > "/etc/nginx/sites-available/${SITE_NAME}.conf" << NGINX
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
    nginx -t 2>/dev/null && nginx -s reload 2>/dev/null || warn "Nginx reload lỗi"

    add_to_tunnel "http://localhost:8080"

    echo ""
    log "NextJS proxy tạo xong!"
    echo "  URL   : https://$DOMAIN → localhost:$NJS_PORT"
    warn "Đảm bảo NextJS đang chạy trên port $NJS_PORT"
    echo ""
}

# ── Tạo Static HTML ───────────────────────────────────────
create_static() {
    mkdir -p /var/www/$SITE_NAME
    cat > /var/www/$SITE_NAME/index.html << HTML
<!DOCTYPE html>
<html lang="vi">
<head><meta charset="UTF-8"><title>$DOMAIN</title></head>
<body><h1>$DOMAIN đang hoạt động!</h1></body>
</html>
HTML
    chown -R www-data:www-data /var/www/$SITE_NAME

    cat > "/etc/nginx/sites-available/${SITE_NAME}.conf" << NGINX
server {
    listen 8080;
    server_name $DOMAIN;
    root /var/www/$SITE_NAME;
    index index.html;
    location / { try_files \$uri \$uri/ =404; }
    location ~* \.(jpg|jpeg|png|gif|ico|css|js)\$ { expires 30d; }
}
NGINX

    ln -sf /etc/nginx/sites-available/${SITE_NAME}.conf /etc/nginx/sites-enabled/
    nginx -t 2>/dev/null && nginx -s reload 2>/dev/null || warn "Nginx reload lỗi"

    add_to_tunnel "http://localhost:8080"

    echo ""
    log "Static site tạo xong!"
    echo "  URL     : https://$DOMAIN"
    echo "  Thư mục : /var/www/$SITE_NAME"
    echo ""
}

# ── Dispatch ──────────────────────────────────────────────
case "$SITE_TYPE" in
    1) create_wordpress ;;
    2) create_nextjs ;;
    3) create_static ;;
    *) err "Lựa chọn không hợp lệ"; exit 0 ;;
esac
SCRIPT

    # ── wp.sh ─────────────────────────────────────────────────
    cat > "$DEBIAN_ROOT/root/scripts/wp.sh" << 'SCRIPT'
#!/bin/bash
DOMAIN=$1; shift; CMD="$*"

if [ -z "$DOMAIN" ]; then
    echo ""
    echo "Cách dùng: vps wp <domain> <lệnh>"
    echo ""
    echo "Ví dụ:"
    echo "  vps wp example.com plugin list"
    echo "  vps wp example.com plugin update --all"
    echo "  vps wp example.com cache flush"
    echo "  vps wp example.com db export backup.sql"
    echo ""
    exit 0
fi

SITE_NAME=$(echo "$DOMAIN" | sed 's/\./-/g')
SITE_DIR="/var/www/$SITE_NAME"

if [ ! -d "$SITE_DIR" ]; then
    echo "Không tìm thấy site: $SITE_DIR"
    exit 1
fi

cd "$SITE_DIR"
wp $CMD --allow-root --path="$SITE_DIR"
SCRIPT

    # ── db.sh ─────────────────────────────────────────────────
    cat > "$DEBIAN_ROOT/root/scripts/db.sh" << 'SCRIPT'
#!/bin/bash
CMD=$1; shift

case "$CMD" in
    shell)
        echo "Vào MariaDB shell (vps_admin)..."
        mariadb --defaults-file=/root/.my.cnf
        ;;
    list)
        echo ""
        echo "DATABASES:"
        mariadb --defaults-file=/root/.my.cnf -e "SHOW DATABASES;" 2>/dev/null | \
            grep -v "^Database\|information_schema\|performance_schema\|mysql\|sys"
        echo ""
        ;;
    create)
        DB=$1 USER=$2 PASS=$3
        [ -z "$DB" ]   && read -p "Tên database: " DB
        [ -z "$USER" ] && read -p "Username: " USER
        [ -z "$PASS" ] && { read -sp "Password: " PASS; echo; }
        mariadb --defaults-file=/root/.my.cnf << SQL
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
        [ "$OK" != "y" ] && exit 0
        mariadb --defaults-file=/root/.my.cnf -e "DROP DATABASE IF EXISTS \`$DB\`;"
        echo "Đã xóa $DB"
        ;;
    export)
        DB=$1
        FILE=${2:-/root/backup/${DB}_$(date +%Y%m%d).sql.gz}
        mkdir -p "$(dirname $FILE)"
        mariadb-dump --defaults-file=/root/.my.cnf "$DB" 2>/dev/null | gzip > "$FILE"
        echo "Export: $FILE ($(du -sh "$FILE" | cut -f1))"
        ;;
    import)
        DB=$1 FILE=$2
        [ ! -f "$FILE" ] && echo "File không tồn tại: $FILE" && exit 1
        if [[ "$FILE" == *.gz ]]; then
            gunzip -c "$FILE" | mariadb --defaults-file=/root/.my.cnf "$DB"
        else
            mariadb --defaults-file=/root/.my.cnf "$DB" < "$FILE"
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

    # ── pg.sh - PostgreSQL helper ──────────────────────────────
    cat > "$DEBIAN_ROOT/root/scripts/pg.sh" << 'SCRIPT'
#!/bin/bash
# PostgreSQL helper - tương tự db.sh nhưng cho PostgreSQL
CMD=$1; shift

PG_CMD() { su - postgres -c "psql -c \"$1\"" 2>/dev/null; }

case "$CMD" in
    shell)
        echo "Vào PostgreSQL shell..."
        su - postgres -c "psql"
        ;;
    list)
        echo ""; echo "DATABASES:"
        su - postgres -c "psql -c '\l'" 2>/dev/null
        echo ""
        ;;
    create)
        DB=$1 USER=$2 PASS=$3
        [ -z "$DB" ]   && read -p "Tên database: " DB
        [ -z "$USER" ] && read -p "Username: " USER
        [ -z "$PASS" ] && { read -sp "Password: " PASS; echo; }
        su - postgres -c "psql << SQL
CREATE DATABASE \"$DB\";
CREATE USER \"$USER\" WITH ENCRYPTED PASSWORD '$PASS';
GRANT ALL PRIVILEGES ON DATABASE \"$DB\" TO \"$USER\";
SQL" 2>/dev/null
        echo "PostgreSQL database '$DB' tạo xong!"
        ;;
    drop)
        DB=$1
        [ -z "$DB" ] && read -p "Tên database: " DB
        read -p "Xóa '$DB'? (y/n): " OK; [ "$OK" != "y" ] && exit 0
        su - postgres -c "psql -c 'DROP DATABASE IF EXISTS \"$DB\";'" 2>/dev/null
        echo "Đã xóa $DB"
        ;;
    *)
        echo "Cách dùng: vps pg <shell|list|create|drop>"
        ;;
esac
SCRIPT

    run_debian "chmod +x /root/scripts/*.sh"

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
tmux new-session -d -s vps 2>/dev/null || true
tmux send-keys -t vps "proot-distro login debian --shared-tmp -- bash /root/scripts/start.sh" Enter
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
CYAN='\033[0;36m'; NC='\033[0m'
CMD=$1; shift

run() { proot-distro login debian --shared-tmp -- bash -c "$1"; }

case "$CMD" in
    start|restart)
        echo "Khởi động Server..."
        tmux kill-session -t vps 2>/dev/null || true
        run "bash /root/scripts/stop.sh"
        sleep 2
        tmux new-session -d -s vps 2>/dev/null || true
        tmux send-keys -t vps "proot-distro login debian --shared-tmp -- bash /root/scripts/start.sh" Enter
        echo "Đang đợi services khởi động (15s)..."
        sleep 15
        run "bash /root/scripts/status.sh"
        ;;
    stop)    run "bash /root/scripts/stop.sh" ;;
    status)  run "bash /root/scripts/status.sh" ;;
    monitor) proot-distro login debian --shared-tmp -- bash /root/scripts/monitor.sh ;;
    create)  run "bash /root/scripts/create-site.sh" ;;
    backup)  run "bash /root/scripts/backup.sh" ;;
    attach)  tmux attach -t vps ;;
    debian)  proot-distro login debian --shared-tmp ;;
    wp)
        DOMAIN=$1; shift
        run "bash /root/scripts/wp.sh $DOMAIN $*"
        ;;
    db)
        run "bash /root/scripts/db.sh $*"
        ;;
    pg)
        run "bash /root/scripts/pg.sh $*"
        ;;
    debug)
        echo "==== STARTUP LOG ===="
        proot-distro login debian --shared-tmp -- cat /root/logs/startup.log 2>/dev/null || echo 'Không có log.'
        echo "==== CLOUDFLARE LOG ===="
        proot-distro login debian --shared-tmp -- tail -20 /root/logs/cloudflared.log 2>/dev/null
        echo "==== NGINX ERROR ===="
        proot-distro login debian --shared-tmp -- tail -20 /var/log/nginx/error.log 2>/dev/null
        echo "==== MARIADB ERROR ===="
        proot-distro login debian --shared-tmp -- tail -20 /var/log/mysql/error.log 2>/dev/null
        echo "==== POSTGRESQL LOG ===="
        proot-distro login debian --shared-tmp -- tail -20 /var/log/postgresql/postgresql.log 2>/dev/null
        echo "==== CHROMADB LOG ===="
        proot-distro login debian --shared-tmp -- tail -20 /root/logs/chromadb.log 2>/dev/null
        echo "==== AUTO RECOVER LOG ===="
        proot-distro login debian --shared-tmp -- tail -20 /root/logs/auto_recover.log 2>/dev/null
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
        if [ -z "$DOMAIN" ]; then
            echo "Sites hiện có:"
            run "ls /etc/nginx/sites-enabled/ 2>/dev/null | sed 's/\.conf//g; s/-/./g'"
            read -p "Nhập Domain cần xóa: " DOMAIN
        fi
        SITE_NAME=$(echo "$DOMAIN" | sed 's/\./-/g')
        echo "Xóa Website: $DOMAIN"
        read -p "Chắc chắn? (y/n): " OK
        [ "$OK" != "y" ] && exit 0

        run "
            rm -f /etc/nginx/sites-enabled/${SITE_NAME}.conf
            rm -f /etc/nginx/sites-available/${SITE_NAME}.conf
            nginx -s reload 2>/dev/null || true
            rm -rf /var/www/${SITE_NAME}
            python3 << PYTHON
import yaml, os
config_path = os.path.expanduser('~/.cloudflared/config.yml')
if os.path.exists(config_path):
    with open(config_path) as f:
        config = yaml.safe_load(f)
    if config and 'ingress' in config:
        config['ingress'] = [r for r in config['ingress']
                             if r.get('hostname') not in ['$DOMAIN', 'www.$DOMAIN']]
        with open(config_path, 'w') as f:
            yaml.dump(config, f, default_flow_style=False)
PYTHON
            pkill -HUP cloudflared 2>/dev/null || true
            echo 'Đã xóa website và dọn tunnel config.'
            echo 'Vào Cloudflare Dashboard để xóa DNS record thủ công.'
        "
        ;;
    logs)
        SERVICE=${1:-cloudflared}
        run "tail -f /root/logs/${SERVICE}.log"
        ;;
    ""|menu)
        while true; do
            clear
            echo "  ╔═══════════════════════════════════════════════════╗"
            echo "  ║         ANDROID VPS CONTROL PANEL v4.0           ║"
            echo "  ╚═══════════════════════════════════════════════════╝"
            echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
            echo "  1. Khởi động Server        6. Danh sách Websites"
            echo "  2. Dừng Server             7. Xóa Website"
            echo "  3. Xem Trạng thái          8. Backup Telegram"
            echo "  4. Monitor Real-time       9. Xem Log (Debug)"
            echo "  5. Tạo Website mới        10. Mở Tmux (Attach)"
            echo "                             0. Thoát"
            echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
            echo ""
            read -p "Chọn chức năng (0-10): " OPT
            case $OPT in
                1) vps start; sleep 2 ;;
                2) vps stop; sleep 2 ;;
                3) vps status; echo ""; read -p "Bấm Enter để về Menu..." ;;
                4) vps monitor ;;
                5) vps create; echo ""; read -p "Bấm Enter để về Menu..." ;;
                6) vps list; echo ""; read -p "Bấm Enter để về Menu..." ;;
                7) vps delete; echo ""; read -p "Bấm Enter để về Menu..." ;;
                8) vps backup; sleep 2 ;;
                9) vps debug; echo ""; read -p "Bấm Enter để về Menu..." ;;
                10) vps attach ;;
                0) exit 0 ;;
                *) echo "Lựa chọn không hợp lệ."; sleep 1 ;;
            esac
        done
        ;;
    *)
        echo "Lệnh không hợp lệ. Gõ 'vps' để mở Menu."
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

    echo -e "${YELLOW}Cài đặt Android VPS Stack v4.0${NC}"
    echo ""
    echo "  • Nginx + PHP-FPM 8.4 (nhẹ hơn Apache)"
    echo "  • MariaDB (auth mới: vps_admin user)"
    echo "  • Redis + WP-CLI + Node.js 20"
    echo "  • PostgreSQL (pg_ctl trực tiếp, không cần systemd)"
    echo "  • ChromaDB + Cloudflare Tunnel"
    echo "  • Auto Recovery + Health Check + Backup Telegram"
    echo "  • Fix: MariaDB auth, PostgreSQL proot, menu không văng"
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

    section "✅ CÀI ĐẶT HOÀN TẤT v4.0"
    echo ""
    echo -e "${GREEN}Lệnh quan trọng:${NC}"
    echo ""
    echo -e "  ${CYAN}vps start${NC}                Khởi động server"
    echo -e "  ${CYAN}vps status${NC}               Trạng thái services"
    echo -e "  ${CYAN}vps monitor${NC}              Real-time monitor"
    echo -e "  ${CYAN}vps create${NC}               Tạo WordPress / NextJS / Static"
    echo -e "  ${CYAN}vps db shell${NC}             Vào MariaDB"
    echo -e "  ${CYAN}vps pg shell${NC}             Vào PostgreSQL"
    echo -e "  ${CYAN}vps wp example.com help${NC}  WP-CLI"
    echo -e "  ${CYAN}vps debug${NC}                Xem log lỗi"
    echo -e "  ${CYAN}vps backup${NC}               Backup Telegram"
    echo ""
    echo -e "${YELLOW}Thay đổi chính so với v3.0:${NC}"
    echo "  ✓ MariaDB: dùng vps_admin user thay vì root (fix ERROR 1698)"
    echo "  ✓ PostgreSQL: pg_ctl trực tiếp, không cần systemd"
    echo "  ✓ create-site: dùng return thay exit → không văng menu"
    echo "  ✓ WP plugins: retry logic, bắt lỗi đúng cách"
    echo "  ✓ Thêm: vps pg (PostgreSQL helper)"
    echo ""

    # Thông tin SSH
    PHONE_IP=$(ip route get 1 2>/dev/null | awk '{print $7; exit}' || \
               ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -1)
    SSH_USER=$(whoami)

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  THÔNG TIN KẾT NỐI SSH (Bitvise SSH Client)    ${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  Host     : ${GREEN}${PHONE_IP:-<IP điện thoại>}${NC}"
    echo -e "  Port     : ${GREEN}8022${NC}"
    echo -e "  Username : ${GREEN}${SSH_USER}${NC}"
    echo -e "  Password : ${GREEN}<password bạn vừa đặt lúc cài>${NC}"
    echo ""
    echo -e "  ${YELLOW}Máy tính và điện thoại phải cùng WiFi${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    read -p "Khởi động server ngay? (y/n): " START_NOW
    if [[ "$START_NOW" == "y" ]]; then
        vps restart
    fi

    echo ""
    log "Done! Gõ 'vps create' để tạo site đầu tiên."
    echo ""
    read -n 1 -s -r -p "Bấm phím bất kỳ để vào Menu điều khiển VPS..."
    echo ""
    vps
}

main
