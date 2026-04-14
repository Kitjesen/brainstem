// 01_hello_walk.cpp — 最简示例：使能 → 站起 → 走路 → 坐下
#include "orix/orix.h"

#include <iostream>
#include <thread>
#include <chrono>

int main() {
    orix::OrixClient dog("192.168.66.190");

    if (!dog.ping()) {
        std::cerr << "无法连接到机器人，请检查 IP 和网络。\n";
        return 1;
    }

    try {
        dog.enable();

        dog.stand_up();
        std::cout << "机器人已站立。3 秒后开始走路...\n";
        std::this_thread::sleep_for(std::chrono::seconds(3));

        // 以 30% 速度前进
        dog.walk(0.3);
        std::cout << "正在前进。3 秒后停止...\n";
        std::this_thread::sleep_for(std::chrono::seconds(3));

        dog.walk(0.0);   // 停止
        dog.sit_down();
        std::cout << "完成。\n";

    } catch (const orix::InvalidStateError& e) {
        std::cerr << "状态错误: " << e.what() << "\n";
    } catch (const orix::ConnectionError& e) {
        std::cerr << "连接错误: " << e.what() << "\n";
    } catch (const orix::OrixError& e) {
        std::cerr << "SDK 错误: " << e.what() << "\n";
    }

    try { dog.sit_down(); }  catch (...) {}
    try { dog.disable();  }  catch (...) {}

    return 0;
}
