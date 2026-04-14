// 08_camera_record.cpp — 后台录像：定时录制 + 手动停止
#include "orix/orix_camera.h"

#include <chrono>
#include <csignal>
#include <iostream>
#include <thread>

static volatile bool g_interrupt = false;
static void sig_handler(int) { g_interrupt = true; }

int main(int argc, char* argv[]) {
    double duration = 10.0; // 默认录制 10 秒
    if (argc >= 2) duration = std::stod(argv[1]);

    std::signal(SIGINT, sig_handler);

    try {
        orix::OrixCamera cam(0, 640, 480, 30);
        cam.open();

        auto [w, h] = cam.get_frame_size();
        std::cout << "摄像头: " << w << "x" << h << "\n";

        // ── 定时录制 ──────────────────────────────────────────
        std::cout << "开始录制（" << duration << " 秒）: orix_record.mp4\n";
        cam.start_recording("orix_record.mp4", duration);

        auto t0 = std::chrono::steady_clock::now();
        while (cam.is_recording() && !g_interrupt) {
            auto elapsed = std::chrono::duration<double>(
                std::chrono::steady_clock::now() - t0).count();
            std::cout << "\r录制中... " << std::fixed << std::setprecision(1)
                      << elapsed << " / " << duration << " s  " << std::flush;
            std::this_thread::sleep_for(std::chrono::milliseconds(200));
        }
        std::cout << "\n";

        if (g_interrupt) {
            std::cout << "收到中断信号，停止录制...\n";
            cam.stop_recording();
        } else {
            // 等录制线程自然结束
            while (cam.is_recording())
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }

        std::cout << "录制完成: orix_record.mp4\n";

        // ── 验证：读取录制文件的帧数 ──────────────────────────
        cv::VideoCapture verify("orix_record.mp4");
        if (verify.isOpened()) {
            int frames = static_cast<int>(verify.get(cv::CAP_PROP_FRAME_COUNT));
            double fps = verify.get(cv::CAP_PROP_FPS);
            std::cout << "验证: " << frames << " 帧, "
                      << fps << " fps, "
                      << (frames / fps) << " 秒\n";
        }

        cam.close();

    } catch (const std::exception& e) {
        std::cerr << "错误: " << e.what() << "\n";
        return 1;
    }

    return 0;
}
