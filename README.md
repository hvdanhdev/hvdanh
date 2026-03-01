# Android VPS Installer v4.0

## Stack Ä‘áº§y Ä‘á»§ vÃ  Cáº£i tiáº¿n v4.0
| Service | Vai trÃ² | Tráº¡ng thÃ¡i v4.0 |
|---------|---------|-----------------|
| Nginx + PHP-FPM | Web server | CÃ³ menu Optimize (OpCache/FPM) |
| MariaDB | Database WP | **Fix ERROR 1698** (vps_admin user) |
| Redis | Object cache | Tá»± Ä‘á»™ng cÃ i plugin WP |
| Node.js 20 | NextJS projects | Sáºµn sÃ ng cho production |
| PostgreSQL | Database | **Cháº¡y Native Termux** (á»”n Ä‘á»‹nh hÆ¡n) |
| Cloudflare Tunnel | Káº¿t ná»‘i | Fix DNS routing thÃ´ng minh |
| vps setup-wp | Tá»± Ä‘á»™ng hÃ³a | CÃ i WP Core + Plugin 1-click |

---

## LÆ°u Ã½ Quan trá»ng trÆ°á»›c khi cÃ i Ä‘áº·t (DNS & Cloudflare)
Äá»ƒ há»‡ thá»‘ng hoáº¡t Ä‘á»™ng trÆ¡n tru ngay láº§n Ä‘áº§u, báº¡n **Cáº¦N** thá»±c hiá»‡n cÃ¡c bÆ°á»›c sau trÃªn Dashboard Cloudflare:

1. **Trá» NameServers**: Äáº£m báº£o tÃªn miá»n cá»§a báº¡n Ä‘Ã£ trá» vá» DNS cá»§a Cloudflare.
2. **XÃ³a Record cÅ©**: XÃ³a **Táº¤T Cáº¢** cÃ¡c báº£n ghi `A`, `AAAA`, hoáº·c `CNAME` cÅ© cá»§a tÃªn miá»n (vÃ  cÃ¡c subdomain) mÃ  báº¡n Ä‘á»‹nh dÃ¹ng. 
   - *Táº¡i sao?* Náº¿u cÃ²n record cÅ©, Cloudflare Tunnel sáº½ khÃ´ng thá»ƒ tá»± Ä‘á»™ng Ä‘Ã¨ lÃªn, dáº«n Ä‘áº¿n lá»—i káº¿t ná»‘i (Error 1033).
3. **SSL/TLS**: Chá»‰nh cháº¿ Ä‘á»™ thÃ nh **Full** hoáº·c **Full (Strict)** Ä‘á»ƒ trÃ¡nh lá»—i vÃ²ng láº·p redirect.

---

## CÃ i Ä‘áº·t

### MÃ¡y má»›i - cháº¡y 1 lá»‡nh duy nháº¥t
```bash
pkg update -y && pkg install -y wget && wget -O install.sh https://raw.githubusercontent.com/hvdanhdev/hvdanh/main/install.sh && bash install.sh
```

**CÃ¡c bÆ°á»›c sau khi cÃ i:**
1. Cháº¡y lá»‡nh: `vps`
2. Táº¡o website: Chá»n **Sá»‘ 5**.
3. CÃ i WordPress hoÃ n chá»‰nh: Cháº¡y `vps setup-wp <domain>`.
4. (TÃ¹y chá»n) CÃ i PostgreSQL/ChromaDB: Chá»n **Sá»‘ 12**.

---

## Lá»‡nh vps (Control Panel)

### Quáº£n lÃ½ Há»‡ thá»‘ng
```bash
vps start          # Khá»Ÿi Ä‘á»™ng Táº¤T Cáº¢ (Debian + Native PG/Chroma)
vps stop           # Dá»«ng Táº¤T Cáº¢ an toÃ n
vps status         # Tráº¡ng thÃ¡i Real-time (Xanh = Cháº¡y, Äá» = Dá»«ng)
vps monitor        # Dashboard giÃ¡m sÃ¡t RAM/CPU/Disk
vps optimize       # Menu tá»‘i Æ°u OpCache vÃ  PHP-FPM (Sá»‘ 11)
vps native         # Menu quáº£n lÃ½ PostgreSQL (Sá»‘ 12)
```

### Quáº£n lÃ½ Website & WordPress
```bash
vps create         # Wizard táº¡o Website má»›i (WP, NextJS, Static)
vps setup-wp <dom> # CÃ i Ä‘áº·t WP Core, Admin, Plugin tá»± Ä‘á»™ng
vps wp <dom> help  # Sá»­ dá»¥ng WP-CLI cho website chá»‰ Ä‘á»‹nh
vps list           # Danh sÃ¡ch cÃ¡c website Ä‘ang hoáº¡t Ä‘á»™ng
vps delete <dom>   # XÃ³a website vÃ  dá»n dáº¹p Tunnel DNS
```

### Database & Backup
```bash
vps db <shell|list|create|export|import>  # Quáº£n lÃ½ MariaDB
vps pg <shell|list|create|drop>           # Quáº£n lÃ½ PostgreSQL
vps backup                                # Backup má»i thá»© lÃªn Telegram
```

---

## HÆ°á»›ng dáº«n cÃ i Ä‘áº·t thá»§ cÃ´ng (Dá»± phÃ²ng)
Náº¿u script cÃ i Ä‘áº·t gáº·p lá»—i á»Ÿ cÃ¡c dá»‹ch vá»¥ Native (thÆ°á»ng do mÃ´i trÆ°á»ng Termux thiáº¿u thÆ° viá»‡n), báº¡n cÃ³ thá»ƒ cÃ i thá»§ cÃ´ng báº±ng cÃ¡c lá»‡nh sau:

### 1. PostgreSQL (Native)
```bash
pkg install postgresql -y
initdb -D $PREFIX/var/lib/postgresql
pg_ctl -D $PREFIX/var/lib/postgresql start
```

---

## Cáº¥u trÃºc thÆ° má»¥c (Trong Debian)
Dá»¯ liá»‡u web vÃ  scripts quáº£n lÃ½ náº±m trong Debian (`proot-distro login debian`):
- `/var/www/` : Chá»©a mÃ£ nguá»“n cÃ¡c website.
- `/root/scripts/` : CÃ¡c file thá»±c thi quáº£n lÃ½ dá»‹ch vá»¥.
- `/root/logs/` : NÆ¡i kiá»ƒm tra khi cÃ³ lá»—i (vps debug).
- `/root/.vps_config` : Chá»©a cáº¥u hÃ¬nh Tunnel vÃ  Telegram.

---

## Luá»“ng hoáº¡t Ä‘á»™ng cá»§a Website (Workflow)

### 1. Website WordPress
Khi ngÆ°á»i dÃ¹ng truy cáº­p `https://example.com`:
1. **TrÃ¬nh duyá»‡t** gá»­i yÃªu cáº§u tá»›i **Cloudflare** (SSL/TLS).
2. **Cloudflare** chuyá»ƒn hÆ°á»›ng yÃªu cáº§u vÃ o **Cloudflare Tunnel** (MÃ£ hÃ³a).
3. **Cloudflared (Termux)** nháº­n yÃªu cáº§u vÃ  Ä‘áº©y vÃ o **Nginx (Debian Proot)**.
4. **Nginx** xá»­ lÃ½:
   - Náº¿u lÃ  file tÄ©nh (áº£nh, css, js): Tráº£ vá» ngay (Cache 30 ngÃ y).
   - Náº¿u lÃ  mÃ£ PHP: Äáº©y sang **PHP-FPM 8.4**.
5. **PHP-FPM** truy váº¥n dá»¯ liá»‡u tá»« **MariaDB** vÃ  **Redis Cache**.
6. Káº¿t quáº£ Ä‘Æ°á»£c tráº£ ngÆ°á»£c láº¡i cho ngÆ°á»i dÃ¹ng.

### 2. Website NextJS (Dá»± Ã¡n AI)
Khi ngÆ°á»i dÃ¹ng truy cáº­p `https://api.example.com`:
1. **Cloudflare & Tunnel** xá»­ lÃ½ tÆ°Æ¡ng tá»± nhÆ° WordPress.
2. **Nginx (Debian Proot)** Ä‘Ã³ng vai trÃ² **Reverse Proxy**, Ä‘áº©y yÃªu cáº§u tá»›i port cá»§a á»©ng dá»¥ng (vÃ­ dá»¥: `localhost:3000`).
3. **Node.js (NextJS App)** nháº­n yÃªu cáº§u vÃ  xá»­ lÃ½ logic.
4. **NextJS** cÃ³ thá»ƒ káº¿t ná»‘i vá»›i **PostgreSQL (Native Termux)**: LÆ°u trá»¯ dá»¯ liá»‡u quan há»‡, CRM.
5. á»¨ng dá»¥ng tráº£ vá» káº¿t quáº£ cho trÃ¬nh duyá»‡t.

---
**Duy trÃ¬ bá»Ÿi hvdanhdev**
**PhiÃªn báº£n: 4.0 (á»”n Ä‘á»‹nh nháº¥t cho Android VPS)**
