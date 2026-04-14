// 02_read_imu.cpp — 订阅 IMU 数据流（5 秒后自动停止）
#include "orix/orix.h"

#include <chrono>
#include <iomanip>
#include <iostream>
#include <thread>

int main() {
    orix::OrixClient dog("192.168.66.190");

    if (!dog.ping()) {
        std::cerr << "无法连接到机器人。\n";
        return 1;
    }

    std::cout << "订阅 IMU 数据流（5 秒）...\n";
    std::cout << std::fixed << std::setprecision(4);

    auto t0 = std::chrono::steady_clock::now();
    int  count = 0;

    // listen_imu 在当前线程阻塞，callback 返回 false 时停止
    dog.listen_imu([&](const orix::ImuData& d) -> bool {
        auto elapsed = std::chrono::steady_clock::now() - t0;
        if (elapsed >= std::chrono::seconds(5)) return false;

        ++count;
        if (count % 25 == 0) {  // 每 0.5 秒打印一次
            std::cout
                << "gyro: ["
                << std::setw(8) << d.gyroscope.x << ", "
                << std::setw(8) << d.gyroscope.y << ", "
                << std::setw(8) << d.gyroscope.z << "]  "
                << "quat: w=" << std::setw(7) << d.quaternion.w
                << "  t=" << std::setprecision(1) << d.timestamp_ms << "ms\n"
                << std::setprecision(4);
        }
        return true;
    });

    std::cout << "\n共接收 " << count << " 帧，平均频率 "
              << (count / 5.0) << " Hz\n";

    return 0;
}
