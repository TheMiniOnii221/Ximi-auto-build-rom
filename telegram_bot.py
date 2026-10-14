#!/usr/bin/env python3
"""
Telegram Bot điều khiển GitHub Actions Build ROM Xiaomi
Sử dụng thư viện chuẩn của Python (không cần cài thêm pip package)
"""

import os
import sys
import json
import time
import urllib.request
import urllib.error

# ================= CẤU HÌNH =================
# Bạn có thể điền trực tiếp vào đây hoặc set qua biến môi trường
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "YOUR_BOT_TOKEN_HERE")
GITHUB_TOKEN = os.getenv("GITHUB_TOKEN", "YOUR_GITHUB_PAT_TOKEN_HERE")
GITHUB_REPO = os.getenv("GITHUB_REPO", "username/xiaomi-rom-builder")
ALLOWED_USER_ID = os.getenv("ALLOWED_USER_ID", "")  # Điền chat ID của bạn để chỉ mình bạn dùng được
# ============================================

def send_telegram_msg(chat_id, text):
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    payload = {
        "chat_id": chat_id,
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": True
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        print(f"[ERROR] Gửi tin nhắn Telegram lỗi: {e}")
        return None

def trigger_github_workflow(rom_url, device_name="vermeer", super_size="9663676416"):
    url = f"https://api.github.com/repos/{GITHUB_REPO}/dispatches"
    payload = {
        "event_type": "build_rom",
        "client_payload": {
            "rom_url": rom_url,
            "device_name": device_name,
            "super_size": super_size
        }
    }
    data = json.dumps(payload).encode("utf-8")
    headers = {
        "Authorization": f"Bearer {GITHUB_TOKEN}",
        "Accept": "application/vnd.github.v3+json",
        "Content-Type": "application/json",
        "User-Agent": "Xiaomi-ROM-Builder-Bot"
    }
    req = urllib.request.Request(url, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status == 204
    except urllib.error.HTTPError as e:
        print(f"[ERROR] GitHub API lỗi ({e.code}): {e.read().decode()}")
        return False
    except Exception as e:
        print(f"[ERROR] Không thể kết nối GitHub: {e}")
        return False

def get_recent_runs():
    url = f"https://api.github.com/repos/{GITHUB_REPO}/actions/runs?per_page=3"
    headers = {
        "Authorization": f"Bearer {GITHUB_TOKEN}",
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "Xiaomi-ROM-Builder-Bot"
    }
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode())
            runs = data.get("workflow_runs", [])
            lines = []
            for r in runs:
                status = r.get("status")
                conclusion = r.get("conclusion") or "đang chạy..."
                icon = "⏳" if status != "completed" else ("✅" if conclusion == "success" else "❌")
                lines.append(f"{icon} <b>{r.get('name')}</b>: {status} ({conclusion})\n🔗 <a href=\"{r.get('html_url')}\">Xem chi tiết</a>")
            return "\n\n".join(lines) if lines else "Chưa có lượt chạy nào."
    except Exception as e:
        return f"Lỗi lấy thông tin: {e}"

def handle_command(chat_id, user_id, text):
    if ALLOWED_USER_ID and str(user_id) != str(ALLOWED_USER_ID):
        send_telegram_msg(chat_id, "⛔ <b>Từ chối truy cập:</b> Bạn không có quyền sử dụng bot này.")
        return

    parts = text.strip().split()
    cmd = parts[0].lower() if parts else ""

    if cmd in ["/start", "/help"]:
        msg = (
            "🤖 <b>Chào mừng bạn đến với Xiaomi ROM Builder Bot!</b>\n\n"
            "📌 <b>Các lệnh hỗ trợ:</b>\n"
            "• <code>/build &lt;link_rom&gt; [tên_máy] [super_size]</code>\n"
            "  <i>Ví dụ:</i>\n"
            "  <code>/build https://example.com/rom.zip vermeer</code>\n\n"
            "• <code>/status</code>: Kiểm tra trạng thái các lần build gần nhất\n"
            "• <code>/myid</code>: Lấy Chat ID của bạn\n"
        )
        send_telegram_msg(chat_id, msg)

    elif cmd == "/myid":
        send_telegram_msg(chat_id, f"🆔 Chat ID của bạn là: <code>{user_id}</code>")

    elif cmd == "/status":
        send_telegram_msg(chat_id, "🔍 Đang kiểm tra tiến trình GitHub Actions...")
        runs_msg = get_recent_runs()
        send_telegram_msg(chat_id, f"📋 <b>Trạng thái gần đây:</b>\n\n{runs_msg}")

    elif cmd == "/build":
        if len(parts) < 2:
            send_telegram_msg(chat_id, "⚠️ <b>Thiếu tham số!</b>\nCú pháp: <code>/build &lt;link_rom&gt; [tên_máy] [super_size]</code>")
            return
        
        rom_url = parts[1]
        device = parts[2] if len(parts) > 2 else "vermeer"
        super_size = parts[3] if len(parts) > 3 else "9663676416"

        send_telegram_msg(chat_id, f"⏳ Đang gửi yêu cầu build cho <b>{device}</b> lên GitHub...")
        success = trigger_github_workflow(rom_url, device, super_size)

        if success:
            send_telegram_msg(chat_id, (
                f"🚀 <b>Đã kích hoạt GitHub Actions thành công!</b>\n\n"
                f"📱 <b>Thiết bị:</b> <code>{device}</code>\n"
                f"🔗 <b>ROM URL:</b> {rom_url}\n"
                f"💾 <b>Super Size:</b> <code>{super_size}</code>\n\n"
                f"Bot sẽ tự động báo cáo khi quá trình build hoàn tất!"
            ))
        else:
            send_telegram_msg(chat_id, "❌ <b>Kích hoạt thất bại!</b> Hãy kiểm tra lại GITHUB_TOKEN và tên GITHUB_REPO.")

def main():
    print("=== XIAOMI ROM BUILDER TELEGRAM BOT ===")
    if TELEGRAM_BOT_TOKEN == "YOUR_BOT_TOKEN_HERE":
        print("[LƯU Ý] Bạn chưa điền TELEGRAM_BOT_TOKEN!")
        print("Mở file telegram_bot.py hoặc chạy với:")
        print("export TELEGRAM_BOT_TOKEN='...'")
        print("export GITHUB_TOKEN='...'")
        print("export GITHUB_REPO='username/repo'")
        print("export ALLOWED_USER_ID='your_chat_id'")
        sys.exit(1)

    print("Bot đang chạy và lắng nghe lệnh...")
    last_update_id = 0
    while True:
        try:
            url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/getUpdates?offset={last_update_id + 1}&timeout=30"
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req) as resp:
                result = json.loads(resp.read().decode())
                for item in result.get("result", []):
                    last_update_id = item["update_id"]
                    message = item.get("message", {})
                    chat = message.get("chat", {})
                    chat_id = chat.get("id")
                    user_id = message.get("from", {}).get("id")
                    text = message.get("text", "")
                    if text and chat_id:
                        handle_command(chat_id, user_id, text)
        except Exception as e:
            time.sleep(3)

if __name__ == "__main__":
    main()
