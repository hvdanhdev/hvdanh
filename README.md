# Android VPS Installer v4.0 (Stable)

Stack tối ưu chạy trên Termux (Android): **Nginx + PHP 8.4 + MariaDB + Redis + WP-CLI + Cloudflare Tunnel**.

## 🚀 Cài đặt nhanh
Mở Termux và dán lệnh sau:
```bash
pkg update -y && pkg install -y wget && wget -O install.sh https://raw.githubusercontent.com/hvdanhdev/hvdanh/main/install.sh && bash install.sh
```

## 🛠 Lệnh điều khiển VPS (vps command)
Sau khi cài đặt, bạn có thể sử dụng lệnh `vps` từ bất cứ đâu:

- `vps` hoặc `vps menu`: Mở menu điều khiển giao diện trực quan.
- `vps start`: Khởi động toàn bộ dịch vụ (Nginx, PHP, MySQL, Redis, Cloudflare).
- `vps stop`: Dừng tất cả dịch vụ.
- `vps status`: Xem trạng thái sống/chết của các dịch vụ.
- `vps monitor`: Xem tài liệu hệ thống (CPU, RAM, Connections) thời gian thực.
- `vps create`: Tạo Website mới (WordPress, NextJS, Static).
- `vps delete`: Xóa Website hiện có.
- `vps list`: Danh sách các Website đang chạy.
- `vps backup`: Sao lưu toàn bộ dữ liệu lên Telegram (nếu đã cấu hình).
- `vps debug`: Xem log lỗi của Nginx, MariaDB, Cloudflare để xử lý sự cố.

## 📝 Hướng dẫn sử dụng WP-CLI (Dành cho WordPress)
WP-CLI được tích hợp sẵn để quản lý WordPress cực nhanh mà không cần vào giao diện Web.

**Cú pháp chung:** `vps wp <domain> <lệnh_wp>`

### 1. Cài đặt Plugin/Theme (Khắc phục lỗi upload 413/Timeout)
Nếu bạn không upload được plugin qua Web, hãy dùng lệnh này:
- **Cài từ link .zip:**
  ```bash
  vps wp example.com plugin install https://wordpress.org/plugins/classic-editor.zip --activate
  ```
- **Cài từ file đã upload lên máy (SFTP):**
  Upload file vào thư mục Home của Termux, sau đó chạy:
  ```bash
  vps wp example.com plugin install ~/my-plugin.zip --activate
  ```
- **Cài trực tiếp từ kho WordPress.org:**
  ```bash
  vps wp example.com plugin install query-monitor --activate
  ```

### 2. Quản lý Database
- **Export Database:** `vps wp example.com db export`
- **Tối ưu Database:** `vps wp example.com db optimize`

### 3. Dọn dẹp Cache
- `vps wp example.com cache flush`

## 🖥 Truy cập từ Máy tính (SSH)
1. **Mở Bitvise SSH Client**.
2. **Host**: IP của điện thoại (xem bằng lệnh `ifconfig` trong Termux).
3. **Port**: `8022`.
4. **Username**: (Để trống).
5. **Password**: Password bạn đã đặt lúc cài đặt bước 1.
6. **SFTP**: Sử dụng cửa sổ SFTP để kéo thả dữ liệu website vào `/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/debian/var/www/`.

---
*Phát triển bởi hvdanhdev.*
