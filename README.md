# Android VPS Installer v3.0

## Stack đầy đủ
| Service | Vai trò |
|---------|---------|
| Nginx + PHP-FPM | Web server (nhẹ hơn Apache 2-3x) |
| MariaDB | Database WordPress |
| Redis | Object cache (tăng tốc WordPress) |
| WP-CLI | Quản lý WordPress qua terminal |
| Node.js 20 | NextJS projects |
| PostgreSQL | Database cho NextJS/CRM |
| ChromaDB | Vector database AI |
| Cloudflare Tunnel | SSL miễn phí, IP động |
| tmux | Server không bị kill khi đóng SSH |
| Auto Recovery | Tự restart service khi chết |
| Health Check | Heartbeat Telegram 5 phút/lần |
| Backup Telegram | Auto backup lên Telegram |
| Monitor | Real-time RAM/CPU/Nginx |
| Rate Limiting | Chống brute force wp-login |
| Block xmlrpc | Bảo mật WordPress |

---

## Cài đặt

### Máy mới - chạy 1 lệnh
```bash
bash install.sh
```
Hoặc trong termux dùng lệnh sau
```bash
pkg update -y && pkg install -y wget && wget -O install.sh https://raw.githubusercontent.com/hvdanhdev/hvdanh/main/install.sh && bash install.sh
```

Script hỏi lần lượt:
1. Xác nhận bắt đầu
2. Mở link đăng nhập Cloudflare trên trình duyệt
3. Nhập tên tunnel (Enter = my-server)
4. Nhập Telegram Bot Token + Chat ID (Enter để bỏ qua)

---

## Lệnh vps

### Server
```bash
vps start          # Khởi động tất cả services
vps stop           # Dừng tất cả
vps restart        # Restart
vps status         # Xem trạng thái + danh sách sites
vps monitor        # Real-time RAM/CPU/Nginx/processes
vps attach         # Mở tmux xem log live
vps ubuntu         # Vào Ubuntu shell
vps logs <service> # Xem log (cloudflared/nginx/redis/chromadb...)
```

### Website
```bash
vps create                    # Tạo site mới (wizard)
vps list                      # Danh sách sites đang chạy
vps delete thoigianranh.com   # Xóa site
```

### WordPress - WP-CLI
```bash
vps wp thoigianranh.com plugin list
vps wp thoigianranh.com plugin update --all
vps wp thoigianranh.com theme list
vps wp thoigianranh.com core update
vps wp thoigianranh.com user list
vps wp thoigianranh.com cache flush
vps wp thoigianranh.com db export backup.sql
vps wp thoigianranh.com db import backup.sql
```

### Database
```bash
vps db shell                      # Vào MariaDB shell
vps db list                       # Danh sách databases
vps db create                     # Tạo database mới (wizard)
vps db export mydb                # Export → ~/backup/mydb_date.sql.gz
vps db export mydb /path/out.sql  # Export ra file chỉ định
vps db import mydb backup.sql     # Import (hỗ trợ .sql và .sql.gz)
vps db drop mydb                  # Xóa database
```

### Backup
```bash
vps backup    # Backup tất cả sites lên Telegram
```

---

## Tạo site mới (vps create)

Hỗ trợ 3 loại:

### 1. WordPress
- Tạo database MariaDB tự động
- Tải và cài WordPress
- Cấu hình wp-config.php (Redis, HTTPS fix, Security)
- Nginx vhost với bảo mật đầy đủ:
  - Rate limit wp-login: 5 lần/phút
  - Block xmlrpc.php hoàn toàn
  - Block .env, .git, wp-config.php
  - Cache static 30 ngày
- Thêm domain vào Cloudflare Tunnel
- Cài Redis Object Cache plugin tự động

### 2. NextJS (reverse proxy)
- Nginx reverse proxy về port chỉ định
- Header forwarding đầy đủ

### 3. Static HTML
- Thư mục web + file index mẫu
- Nginx serve static files

### Subdomain tự động
- `thoigianranh.com` → thêm cả `www.thoigianranh.com`
- `api.thoigianranh.com` → chỉ thêm subdomain đó
- `crm.thoigianranh.com` → tương tự

---

## Telegram

### Cách lấy Token + Chat ID
1. Nhắn @BotFather → `/newbot` → đặt tên → lấy **Token**
2. Nhắn @userinfobot → lấy **Chat ID**

### Các tin nhắn nhận được
| Tin nhắn | Thời điểm |
|----------|-----------|
| 🚀 VPS Online | Khi server khởi động |
| 💓 Heartbeat | Mỗi 5 phút (RAM/Disk/Sites) |
| 🔄 Service restart | Khi service chết và tự restart |
| ❌ Restart failed | Khi restart thất bại |
| 🚨 RAM Critical | Khi RAM > 7GB |
| 🔄 Backup bắt đầu | Khi chạy backup |
| 📁 Files backup | File tar.gz từng site |
| 🗄️ DB backup | File sql.gz từng site |
| ✅ Backup xong | Khi backup hoàn tất |

### Cấu hình lại sau khi cài
Sửa file trong Ubuntu:
```bash
vps ubuntu
nano ~/.vps_config
```
```
TUNNEL_NAME=my-server
TUNNEL_ID=xxx-xxx-xxx
TG_ENABLED=true
TG_TOKEN=123456:ABC...
TG_CHAT_ID=123456789
```

---

## Monitor real-time (vps monitor)

Hiển thị cập nhật mỗi 3 giây:
- RAM usage (màu xanh/vàng/đỏ theo mức)
- CPU Load
- Disk usage
- Nginx: số processes, requests/phút
- 5 requests gần nhất
- Top processes ngốn RAM
- Trạng thái từng service

---

## Auto Recovery

Cứ 45 giây kiểm tra và tự restart:
- Nginx, PHP-FPM, MariaDB, Redis
- PostgreSQL, ChromaDB, Cloudflare Tunnel

Xử lý RAM:
- > 6GB: flush Redis cache
- > 7GB: flush cache + drop page cache

---

## Bảo mật

### Nginx
- Rate limit wp-login: 5 req/phút (burst 3)
- Block xmlrpc.php → 444 (không response)
- Block .htaccess, .env, .git, wp-config.php
- server_tokens off (ẩn phiên bản Nginx)

### WordPress (wp-config.php)
- `DISALLOW_FILE_EDIT true` - tắt editor trong admin
- `WP_AUTO_UPDATE_CORE minor` - tự update minor
- HTTPS fix cho Cloudflare Tunnel
- Redis Object Cache

### Internal services
- MariaDB: chỉ localhost
- Redis: bind 127.0.0.1
- PostgreSQL: chỉ localhost
- ChromaDB: bind 127.0.0.1

---

## Cấu trúc thư mục (trong Ubuntu)

```
~/
├── scripts/
│   ├── start.sh          # Khởi động tất cả
│   ├── stop.sh           # Dừng tất cả
│   ├── status.sh         # Trạng thái
│   ├── monitor.sh        # Real-time monitor
│   ├── create-site.sh    # Tạo site mới
│   ├── wp.sh             # WP-CLI helper
│   ├── db.sh             # Database helper
│   ├── backup.sh         # Backup Telegram
│   ├── auto_recover.sh   # Daemon giám sát
│   └── health_check.sh   # Heartbeat Telegram
├── logs/
│   ├── cloudflared.log
│   ├── auto_recover.log
│   ├── health_check.log
│   ├── backup.log
│   ├── chromadb.log
│   └── redis.log
├── backup/               # File backup local
├── projects/             # NextJS projects
└── .vps_config           # Config chính
```
