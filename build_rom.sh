#!/usr/bin/env bash
# ==============================================================================
# Xiaomi ROM Builder: payload.bin / Recovery ZIP -> Fastboot ROM with super.img
# Supports: Android (Termux/AGY) and Linux (Ubuntu / GitHub Actions)
# ==============================================================================

set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { 
    echo -e "${RED}[ERROR]${NC} $1";
    tg_notify "❌ <b>Lỗi trong quá trình build:</b>%0A<code>$1</code>"
    exit 1; 
}

# Hàm gửi thông báo Telegram
tg_notify() {
    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        local msg="$1"
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}&parse_mode=HTML&text=${msg}" >/dev/null 2>&1 || true
    fi
}

# Default arguments
ROM_URL="${1:-}"
DEVICE_NAME="${2:-xiaomi_device}"
CUSTOM_SUPER_SIZE="${3:-0}"

WORK_DIR="${WORK_DIR:-$(pwd)/rom_build_workspace}"
OUT_DIR="${OUT_DIR:-$(pwd)/fastboot_rom_output}"

if [ -z "$ROM_URL" ]; then
    echo "Sử dụng: $0 <LINK_ROM_ZIP_HOAC_PAYLOAD> [TEN_THIET_BI] [SUPER_SIZE_BYTES]"
    echo "Ví dụ:   $0 'https://example.com/miui_VERMEER_....zip' vermeer 9663676416"
    exit 1
fi

log_info "Bắt đầu tiến trình build ROM..."
log_info "URL: $ROM_URL"
log_info "Thiết bị: $DEVICE_NAME"
log_info "Workspace: $WORK_DIR"
log_info "Output: $OUT_DIR"

mkdir -p "$WORK_DIR" "$OUT_DIR/images"

# 1. Tải ROM
ROM_FILENAME=$(basename "${ROM_URL%%\?*}")
if [ -z "$ROM_FILENAME" ] || [[ "$ROM_FILENAME" != *.zip && "$ROM_FILENAME" != *.bin ]]; then
    ROM_FILENAME="rom_download.zip"
fi

DOWNLOAD_TARGET="$WORK_DIR/$ROM_FILENAME"

if [ ! -f "$DOWNLOAD_TARGET" ]; then
    log_info "Đang tải ROM: $ROM_URL ..."
    tg_notify "📥 <b>[Bước 1/5] Đang tải ROM từ máy chủ...</b>%0A📱 <b>Thiết bị:</b> <code>$DEVICE_NAME</code>%0A📁 <b>Tệp:</b> <code>$ROM_FILENAME</code>"
    
    if command -v aria2c >/dev/null 2>&1; then
        aria2c -x16 -s16 -j4 -c --summary-interval=10 -d "$WORK_DIR" -o "$ROM_FILENAME" "$ROM_URL" || \
        curl -L -C - -o "$DOWNLOAD_TARGET" "$ROM_URL"
    else
        curl -L -C - -o "$DOWNLOAD_TARGET" "$ROM_URL"
    fi
else
    log_info "File ROM đã tồn tại: $DOWNLOAD_TARGET. Bỏ qua bước tải."
fi

FILE_SIZE_HR=$(ls -lh "$DOWNLOAD_TARGET" | awk '{print $5}')
log_success "Đã có file ROM ($FILE_SIZE_HR)!"

# 2. Xác định và giải nén payload.bin
EXTRACTED_DIR="$WORK_DIR/extracted_images"
mkdir -p "$EXTRACTED_DIR"

PAYLOAD_FILE=""
if [[ "$DOWNLOAD_TARGET" == *.bin ]]; then
    PAYLOAD_FILE="$DOWNLOAD_TARGET"
else
    log_info "Đang tìm payload.bin từ file zip..."
    tg_notify "📦 <b>[Bước 2/5] Đã tải ROM ($FILE_SIZE_HR).</b>%0AĐang giải nén <code>payload.bin</code> từ file ZIP..."
    
    if command -v 7z >/dev/null 2>&1; then
        7z e -y -o"$WORK_DIR" "$DOWNLOAD_TARGET" "payload.bin" >/dev/null || true
    elif command -v unzip >/dev/null 2>&1; then
        unzip -q -o "$DOWNLOAD_TARGET" "payload.bin" -d "$WORK_DIR" || true
    fi

    if [ -f "$WORK_DIR/payload.bin" ]; then
        PAYLOAD_FILE="$WORK_DIR/payload.bin"
    else
        log_error "Không tìm thấy payload.bin trong file ZIP!"
    fi
fi

# 3. Trích xuất partition images từ payload.bin
log_info "Đang extract các partition images bằng payload-dumper-go..."
tg_notify "📂 <b>[Bước 3/5] Đang trích xuất các phân vùng (.img)</b> từ payload.bin..."

if ! command -v payload-dumper-go >/dev/null 2>&1; then
    log_error "Không tìm thấy công cụ 'payload-dumper-go' trong PATH!"
fi

payload-dumper-go -o "$EXTRACTED_DIR" "$PAYLOAD_FILE"
log_success "Đã trích xuất xong toàn bộ partition images!"

# 4. Phân loại Dynamic partitions và Firmware partitions
DYNAMIC_PARTS=("system" "system_ext" "product" "vendor" "odm" "mi_ext" "system_dlkm" "vendor_dlkm" "odm_dlkm")

log_info "Phân loại các partition..."
LPMAKE_ARGS=()
TOTAL_DYNAMIC_SIZE=0

for img_file in "$EXTRACTED_DIR"/*.img; do
    [ -f "$img_file" ] || continue
    bname=$(basename "$img_file" .img)
    
    is_dynamic=false
    for dyn in "${DYNAMIC_PARTS[@]}"; do
        if [ "$bname" == "$dyn" ]; then
            is_dynamic=true
            break
        fi
    done
    
    if [ "$is_dynamic" = true ]; then
        size=$(stat -c%s "$img_file" 2>/dev/null || stat -f%z "$img_file")
        TOTAL_DYNAMIC_SIZE=$((TOTAL_DYNAMIC_SIZE + size))
        log_info "Dynamic partition: $bname ($size bytes)"
        
        LPMAKE_ARGS+=(
            "--partition" "${bname}_a:readonly:${size}:qti_dynamic_partitions_a"
            "--image" "${bname}_a=${img_file}"
            "--partition" "${bname}_b:readonly:0:qti_dynamic_partitions_b"
        )
    else
        log_info "Firmware partition: $bname.img -> copy sang images/"
        cp -f "$img_file" "$OUT_DIR/images/"
    fi
done

# 5. Đóng gói super.img bằng lpmake
log_info "Tính toán dung lượng super partition..."

if [ "$CUSTOM_SUPER_SIZE" -gt 0 ]; then
    SUPER_SIZE="$CUSTOM_SUPER_SIZE"
    GROUP_SIZE="$CUSTOM_SUPER_SIZE"
    log_info "Sử dụng super size chỉ định: $SUPER_SIZE bytes"
else
    # Tự động tính: tổng size dynamic + 100MB dự phòng (align 4KB)
    GROUP_SIZE=$(( ((TOTAL_DYNAMIC_SIZE + 104857600 + 4095) / 4096) * 4096 ))
    SUPER_SIZE=$(( GROUP_SIZE + 20971520 ))
    log_info "Tự động tính super size: $SUPER_SIZE bytes"
fi

if [ "$TOTAL_DYNAMIC_SIZE" -gt "$GROUP_SIZE" ]; then
    log_error "Tổng dung lượng các file image ($TOTAL_DYNAMIC_SIZE bytes) lớn hơn giới hạn Super ($GROUP_SIZE bytes)!"
fi

log_info "Tổng dung lượng Dynamic images: $TOTAL_DYNAMIC_SIZE bytes (~$((TOTAL_DYNAMIC_SIZE/1024/1024)) MB)"
log_info "Group size thiết lập: $GROUP_SIZE bytes"
log_info "Super size thiết lập: $SUPER_SIZE bytes"

tg_notify "🔨 <b>[Bước 4/5] Đang đóng gói super.img</b>...%0A📊 <b>Tổng size phân vùng:</b> ~$((TOTAL_DYNAMIC_SIZE/1024/1024)) MB%0A💾 <b>Super Size đích:</b> ~$((SUPER_SIZE/1024/1024)) MB"

if ! command -v lpmake >/dev/null 2>&1; then
    log_error "Không tìm thấy công cụ 'lpmake' trong PATH!"
fi

log_info "Bắt đầu tạo super.img..."
lpmake \
    --metadata-size 65536 \
    --super-name super \
    --metadata-slots 3 \
    --device "super:${SUPER_SIZE}" \
    --group "qti_dynamic_partitions_a:${GROUP_SIZE}" \
    --group "qti_dynamic_partitions_b:${GROUP_SIZE}" \
    "${LPMAKE_ARGS[@]}" \
    --virtual-ab \
    --sparse \
    --output "$OUT_DIR/images/super.img"

SUPER_IMG_SIZE=$(ls -lh "$OUT_DIR/images/super.img" | awk '{print $5}')
log_success "Đã tạo thành công super.img dạng sparse ($SUPER_IMG_SIZE) tại: $OUT_DIR/images/super.img"

# 6. Tạo script flash tự động cho Windows (.bat) và Linux (.sh)
log_info "Đang tạo script flash (flash_all.bat & flash_all.sh)..."

# Script flash cho Linux/Mac
cat << 'EOF' > "$OUT_DIR/flash_all.sh"
#!/usr/bin/env bash
set -e
echo "============================================="
echo "   XIAOMI FASTBOOT FLASH SCRIPT (LINUX/MAC)   "
echo "============================================="

FASTBOOT="fastboot"

if ! command -v $FASTBOOT >/dev/null 2>&1; then
    echo "Lỗi: Không tìm thấy lệnh fastboot trong PATH!"
    exit 1
fi

echo "Đang kiểm tra kết nối thiết bị fastboot..."
$FASTBOOT devices

flash_if_exists() {
    local part=$1
    local file="images/$2"
    if [ -f "$file" ]; then
        echo "Flashing $part ..."
        $FASTBOOT flash "$part" "$file"
    fi
}

flash_if_exists boot boot.img
flash_if_exists init_boot init_boot.img
flash_if_exists vendor_boot vendor_boot.img
flash_if_exists dtbo dtbo.img
flash_if_exists vbmeta vbmeta.img
flash_if_exists vbmeta_system vbmeta_system.img
flash_if_exists recovery recovery.img
flash_if_exists modem modem.img
flash_if_exists dsp dsp.img
flash_if_exists bluetooth bluetooth.img
flash_if_exists super super.img

echo "Quá trình nạp hoàn tất! Đang khởi động lại máy..."
$FASTBOOT reboot
echo "DONE!"
EOF

chmod +x "$OUT_DIR/flash_all.sh"

# Script flash cho Windows
cat << 'EOF' > "$OUT_DIR/flash_all.bat"
@echo off
title Xiaomi Fastboot ROM Flasher
echo =============================================
echo    XIAOMI FASTBOOT FLASH SCRIPT (WINDOWS)
echo =============================================
set FASTBOOT=fastboot.exe

where %FASTBOOT% >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Khong tim thay fastboot.exe! Hay copy vao thu muc platform-tools.
    pause
    exit /b 1
)

echo Dang kiem tra ket noi thiet bi...
%FASTBOOT% devices

call :flash_img boot boot.img
call :flash_img init_boot init_boot.img
call :flash_img vendor_boot vendor_boot.img
call :flash_img dtbo dtbo.img
call :flash_img vbmeta vbmeta.img
call :flash_img vbmeta_system vbmeta_system.img
call :flash_img recovery recovery.img
call :flash_img modem modem.img
call :flash_img dsp dsp.img
call :flash_img bluetooth bluetooth.img
call :flash_img super super.img

echo =============================================
echo Flash hoan tat! Dang khoi dong lai thiet bi...
%FASTBOOT% reboot
pause
exit /b 0

:flash_img
if exist "images\%~2" (
    echo Dang nạp %~1...
    %FASTBOOT% flash %~1 "images\%~2"
)
exit /b 0
EOF

log_success "Đã tạo đầy đủ trọn bộ Fastboot ROM tại: $OUT_DIR"
tg_notify "✅ <b>[Bước 5/5] Hoàn thành tạo super.img ($SUPER_IMG_SIZE)</b> và các script flash! Đang chuyển sang đóng gói phát hành..."
ls -lh "$OUT_DIR/images"
