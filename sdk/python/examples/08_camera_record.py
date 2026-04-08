"""录像示例：录制指定时长的视频。

用法:
    # 录制 10 秒 (默认)
    python 08_camera_record.py

    # 录制 30 秒
    python 08_camera_record.py 30

    # 指定摄像头源和时长
    python 08_camera_record.py 15 rtsp://192.168.66.190:8554/cam
"""

import sys
import time

from brainstem_sdk.camera import OrixCamera

# ── 参数解析 ────────────────────────────────────────────────

duration = 10.0  # 默认录制 10 秒
source = 0       # 默认 USB 摄像头

if len(sys.argv) > 1:
    try:
        duration = float(sys.argv[1])
    except ValueError:
        source = sys.argv[1]

if len(sys.argv) > 2:
    arg = sys.argv[2]
    source = int(arg) if arg.isdigit() else arg

# ── 录制 ────────────────────────────────────────────────────

output_file = "orix_recording.mp4"

with OrixCamera(source=source) as cam:
    w, h = cam.get_frame_size()
    print(f"摄像头: {w}x{h}")
    print(f"开始录制 {duration} 秒 → {output_file}")
    print("录制中... (按 Ctrl+C 提前停止)")

    cam.start_recording(output_file, duration=duration)

    start = time.monotonic()
    try:
        while cam.is_recording:
            elapsed = time.monotonic() - start
            remaining = max(0.0, duration - elapsed)
            print(
                f"\r  已录制 {elapsed:.1f}s / {duration:.1f}s "
                f"(剩余 {remaining:.1f}s)",
                end="", flush=True,
            )
            time.sleep(0.5)
    except KeyboardInterrupt:
        print("\n用户中断，停止录制...")
        cam.stop_recording()

    print(f"\n录制完成: {output_file}")
