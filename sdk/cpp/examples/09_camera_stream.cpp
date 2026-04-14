// 09_camera_stream.cpp — MJPEG HTTP 流服务器
//
// 启动后，在浏览器访问：
//   http://<机器人IP>:8080/stream    — 实时视频流
//   http://<机器人IP>:8080/snapshot  — 单帧快照
//
// 按 Ctrl+C 停止。
#include "orix/orix_camera.h"

#include <chrono>
#include <csignal>
#include <iostream>
#include <thread>

static volatile bool g_interrupt = false;
static void sig_handler(int) { g_interrupt = true; }

int main(int argc, char* argv[]) {
    int port = 8080;
    int src  = 0;
    if (argc >= 2) src  = std::stoi(argv[1]);
    if (argc >= 3) port = std::stoi(argv[2]);

    std::signal(SIGINT, sig_handler);

    try {
        orix::OrixCamera cam(src, 640, 480, 30);
        cam.open();

        auto [w, h] = cam.get_frame_size();
        std::cout << "摄像头: " << w << "x" << h << "\n";

        std::cout << "启动 MJPEG 流服务器 (端口 " << port << ")...\n";
        cam.stream_mjpeg(port, "0.0.0.0");

        std::cout << "已启动！浏览器访问：\n"
                  << "  http://localhost:" << port << "/stream    （实时流）\n"
                  << "  http://localhost:" << port << "/snapshot  （快照）\n"
                  << "按 Ctrl+C 停止。\n\n";

        // 主线程等待，每秒打印一次状态
        long secs = 0;
        while (!g_interrupt) {
            std::this_thread::sleep_for(std::chrono::seconds(1));
            ++secs;
            std::cout << "\r运行中 " << secs << "s..." << std::flush;
        }

        std::cout << "\n停止流服务器...\n";
        cam.stop_stream();
        cam.close();
        std::cout << "已停止。\n";

    } catch (const orix::CameraOpenError& e) {
        std::cerr << "摄像头错误: " << e.what() << "\n";
        return 1;
    } catch (const std::exception& e) {
        std::cerr << "错误: " << e.what() << "\n";
        return 1;
    }

    return 0;
}
