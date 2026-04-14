// 07_camera_basic.cpp — 摄像头基本操作：打开、读帧、拍照
//
// 编译需要 OpenCV。在 CMakeLists.txt 中启用：
//   find_package(OpenCV REQUIRED)
//   target_link_libraries(07_camera_basic PRIVATE orix_sdk orix_camera ${OpenCV_LIBS})
#include "orix/orix_camera.h"

#include <iostream>
#include <thread>
#include <chrono>

int main(int argc, char* argv[]) {
    // 支持命令行指定摄像头源（索引或 URL）
    // 用法：
    //   ./07_camera_basic          # 默认 USB 摄像头 0
    //   ./07_camera_basic 1        # USB 摄像头 1
    //   ./07_camera_basic rtsp://192.168.66.190:8554/cam

    try {
        std::unique_ptr<orix::OrixCamera> cam;

        if (argc >= 2) {
            std::string src(argv[1]);
            // 如果是纯数字则作为设备索引
            bool is_number = !src.empty() && std::all_of(
                src.begin(), src.end(), ::isdigit);
            if (is_number)
                cam = std::make_unique<orix::OrixCamera>(std::stoi(src));
            else
                cam = std::make_unique<orix::OrixCamera>(src);
        } else {
            cam = std::make_unique<orix::OrixCamera>(0, 640, 480, 30);
        }

        cam->open();

        auto [w, h] = cam->get_frame_size();
        std::cout << "摄像头已打开：" << w << "x" << h << "\n";

        // ── 读取 10 帧，统计成功率 ────────────────────────────
        std::cout << "读取 10 帧...\n";
        int ok = 0;
        for (int i = 0; i < 10; ++i) {
            cv::Mat frame = cam->read();
            if (!frame.empty()) {
                ++ok;
                std::cout << "  帧 " << i + 1 << ": "
                          << frame.cols << "x" << frame.rows
                          << " channels=" << frame.channels() << "\n";
            } else {
                std::cout << "  帧 " << i + 1 << ": 读取失败\n";
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(33));
        }
        std::cout << "成功率: " << ok << "/10\n\n";

        // ── 拍照保存 ──────────────────────────────────────────
        std::cout << "拍照中...\n";
        if (cam->save_photo("orix_photo.jpg")) {
            std::cout << "照片已保存: orix_photo.jpg\n";
        } else {
            std::cerr << "拍照失败。\n";
        }

        cam->close();

    } catch (const orix::CameraOpenError& e) {
        std::cerr << "摄像头错误: " << e.what() << "\n";
        return 1;
    } catch (const std::exception& e) {
        std::cerr << "错误: " << e.what() << "\n";
        return 1;
    }

    return 0;
}
