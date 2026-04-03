"""MJPEG 流服务器示例：让远程浏览器查看摄像头画面。

用法:
    # 默认端口 8080
    python 09_camera_stream.py

    # 自定义端口
    python 09_camera_stream.py 9090

启动后，在浏览器中打开:
    http://<机器狗IP>:8080/           — 带样式的查看页面
    http://<机器狗IP>:8080/stream     — 原始 MJPEG 流
    http://<机器狗IP>:8080/snapshot   — 单帧 JPEG 快照
"""

import sys
import signal

from brainstem_sdk.camera import OrixCamera

# ── 参数解析 ────────────────────────────────────────────────

port = 8080
source = 0

for arg in sys.argv[1:]:
    if arg.isdigit():
        port = int(arg)
    else:
        source = arg

# ── 启动流服务器 ────────────────────────────────────────────

cam = OrixCamera(source=source)

if not cam.open():
    print("无法打开摄像头，请检查设备连接。")
    sys.exit(1)

w, h = cam.get_frame_size()
print(f"摄像头已打开: {w}x{h}")


def shutdown(signum, frame):
    print("\n正在关闭...")
    cam.close()
    sys.exit(0)


signal.signal(signal.SIGINT, shutdown)
signal.signal(signal.SIGTERM, shutdown)

cam.stream_mjpeg(port=port)

print(f"MJPEG 流服务器已启动于端口 {port}")
print(f"  查看页面: http://0.0.0.0:{port}/")
print(f"  原始流:   http://0.0.0.0:{port}/stream")
print(f"  快照:     http://0.0.0.0:{port}/snapshot")
print()
print("按 Ctrl+C 停止服务器")

# 保持主线程运行
try:
    signal.pause()
except AttributeError:
    # Windows 不支持 signal.pause()，用循环替代
    import time
    while True:
        time.sleep(1.0)
