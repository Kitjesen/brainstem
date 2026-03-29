#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# brainstem 一键部署脚本
#
# 在新机器上运行一次即可完成全部环境配置。
# 用法: sudo bash scripts/setup_brainstem.sh
#
# 前提:
#   - Ubuntu 22.04 aarch64 (RDK X5 / S100P)
#   - PCAN USB 设备已接好
#   - Hi91 IMU USB 已接好
#   - 有网络连接（用于 clone CSerialPort）
# ═══════════════════════════════════════════════════════════════

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRAINSTEM_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

info()  { echo -e "\033[32m[INFO]\033[0m  $*"; }
warn()  { echo -e "\033[33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[31m[ERROR]\033[0m $*"; exit 1; }
step()  { echo -e "\n\033[36m══ $* ══\033[0m"; }

if [ "$(id -u)" -ne 0 ]; then
  error "请用 sudo 运行: sudo bash $0"
fi

REAL_USER="${SUDO_USER:-$(whoami)}"
REAL_HOME="$(eval echo ~$REAL_USER)"

# ──────────────────────────────────────────────────────────────
step "1/7 USB 串口驱动 (CH341 + CP210x)"
# ──────────────────────────────────────────────────────────────

modprobe usbserial 2>/dev/null || true
modprobe ch341 2>/dev/null || true
modprobe cp210x 2>/dev/null || true

cat > /etc/modules-load.d/usb-serial.conf << 'EOF'
usbserial
ch341
cp210x
EOF
info "USB 串口驱动已加载 + 开机自启"

# ──────────────────────────────────────────────────────────────
step "2/7 CAN 接口自启 (SocketCAN 1Mbps)"
# ──────────────────────────────────────────────────────────────

cat > /etc/systemd/system/can-setup.service << 'EOF'
[Unit]
Description=Setup CAN interfaces for brainstem
After=network.target sys-subsystem-net-devices-can0.device
Wants=sys-subsystem-net-devices-can0.device
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/sleep 3
ExecStart=/bin/bash -c 'for i in 0 1 2 3; do ip link set can$i down 2>/dev/null; ip link set can$i type can bitrate 1000000; ip link set can$i txqueuelen 100; ip link set can$i up; done'
ExecStop=/bin/bash -c 'for i in 0 1 2 3; do ip link set can$i down 2>/dev/null; done'
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable can-setup.service
systemctl restart can-setup.service || warn "CAN 接口启动失败（PCAN USB 可能未接）"
info "CAN 接口 systemd service 已配置"

# ──────────────────────────────────────────────────────────────
step "3/7 编译安装 libcserialport (IMU 串口库)"
# ──────────────────────────────────────────────────────────────

CSERIAL_SRC="$BRAINSTEM_ROOT/serial_port/src/CSerialPort"

if [ ! -f "$CSERIAL_SRC/CMakeLists.txt" ]; then
  info "克隆 CSerialPort 源码..."
  rm -rf "$CSERIAL_SRC"
  su - "$REAL_USER" -c "git clone --depth 1 https://gitee.com/itas109/CSerialPort.git '$CSERIAL_SRC'" || \
  su - "$REAL_USER" -c "git clone --depth 1 https://github.com/itas109/CSerialPort.git '$CSERIAL_SRC'" || \
    error "CSerialPort 源码克隆失败"
fi

BUILD_DIR="/tmp/cserialport_build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
cmake "$CSERIAL_SRC/bindings/c/" \
  -DCSERIALPORT_ENABLE_UTF8=ON \
  -DCMAKE_BUILD_TYPE=Release > /dev/null 2>&1
make -j$(nproc) > /dev/null 2>&1

cp "$BUILD_DIR/lib/libcserialport.so" /lib/aarch64-linux-gnu/libcserialport.so
ldconfig
info "libcserialport.so 已编译安装"

# ──────────────────────────────────────────────────────────────
step "4/7 链接 libpcanbasic (PCAN Basic API)"
# ──────────────────────────────────────────────────────────────

if [ -f /lib/libpcanbasic.so ] && [ ! -f /lib/aarch64-linux-gnu/libpcanbasic.so ]; then
  ln -sf /lib/libpcanbasic.so /lib/aarch64-linux-gnu/libpcanbasic.so
  ldconfig
  info "libpcanbasic.so 已链接"
elif [ -f /lib/aarch64-linux-gnu/libpcanbasic.so ]; then
  info "libpcanbasic.so 已存在"
else
  warn "libpcanbasic.so 未找到（SocketCAN 后端会自动降级，无影响）"
fi

# ──────────────────────────────────────────────────────────────
step "5/7 链接 libonnxruntime (ONNX 推理引擎)"
# ──────────────────────────────────────────────────────────────

# 按优先级查找 onnxruntime
ORT_SO=""
for candidate in \
  "$REAL_HOME/data/askme/.venv/lib/python3.10/site-packages/onnxruntime/capi/libonnxruntime.so"* \
  /usr/lib/libonnxruntime.so \
  /lib/libonnxruntime.so \
  /lib/aarch64-linux-gnu/libonnxruntime.so; do
  if [ -f "$candidate" ]; then
    ORT_SO="$candidate"
    break
  fi
done

if [ -n "$ORT_SO" ]; then
  ln -sf "$ORT_SO" /lib/aarch64-linux-gnu/libonnxruntime.so
  ldconfig
  info "libonnxruntime.so → $ORT_SO"
else
  warn "libonnxruntime.so 未找到 — 需要手动安装 onnxruntime"
fi

# ──────────────────────────────────────────────────────────────
step "6/7 检查 Dart SDK"
# ──────────────────────────────────────────────────────────────

DART_BIN=""
for candidate in \
  "$REAL_HOME/data/dart-sdk/bin/dart" \
  "$REAL_HOME/dart-sdk/bin/dart" \
  /usr/local/dart-sdk/bin/dart \
  /usr/bin/dart; do
  if [ -x "$candidate" ]; then
    DART_BIN="$candidate"
    break
  fi
done

if [ -n "$DART_BIN" ]; then
  info "Dart SDK: $($DART_BIN --version 2>&1)"
else
  warn "Dart SDK 未找到 — 需要手动安装"
fi

# ──────────────────────────────────────────────────────────────
step "7/7 检查 ONNX 模型"
# ──────────────────────────────────────────────────────────────

MODEL_PATH="$BRAINSTEM_ROOT/model/policy_260106.onnx"
if [ -f "$MODEL_PATH" ]; then
  info "ONNX 模型: $MODEL_PATH ($(du -h "$MODEL_PATH" | cut -f1))"
else
  warn "ONNX 模型不存在: $MODEL_PATH — 需要手动复制"
fi

# ──────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  brainstem 环境配置完成!"
echo ""
echo "  启动真机模式:"
echo "    cd $BRAINSTEM_ROOT"
echo "    HAN_DOG_IMU_PORT=/dev/ttyUSB0 \\"
echo "    LD_PRELOAD=/lib/aarch64-linux-gnu/libcserialport.so \\"
echo "    $DART_BIN run han_dog/bin/han_dog.dart"
echo ""
echo "  诊断工具:"
echo "    $DART_BIN run han_dog/bin/ping.dart          # 电机连接"
echo "    $DART_BIN run han_dog/bin/calibrate_can.dart  # CAN↔腿映射"
echo "═══════════════════════════════════════════════════════════"
