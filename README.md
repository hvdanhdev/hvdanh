# Android VPS Installer v4.0

## Stack đầy đủ và Cải tiến v4.0
| Service | Vai trò | Trạng thái v4.0 |
|---------|---------|-----------------|
| Nginx + PHP-FPM | Web server | Có menu Optimize (OpCache/FPM) |
| MariaDB | Database WP | **Fix ERROR 1698** (vps_admin user) |
| Redis | Object cache | Tự động cài plugin WP |
| Node.js 20 | NextJS projects | Sẵn sàng cho production |
| PostgreSQL | Database | **Chạy Native Termux** (Ổn định hơn) |
| ChromaDB | Vector DB | **Chạy Native Termux** (Build từ Rust) |
| Cloudflare Tunnel | Kết nối | Fix DNS routing thông minh |
| vps setup-wp | Tự động hóa | Cài WP Core + Plugin 1-click |

---

## Lưu ý Quan trọng trước khi cài đặt (DNS & Cloudflare)
Để hệ thống hoạt động trơn tru ngay lần đầu, bạn **CẦN** thực hiện các bước sau trên Dashboard Cloudflare:

1. **Trỏ NameServers**: Đảm bảo tên miền của bạn đã trỏ về DNS của Cloudflare.
2. **Xóa Record cũ**: Xóa **TẤT CẢ** các bản ghi `A`, `AAAA`, hoặc `CNAME` cũ của tên miền (và các subdomain) mà bạn định dùng. 
   - *Tại sao?* Nếu còn record cũ, Cloudflare Tunnel sẽ không thể tự động đè lên, dẫn đến lỗi kết nối (Error 1033).
3. **SSL/TLS**: Chỉnh chế độ thành **Full** hoặc **Full (Strict)** để tránh lỗi vòng lặp redirect.

---

## Cài đặt

### Máy mới - chạy 1 lệnh duy nhất
```bash
pkg update -y && pkg install -y wget && wget -O install.sh https://raw.githubusercontent.com/hvdanhdev/hvdanh/main/install.sh && bash install.sh
```

**Các bước sau khi cài:**
1. Chạy lệnh: `vps`
2. Tạo website: Chọn **Số 5**.
3. Cài WordPress hoàn chỉnh: Chạy `vps setup-wp <domain>`.
4. (Tùy chọn) Cài PostgreSQL/ChromaDB: Chọn **Số 12**.

---

## Lệnh vps (Control Panel)

### Quản lý Hệ thống
```bash
vps start          # Khởi động TẤT CẢ (Debian + Native PG/Chroma)
vps stop           # Dừng TẤT CẢ an toàn
vps status         # Trạng thái Real-time (Xanh = Chạy, Đỏ = Dừng)
vps monitor        # Dashboard giám sát RAM/CPU/Disk
vps optimize       # Menu tối ưu OpCache và PHP-FPM (Số 11)
vps native         # Menu quản lý PostgreSQL & ChromaDB (Số 12)
```

### Quản lý Website & WordPress
```bash
vps create         # Wizard tạo Website mới (WP, NextJS, Static)
vps setup-wp <dom> # Cài đặt WP Core, Admin, Plugin tự động
vps wp <dom> help  # Sử dụng WP-CLI cho website chỉ định
vps list           # Danh sách các website đang hoạt động
vps delete <dom>   # Xóa website và dọn dẹp Tunnel DNS
```

### Database & Backup
```bash
vps db <shell|list|create|export|import>  # Quản lý MariaDB
vps pg <shell|list|create|drop>           # Quản lý PostgreSQL
vps backup                                # Backup mọi thứ lên Telegram
```

---

## Hướng dẫn cài đặt thủ công (Dự phòng)
Nếu script cài đặt gặp lỗi ở các dịch vụ Native (thường do môi trường Termux thiếu thư viện), bạn có thể cài thủ công bằng các lệnh sau:

### 1. PostgreSQL (Native)
```bash
pkg install postgresql -y
initdb -D $PREFIX/var/lib/postgresql
pg_ctl -D $PREFIX/var/lib/postgresql start
```

### 2. ChromaDB (Native)
```bash
# Cài đặt môi trường build (C++, Rust)
pkg install python python-pip clang make libffi openssl rust binutils -y
# Cài đặt qua Pip (Mất 10-20 phút để biên dịch)
pip install chromadb
# Chạy server
chroma run --host 127.0.0.1 --port 8000
```

---

## Cấu trúc thư mục (Trong Debian)
Dữ liệu web và scripts quản lý nằm trong Debian (`proot-distro login debian`):
- `/var/www/` : Chứa mã nguồn các website.
- `/root/scripts/` : Các file thực thi quản lý dịch vụ.
- `/root/logs/` : Nơi kiểm tra khi có lỗi (vps debug).
- `/root/.vps_config` : Chứa cấu hình Tunnel và Telegram.

---
**Duy trì bởi hvdanhdev**
**Phiên bản: 4.0 (Ổn định nhất cho Android VPS)**
