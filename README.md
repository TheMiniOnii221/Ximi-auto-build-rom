# 🚀 Xiaomi Fastboot ROM Builder (Payload to Super + Telegram Bot)

Tool tự động chuyển đổi ROM Xiaomi Recovery (`.zip` có chứa `payload.bin` hoặc link `payload.bin` trực tiếp) thành bộ **Fastboot ROM đầy đủ** có `super.img` (sparse) và các phân vùng firmware khác, kèm script nạp tự động `flash_all.bat` và `flash_all.sh`.

Hỗ trợ **kích hoạt build và nhận thông báo kết quả tự động qua Telegram**!

---

## 📁 Cấu trúc thư mục

```text
xiaomi-rom-builder/
├── .github/
│   └── workflows/
│       └── build_rom.yml       # GitHub Actions workflow (hỗ trợ Telegram dispatch & notify)
├── build_rom.sh                # Script core tải, extract, repack super.img
├── telegram_bot.py             # Bot Telegram nhận lệnh /build và gửi GitHub Actions
└── README.md
```

---

## 🤖 Thiết lập thông báo & Điều khiển qua Telegram

### Bước 1: Tạo Bot Telegram & Lấy Chat ID
1. Mở Telegram, tìm **[@BotFather](https://t.me/BotFather)** $\rightarrow$ gửi lệnh `/newbot` $\rightarrow$ làm theo hướng dẫn để lấy **Bot Token** (dạng `123456789:ABCdef...`).
2. Tìm bot **[@userinfobot](https://t.me/userinfobot)** hoặc gửi tin nhắn cho bot của bạn rồi mở:
   `https://api.telegram.org/bot<TOKEN>/getUpdates` để lấy **Chat ID** của bạn (dạng số, ví dụ: `987654321`).

### Bước 2: Thêm Secret vào GitHub Repository
Vào repo trên GitHub: **Settings** $\rightarrow$ **Secrets and variables** $\rightarrow$ **Actions** $\rightarrow$ **New repository secret**:
- `TELEGRAM_BOT_TOKEN`: Token của bot bạn vừa tạo.
- `TELEGRAM_CHAT_ID`: Chat ID của bạn.

> [!NOTE]
> Sau khi thêm 2 Secret này, mỗi khi GitHub Actions bắt đầu build, build xong (hoặc lỗi), bot sẽ tự động gửi tin nhắn báo về Telegram cho bạn kèm link tải Release!

---

## 📲 Cách ra lệnh Build qua Telegram

Bạn có thể chạy script `telegram_bot.py` ngay trên điện thoại (qua Termux/AGY) hoặc trên bất kỳ VPS/máy tính nào:

```bash
cd /storage/emulated/0/Download/xiaomi-rom-builder

export TELEGRAM_BOT_TOKEN="token_bot_cua_ban"
export GITHUB_TOKEN="github_pat_token_cua_ban"       # Tạo tại: github.com/settings/tokens (quyền repo + workflow)
export GITHUB_REPO="username/xiaomi-rom-builder"
export ALLOWED_USER_ID="chat_id_cua_ban"

python3 telegram_bot.py
```

### Các lệnh trong Telegram:
- `/build <link_rom> [tên_thiết_bị] [super_size]`
  - *Ví dụ:*
    ```text
    /build https://bigota.d.miui.com/.../miui_VERMEER_...zip vermeer
    ```
- `/status`: Xem trạng thái các lần build gần nhất trên GitHub Actions.
- `/myid`: Lấy Chat ID của bạn.

---

## ⚡ Cách chạy thủ công trên GitHub Actions Web

1. Vào tab **Actions** trên GitHub.
2. Chọn **"Xiaomi ROM Builder (Payload to Super)"**.
3. Bấm **Run workflow**:
   - Điền link ROM vào ô **rom_url**.
   - Bấm **Run workflow**.
4. Chờ bot gửi link tải về Telegram khi hoàn thành!
