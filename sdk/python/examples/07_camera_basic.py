"""摄像头基础示例：实时预览 + 拍照。

用法:
    # 在机器狗上运行 (USB 摄像头)
    python 07_camera_basic.py

    # 指定远程 RTSP 流
    python 07_camera_basic.py rtsp://192.168.66.190:8554/cam

操作:
    q — 退出
    s — 保存照片到当前目录
"""

import sys
import time

from brainstem_sdk.camera import OrixCamera

# ── 解析摄像头源 ────────────────────────────────────────────

source = 0  # 默认: USB 摄像头 index 0
if len(sys.argv) > 1:
    arg = sys.argv[1]
    # 如果是纯数字，当作设备索引
    source = int(arg) if arg.isdigit() else arg

# ── 主循环 ──────────────────────────────────────────────────

try:
    import cv2
except ImportError:
    print("需要安装 opencv-python:")
    print("  pip install brainstem-sdk[camera]")
    sys.exit(1)

photo_count = 0

with OrixCamera(source=source) as cam:
    w, h = cam.get_frame_size()
    print(f"摄像头已打开: {w}x{h}")
    print("按 'q' 退出, 按 's' 拍照")

    while True:
        frame = cam.read()
        if frame is None:
            print("读取帧失败，等待重试...")
            time.sleep(0.1)
            continue

        cv2.imshow("ORIX Camera", frame)

        key = cv2.waitKey(1) & 0xFF
        if key == ord("q"):
            break
        elif key == ord("s"):
            photo_count += 1
            filename = f"orix_photo_{photo_count:03d}.jpg"
            cam.save_photo(filename)
            print(f"已保存: {filename}")

cv2.destroyAllWindows()
print(f"共拍摄 {photo_count} 张照片。")
