// orix/orix_camera.h — ORIX 摄像头接口（需要 OpenCV）
//
// 支持两种模式：
//   本地模式：直接读 USB 摄像头（在机器人上运行时）
//   远程模式：通过 RTSP/MJPEG URL 读取（在开发机上运行时）
//
// 依赖：OpenCV >= 4.5
//
// 示例：
//   orix::OrixCamera cam;
//   cam.open();
//   cam.save_photo("photo.jpg");
//   cam.close();
#pragma once

#include <functional>
#include <memory>
#include <string>
#include <utility>

#include <opencv2/opencv.hpp>

namespace orix {

// 摄像头无法打开时抛出（设备不存在、被占用、URL 无效）
class CameraOpenError : public std::runtime_error {
public:
    explicit CameraOpenError(const std::string& msg)
        : std::runtime_error(msg) {}
};

class OrixCamera {
public:
    // ── 构造（USB 摄像头，设备索引）────────────────────────────
    explicit OrixCamera(
        int source = 0,
        int width  = 640,
        int height = 480,
        int fps    = 30);

    // ── 构造（RTSP / MJPEG URL）────────────────────────────────
    explicit OrixCamera(const std::string& url);

    ~OrixCamera();

    OrixCamera(const OrixCamera&)            = delete;
    OrixCamera& operator=(const OrixCamera&) = delete;
    OrixCamera(OrixCamera&&) noexcept;
    OrixCamera& operator=(OrixCamera&&) noexcept;

    // ── 上下文管理器风格 ─────────────────────────────────────
    OrixCamera& operator*() { return *this; }

    // ── 基础操作 ─────────────────────────────────────────────
    /**
     * 打开摄像头。
     * @throws CameraOpenError 设备不存在或 URL 无法连接。
     */
    bool open();
    /** 释放摄像头及所有相关资源（自动停止录制和流服务器）。 */
    void close();
    bool is_opened() const;

    /**
     * 读取一帧图像（BGR 格式）。
     * @return 帧数据，失败时返回空 Mat（使用 .empty() 检查）。
     */
    cv::Mat read();

    /** 返回当前画面尺寸 (width, height)，未打开时返回 (0, 0)。 */
    std::pair<int, int> get_frame_size() const;

    // ── 拍照 ─────────────────────────────────────────────────
    /**
     * 拍摄并保存一张照片。
     * @param path 保存路径，如 "photo.jpg" / "capture.png"。
     * @return 是否保存成功。
     */
    bool save_photo(const std::string& path);

    // ── 录像 ─────────────────────────────────────────────────
    /**
     * 开始后台录像（线程安全）。
     * @param path      输出文件路径，如 "output.mp4"。
     * @param duration  录制时长(秒)；<= 0 表示持续录制，需调用 stop_recording()。
     * @param codec     FourCC 编码器，默认 "mp4v"。
     * @throws std::runtime_error 摄像头未打开或已在录制中。
     */
    void start_recording(
        const std::string& path,
        double             duration = -1.0,
        const std::string& codec   = "mp4v");

    /** 停止录像（如未录制则无操作）。 */
    void stop_recording();

    bool is_recording() const;

    // ── MJPEG 流服务器 ───────────────────────────────────────
    /**
     * 启动 MJPEG HTTP 流服务器（后台线程，不阻塞调用者）。
     * 浏览器访问 http://<ip>:<port>/stream 查看实时画面，
     *            http://<ip>:<port>/snapshot 获取单帧快照。
     * @param port 端口号，默认 8080。
     * @param host 绑定地址，默认 "0.0.0.0"。
     * @throws CameraOpenError 摄像头未打开。
     * @throws std::runtime_error 端口被占用或流已在运行。
     */
    void stream_mjpeg(int port = 8080, const std::string& host = "0.0.0.0");

    /** 停止 MJPEG 流服务器（如未运行则无操作）。 */
    void stop_stream();

    bool is_streaming() const;

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace orix
