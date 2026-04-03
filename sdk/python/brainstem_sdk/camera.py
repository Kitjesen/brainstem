"""ORIX 机器狗摄像头接口。

支持两种模式:
1. 本地模式: 直接连接 USB 摄像头 (在机器狗上运行时)
2. 远程模式: 通过 RTSP/MJPEG 流从网络读取 (在开发机上运行时)

快速上手::

    from brainstem_sdk.camera import OrixCamera

    with OrixCamera() as cam:
        frame = cam.read()
        cam.save_photo("photo.jpg")

依赖: pip install brainstem-sdk[camera]
"""

from __future__ import annotations

import io
import logging
import threading
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from typing import Optional, Tuple, Union

logger = logging.getLogger("brainstem_sdk.camera")

# ── OpenCV 延迟导入 ─────────────────────────────────────────

_cv2 = None
_np = None


def _ensure_cv2():
    """延迟导入 opencv-python，未安装时给出清晰的安装提示。"""
    global _cv2, _np
    if _cv2 is not None:
        return
    try:
        import cv2
        import numpy
        _cv2 = cv2
        _np = numpy
    except ImportError as exc:
        raise ImportError(
            "摄像头功能需要 opencv-python 和 numpy。\n"
            "请运行: pip install brainstem-sdk[camera]\n"
            "或单独安装: pip install opencv-python>=4.5.0 numpy>=1.20.0"
        ) from exc


# ── OrixCamera ──────────────────────────────────────────────


class OrixCamera:
    """ORIX 机器狗摄像头接口。

    支持两种模式:
    1. 本地模式: 直接连接 USB 摄像头 (在机器狗上运行时)
    2. 远程模式: 通过 RTSP/MJPEG 流从网络读取 (在开发机上运行时)

    Args:
        source: 摄像头源。整数为 USB 设备索引 (默认 0)，字符串为
                RTSP/MJPEG URL (如 ``"rtsp://192.168.66.190:8554/cam"``)。
        width:  请求的画面宽度 (默认 640)。仅对 USB 摄像头有效。
        height: 请求的画面高度 (默认 480)。仅对 USB 摄像头有效。
        fps:    请求的帧率 (默认 30)。仅对 USB 摄像头有效。

    Example::

        # 本地 USB 摄像头
        cam = OrixCamera(source=0)

        # 远程 RTSP 流
        cam = OrixCamera(source="rtsp://192.168.66.190:8554/cam")

        # 上下文管理器 (推荐)
        with OrixCamera() as cam:
            frame = cam.read()
    """

    def __init__(
        self,
        source: Union[int, str] = 0,
        width: int = 640,
        height: int = 480,
        fps: int = 30,
    ):
        _ensure_cv2()
        self._source = source
        self._width = width
        self._height = height
        self._fps = fps

        self._cap = None  # cv2.VideoCapture 实例

        # ── 录制状态 ────────────────────────────────────────
        self._recording = False
        self._record_writer = None  # cv2.VideoWriter
        self._record_thread: Optional[threading.Thread] = None
        self._record_stop_event = threading.Event()
        self._record_lock = threading.Lock()

        # ── MJPEG 流状态 ────────────────────────────────────
        self._stream_server: Optional[HTTPServer] = None
        self._stream_thread: Optional[threading.Thread] = None
        self._stream_frame: Optional[bytes] = None  # 最新 JPEG 帧
        self._stream_frame_lock = threading.Lock()
        self._stream_running = False

    # ── 上下文管理器 ────────────────────────────────────────

    def __enter__(self):
        self.open()
        return self

    def __exit__(self, *args):
        self.close()

    # ── 基础操作 ────────────────────────────────────────────

    def open(self) -> bool:
        """打开摄像头。

        Returns:
            是否成功打开。
        """
        _ensure_cv2()
        if self._cap is not None and self._cap.isOpened():
            return True

        self._cap = _cv2.VideoCapture(self._source)

        if not self._cap.isOpened():
            logger.error("无法打开摄像头: source=%s", self._source)
            self._cap = None
            return False

        # 仅对 USB 设备设置分辨率和帧率
        if isinstance(self._source, int):
            self._cap.set(_cv2.CAP_PROP_FRAME_WIDTH, self._width)
            self._cap.set(_cv2.CAP_PROP_FRAME_HEIGHT, self._height)
            self._cap.set(_cv2.CAP_PROP_FPS, self._fps)

        actual_w = int(self._cap.get(_cv2.CAP_PROP_FRAME_WIDTH))
        actual_h = int(self._cap.get(_cv2.CAP_PROP_FRAME_HEIGHT))
        actual_fps = self._cap.get(_cv2.CAP_PROP_FPS)
        logger.info(
            "摄像头已打开: source=%s, 分辨率=%dx%d, FPS=%.1f",
            self._source, actual_w, actual_h, actual_fps,
        )
        return True

    def close(self):
        """释放摄像头及所有相关资源。"""
        # 先停止录制和流
        if self._recording:
            self.stop_recording()
        if self._stream_running:
            self._stop_stream_server()

        if self._cap is not None:
            self._cap.release()
            self._cap = None
            logger.info("摄像头已释放")

    def is_opened(self) -> bool:
        """检查摄像头是否已打开。"""
        return self._cap is not None and self._cap.isOpened()

    def read(self):
        """读取一帧图像。

        Returns:
            numpy.ndarray (BGR 格式，OpenCV 标准) 或 None (读取失败)。
        """
        if not self.is_opened():
            logger.warning("摄像头未打开，请先调用 open()")
            return None

        ret, frame = self._cap.read()
        if not ret:
            logger.warning("读取帧失败")
            return None
        return frame

    def get_frame_size(self) -> Tuple[int, int]:
        """获取当前画面尺寸。

        Returns:
            (width, height) 元组。摄像头未打开时返回 (0, 0)。
        """
        if not self.is_opened():
            return (0, 0)
        w = int(self._cap.get(_cv2.CAP_PROP_FRAME_WIDTH))
        h = int(self._cap.get(_cv2.CAP_PROP_FRAME_HEIGHT))
        return (w, h)

    # ── 拍照 ────────────────────────────────────────────────

    def save_photo(self, path: str) -> bool:
        """拍摄并保存一张照片。

        Args:
            path: 保存路径，如 ``"photo.jpg"``、``"capture.png"``。

        Returns:
            是否保存成功。
        """
        frame = self.read()
        if frame is None:
            logger.error("拍照失败: 无法读取帧")
            return False

        ok = _cv2.imwrite(path, frame)
        if ok:
            logger.info("照片已保存: %s", path)
        else:
            logger.error("照片保存失败: %s", path)
        return ok

    # ── 录像 ────────────────────────────────────────────────

    def start_recording(
        self,
        path: str,
        duration: Optional[float] = None,
        codec: str = "mp4v",
    ):
        """开始录像。

        线程安全，会在后台线程持续抓帧并写入视频文件。

        Args:
            path:     输出文件路径，如 ``"output.mp4"``。
            duration: 录制时长 (秒)。None 表示持续录制直到调用
                      ``stop_recording()``。
            codec:    FourCC 编码器 (默认 ``"mp4v"``)。

        Raises:
            RuntimeError: 摄像头未打开或已在录制中。
        """
        if not self.is_opened():
            raise RuntimeError("摄像头未打开，请先调用 open()")

        with self._record_lock:
            if self._recording:
                raise RuntimeError("已在录制中，请先调用 stop_recording()")

            w, h = self.get_frame_size()
            fps = self._cap.get(_cv2.CAP_PROP_FPS) or self._fps
            fourcc = _cv2.VideoWriter_fourcc(*codec)
            self._record_writer = _cv2.VideoWriter(path, fourcc, fps, (w, h))

            if not self._record_writer.isOpened():
                self._record_writer = None
                raise RuntimeError(f"无法创建视频写入器: {path}")

            self._recording = True
            self._record_stop_event.clear()

        logger.info(
            "开始录像: %s (codec=%s, %dx%d, %.1f fps, duration=%s)",
            path, codec, w, h, fps,
            f"{duration}s" if duration else "unlimited",
        )

        self._record_thread = threading.Thread(
            target=self._record_loop,
            args=(duration,),
            daemon=True,
            name="orix-camera-record",
        )
        self._record_thread.start()

    def stop_recording(self):
        """停止录像。

        如果当前没有在录制，此方法不会报错。
        """
        with self._record_lock:
            if not self._recording:
                return
            self._record_stop_event.set()

        # 等待录制线程结束
        if self._record_thread is not None:
            self._record_thread.join(timeout=5.0)
            self._record_thread = None

        with self._record_lock:
            if self._record_writer is not None:
                self._record_writer.release()
                self._record_writer = None
            self._recording = False

        logger.info("录像已停止")

    @property
    def is_recording(self) -> bool:
        """是否正在录制。"""
        return self._recording

    def _record_loop(self, duration: Optional[float]):
        """录制线程的主循环。"""
        start = time.monotonic()
        frame_count = 0

        while not self._record_stop_event.is_set():
            if duration is not None and (time.monotonic() - start) >= duration:
                break

            frame = self.read()
            if frame is None:
                # 短暂等待后重试
                time.sleep(0.01)
                continue

            with self._record_lock:
                if self._record_writer is not None and self._record_writer.isOpened():
                    self._record_writer.write(frame)
                    frame_count += 1

        elapsed = time.monotonic() - start
        actual_fps = frame_count / elapsed if elapsed > 0 else 0
        logger.info(
            "录制结束: %d 帧, %.1f 秒, 实际 %.1f fps",
            frame_count, elapsed, actual_fps,
        )

        # 如果是 duration 到期自动停止，需要清理
        with self._record_lock:
            if self._record_writer is not None:
                self._record_writer.release()
                self._record_writer = None
            self._recording = False

    # ── MJPEG 流服务器 ──────────────────────────────────────

    def stream_mjpeg(self, port: int = 8080):
        """启动 MJPEG HTTP 流服务器，供远程浏览器查看摄像头画面。

        在后台线程运行，不阻塞调用者。浏览器访问
        ``http://<robot-ip>:<port>/`` 即可看到实时画面。

        Args:
            port: HTTP 服务端口 (默认 8080)。

        Raises:
            RuntimeError: 摄像头未打开或流服务器已在运行。
        """
        if not self.is_opened():
            raise RuntimeError("摄像头未打开，请先调用 open()")
        if self._stream_running:
            raise RuntimeError("MJPEG 流服务器已在运行")

        self._stream_running = True

        # 启动帧采集线程
        capture_thread = threading.Thread(
            target=self._stream_capture_loop,
            daemon=True,
            name="orix-camera-stream-capture",
        )
        capture_thread.start()

        # 创建 HTTP 服务器
        camera_ref = self
        server_address = ("0.0.0.0", port)

        class MJPEGHandler(BaseHTTPRequestHandler):
            """处理 MJPEG 流请求的 HTTP handler。"""

            def do_GET(self):
                if self.path == "/":
                    # 返回一个简单的 HTML 页面
                    self.send_response(200)
                    self.send_header("Content-Type", "text/html; charset=utf-8")
                    self.end_headers()
                    html = (
                        "<!DOCTYPE html><html><head>"
                        "<title>ORIX Camera</title>"
                        "<style>body{margin:0;background:#111;display:flex;"
                        "justify-content:center;align-items:center;height:100vh;}"
                        "img{max-width:100%;max-height:100vh;}</style>"
                        "</head><body>"
                        '<img src="/stream" />'
                        "</body></html>"
                    )
                    self.wfile.write(html.encode("utf-8"))

                elif self.path == "/stream":
                    self.send_response(200)
                    self.send_header(
                        "Content-Type",
                        "multipart/x-mixed-replace; boundary=frame",
                    )
                    self.send_header("Cache-Control", "no-cache")
                    self.end_headers()

                    while camera_ref._stream_running:
                        jpeg = camera_ref._stream_frame
                        if jpeg is None:
                            time.sleep(0.03)
                            continue
                        try:
                            self.wfile.write(b"--frame\r\n")
                            self.wfile.write(
                                b"Content-Type: image/jpeg\r\n"
                                b"Content-Length: "
                                + str(len(jpeg)).encode()
                                + b"\r\n\r\n"
                            )
                            self.wfile.write(jpeg)
                            self.wfile.write(b"\r\n")
                            self.wfile.flush()
                        except (BrokenPipeError, ConnectionResetError):
                            break
                        time.sleep(0.033)  # ~30 fps

                elif self.path == "/snapshot":
                    # 单帧快照
                    jpeg = camera_ref._stream_frame
                    if jpeg is not None:
                        self.send_response(200)
                        self.send_header("Content-Type", "image/jpeg")
                        self.send_header("Content-Length", str(len(jpeg)))
                        self.end_headers()
                        self.wfile.write(jpeg)
                    else:
                        self.send_error(503, "No frame available")
                else:
                    self.send_error(404)

            def log_message(self, format, *args):
                # 降低日志噪音
                logger.debug("MJPEG HTTP: %s", format % args)

        self._stream_server = HTTPServer(server_address, MJPEGHandler)
        self._stream_thread = threading.Thread(
            target=self._stream_server.serve_forever,
            daemon=True,
            name="orix-camera-stream-http",
        )
        self._stream_thread.start()

        logger.info(
            "MJPEG 流服务器已启动: http://0.0.0.0:%d/ "
            "(浏览器访问 /stream 查看实时画面, /snapshot 查看快照)",
            port,
        )

    def _stream_capture_loop(self):
        """持续抓帧并编码为 JPEG，供 MJPEG 流使用。"""
        while self._stream_running and self.is_opened():
            frame = self.read()
            if frame is None:
                time.sleep(0.01)
                continue
            ok, buf = _cv2.imencode(".jpg", frame, [_cv2.IMWRITE_JPEG_QUALITY, 80])
            if ok:
                with self._stream_frame_lock:
                    self._stream_frame = buf.tobytes()
            time.sleep(0.01)  # 避免 CPU 过载

    def _stop_stream_server(self):
        """停止 MJPEG 流服务器。"""
        self._stream_running = False
        if self._stream_server is not None:
            self._stream_server.shutdown()
            self._stream_server = None
        if self._stream_thread is not None:
            self._stream_thread.join(timeout=5.0)
            self._stream_thread = None
        self._stream_frame = None
        logger.info("MJPEG 流服务器已停止")

    def stop_stream(self):
        """停止 MJPEG 流服务器。

        如果服务器未运行，此方法不会报错。
        """
        if self._stream_running:
            self._stop_stream_server()
