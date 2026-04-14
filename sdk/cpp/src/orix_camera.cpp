// orix_camera.cpp — OrixCamera 实现
#include "orix/orix_camera.h"

#include <atomic>
#include <chrono>
#include <cstring>
#include <mutex>
#include <stdexcept>
#include <thread>
#include <vector>

// ── 平台 Socket ───────────────────────────────────────────────
#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  include <winsock2.h>
#  pragma comment(lib, "ws2_32.lib")
   using sock_t = SOCKET;
   static constexpr sock_t SOCK_INVALID = INVALID_SOCKET;
   inline void sock_close(sock_t s) { closesocket(s); }
   inline bool sock_valid(sock_t s) { return s != INVALID_SOCKET; }
   struct WsaInit {
       WsaInit()  { WSADATA d; WSAStartup(MAKEWORD(2,2), &d); }
       ~WsaInit() { WSACleanup(); }
   };
   static WsaInit _wsa;
#else
#  include <sys/socket.h>
#  include <netinet/in.h>
#  include <arpa/inet.h>
#  include <unistd.h>
   using sock_t = int;
   static constexpr sock_t SOCK_INVALID = -1;
   inline void sock_close(sock_t s) { ::close(s); }
   inline bool sock_valid(sock_t s) { return s >= 0; }
#endif

namespace orix {

// ── Impl ─────────────────────────────────────────────────────

struct OrixCamera::Impl {
    // 摄像头来源（整数 = 设备索引，字符串 = URL）
    bool        is_url   = false;
    int         src_idx  = 0;
    std::string src_url;
    int         req_w    = 640;
    int         req_h    = 480;
    int         req_fps  = 30;

    cv::VideoCapture cap;

    // ── 录制 ─────────────────────────────────────────────────
    std::atomic<bool>     recording{false};
    std::mutex            rec_mtx;
    cv::VideoWriter       writer;
    std::thread           rec_thread;
    std::atomic<bool>     rec_stop{false};

    // ── MJPEG 流 ─────────────────────────────────────────────
    std::atomic<bool>     streaming{false};
    std::thread           stream_capture_thread;
    std::thread           stream_server_thread;
    std::mutex            frame_mtx;
    std::vector<uint8_t>  latest_jpeg;   // 最新 JPEG 帧
    sock_t                server_sock = SOCK_INVALID;
    std::atomic<bool>     stream_stop{false};

    ~Impl() {
        // 确保析构时所有后台线程都停止
        stop_recording_impl();
        stop_stream_impl();
        if (cap.isOpened()) cap.release();
    }

    void stop_recording_impl() {
        if (!recording) return;
        rec_stop = true;
        if (rec_thread.joinable()) rec_thread.join();
        std::lock_guard<std::mutex> g(rec_mtx);
        if (writer.isOpened()) writer.release();
        recording = false;
        rec_stop  = false;
    }

    void stop_stream_impl() {
        if (!streaming) return;
        stream_stop = true;
        if (sock_valid(server_sock)) {
            sock_close(server_sock);
            server_sock = SOCK_INVALID;
        }
        if (stream_capture_thread.joinable()) stream_capture_thread.join();
        if (stream_server_thread.joinable())  stream_server_thread.join();
        streaming   = false;
        stream_stop = false;
        std::lock_guard<std::mutex> g(frame_mtx);
        latest_jpeg.clear();
    }
};

// ── 构造 / 析构 ───────────────────────────────────────────────

OrixCamera::OrixCamera(int source, int width, int height, int fps)
    : impl_(std::make_unique<Impl>())
{
    impl_->src_idx = source;
    impl_->req_w   = width;
    impl_->req_h   = height;
    impl_->req_fps = fps;
}

OrixCamera::OrixCamera(const std::string& url)
    : impl_(std::make_unique<Impl>())
{
    impl_->is_url  = true;
    impl_->src_url = url;
}

OrixCamera::~OrixCamera() = default;

OrixCamera::OrixCamera(OrixCamera&&) noexcept            = default;
OrixCamera& OrixCamera::operator=(OrixCamera&&) noexcept = default;

// ── 基础操作 ──────────────────────────────────────────────────

bool OrixCamera::open() {
    if (impl_->cap.isOpened()) return true;

    bool ok = impl_->is_url
        ? impl_->cap.open(impl_->src_url)
        : impl_->cap.open(impl_->src_idx);

    if (!ok) {
        std::string src = impl_->is_url
            ? impl_->src_url
            : std::to_string(impl_->src_idx);
        throw CameraOpenError(
            "Failed to open camera source=" + src +
            ". Check that the device exists and is not in use.");
    }

    if (!impl_->is_url) {
        impl_->cap.set(cv::CAP_PROP_FRAME_WIDTH,  impl_->req_w);
        impl_->cap.set(cv::CAP_PROP_FRAME_HEIGHT, impl_->req_h);
        impl_->cap.set(cv::CAP_PROP_FPS,          impl_->req_fps);
    }

    return true;
}

void OrixCamera::close() {
    impl_->stop_recording_impl();
    impl_->stop_stream_impl();
    if (impl_->cap.isOpened()) impl_->cap.release();
}

bool OrixCamera::is_opened() const {
    return impl_->cap.isOpened();
}

cv::Mat OrixCamera::read() {
    if (!is_opened()) return {};
    cv::Mat frame;
    impl_->cap.read(frame);
    return frame;
}

std::pair<int, int> OrixCamera::get_frame_size() const {
    if (!is_opened()) return {0, 0};
    return {
        static_cast<int>(impl_->cap.get(cv::CAP_PROP_FRAME_WIDTH)),
        static_cast<int>(impl_->cap.get(cv::CAP_PROP_FRAME_HEIGHT)),
    };
}

// ── 拍照 ──────────────────────────────────────────────────────

bool OrixCamera::save_photo(const std::string& path) {
    cv::Mat frame = read();
    if (frame.empty()) return false;
    return cv::imwrite(path, frame);
}

// ── 录像 ──────────────────────────────────────────────────────

void OrixCamera::start_recording(
    const std::string& path,
    double             duration,
    const std::string& codec)
{
    if (!is_opened())    throw std::runtime_error("Camera not open");
    if (impl_->recording) throw std::runtime_error("Already recording");

    auto [w, h] = get_frame_size();
    double fps  = impl_->cap.get(cv::CAP_PROP_FPS);
    if (fps <= 0) fps = impl_->req_fps;

    int fourcc = cv::VideoWriter::fourcc(
        codec[0], codec[1], codec[2], codec[3]);

    {
        std::lock_guard<std::mutex> g(impl_->rec_mtx);
        impl_->writer.open(path, fourcc, fps, {w, h});
        if (!impl_->writer.isOpened())
            throw std::runtime_error("Cannot create video writer: " + path);
        impl_->recording = true;
    }

    impl_->rec_stop = false;
    impl_->rec_thread = std::thread([this, duration] {
        auto t0 = std::chrono::steady_clock::now();
        while (!impl_->rec_stop) {
            if (duration > 0) {
                auto elapsed = std::chrono::steady_clock::now() - t0;
                if (elapsed >= std::chrono::duration<double>(duration)) break;
            }
            cv::Mat frame = read();
            if (frame.empty()) {
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
                continue;
            }
            std::lock_guard<std::mutex> g(impl_->rec_mtx);
            if (impl_->writer.isOpened()) impl_->writer.write(frame);
        }
        std::lock_guard<std::mutex> g(impl_->rec_mtx);
        if (impl_->writer.isOpened()) impl_->writer.release();
        impl_->recording = false;
    });
}

void OrixCamera::stop_recording() {
    impl_->stop_recording_impl();
}

bool OrixCamera::is_recording() const {
    return impl_->recording;
}

// ── MJPEG 流服务器 ────────────────────────────────────────────

// 帧采集线程：持续将最新帧编码为 JPEG
static void capture_loop(OrixCamera::Impl* impl) {
    while (!impl->stream_stop) {
        cv::Mat frame;
        impl->cap.read(frame);
        if (frame.empty()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
            continue;
        }
        std::vector<uint8_t> buf;
        std::vector<int> params = {cv::IMWRITE_JPEG_QUALITY, 80};
        cv::imencode(".jpg", frame, buf, params);
        {
            std::lock_guard<std::mutex> g(impl->frame_mtx);
            impl->latest_jpeg = std::move(buf);
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(33)); // ~30fps
    }
}

// 向客户端发送一个字符串
static bool send_all(sock_t fd, const char* data, size_t len) {
    size_t sent = 0;
    while (sent < len) {
#ifdef _WIN32
        int n = send(fd, data + sent, static_cast<int>(len - sent), 0);
        if (n == SOCKET_ERROR) return false;
#else
        ssize_t n = ::send(fd, data + sent, len - sent, MSG_NOSIGNAL);
        if (n <= 0) return false;
#endif
        sent += static_cast<size_t>(n);
    }
    return true;
}

// HTTP 流处理线程：接受连接并推送 MJPEG 帧
static void server_loop(OrixCamera::Impl* impl, int port, const std::string& host) {
    sock_t srv = socket(AF_INET, SOCK_STREAM, 0);
    if (!sock_valid(srv)) return;

    int opt = 1;
#ifdef _WIN32
    setsockopt(srv, SOL_SOCKET, SO_REUSEADDR,
               reinterpret_cast<const char*>(&opt), sizeof(opt));
#else
    setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
#endif

    sockaddr_in addr{};
    addr.sin_family      = AF_INET;
    addr.sin_port        = htons(static_cast<uint16_t>(port));
    addr.sin_addr.s_addr = host == "0.0.0.0"
        ? INADDR_ANY
        : inet_addr(host.c_str());

    if (bind(srv, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
        sock_close(srv);
        return;
    }
    listen(srv, 4);

    impl->server_sock = srv;

    while (!impl->stream_stop) {
        // 非阻塞 accept（使用 select with timeout）
        fd_set fds;
        FD_ZERO(&fds);
        FD_SET(srv, &fds);
        timeval tv{0, 200'000}; // 200ms timeout
        int r = select(static_cast<int>(srv) + 1, &fds, nullptr, nullptr, &tv);
        if (r <= 0) continue;

        sock_t cli = accept(srv, nullptr, nullptr);
        if (!sock_valid(cli)) continue;

        // 读取 HTTP 请求（不解析路径，一律推送流）
        char buf[1024];
#ifdef _WIN32
        recv(cli, buf, sizeof(buf) - 1, 0);
#else
        ::recv(cli, buf, sizeof(buf) - 1, 0);
#endif

        // 发送 HTTP 响应头
        const char* hdr =
            "HTTP/1.1 200 OK\r\n"
            "Content-Type: multipart/x-mixed-replace; boundary=frame\r\n"
            "Cache-Control: no-cache\r\n"
            "Connection: close\r\n"
            "\r\n";
        if (!send_all(cli, hdr, strlen(hdr))) {
            sock_close(cli);
            continue;
        }

        // 推送帧直到客户端断开或流停止
        while (!impl->stream_stop) {
            std::vector<uint8_t> jpeg;
            {
                std::lock_guard<std::mutex> g(impl->frame_mtx);
                jpeg = impl->latest_jpeg;
            }
            if (jpeg.empty()) {
                std::this_thread::sleep_for(std::chrono::milliseconds(33));
                continue;
            }

            std::string part_hdr =
                "--frame\r\n"
                "Content-Type: image/jpeg\r\n"
                "Content-Length: " + std::to_string(jpeg.size()) + "\r\n"
                "\r\n";

            if (!send_all(cli, part_hdr.c_str(), part_hdr.size()) ||
                !send_all(cli, reinterpret_cast<const char*>(jpeg.data()), jpeg.size()) ||
                !send_all(cli, "\r\n", 2))
            {
                break; // 客户端已断开
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(33));
        }
        sock_close(cli);
    }

    sock_close(srv);
    impl->server_sock = SOCK_INVALID;
}

void OrixCamera::stream_mjpeg(int port, const std::string& host) {
    if (!is_opened())   throw CameraOpenError("Camera not open");
    if (impl_->streaming) throw std::runtime_error("Stream already running");

    impl_->stream_stop = false;
    impl_->streaming   = true;

    impl_->stream_capture_thread = std::thread(capture_loop, impl_.get());
    impl_->stream_server_thread  = std::thread(server_loop, impl_.get(), port, host);
}

void OrixCamera::stop_stream() {
    impl_->stop_stream_impl();
}

bool OrixCamera::is_streaming() const {
    return impl_->streaming;
}

} // namespace orix
