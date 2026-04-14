// 05_gestures.cpp — 预设动作系统：列表 + 顺序播放
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

    try {
        // ── 1. 列出所有可用动作 ───────────────────────────────
        std::cout << "=== 可用预设动作 ===\n";
        auto gestures = dog.list_gestures();

        if (gestures.empty()) {
            std::cout << "  （无可用动作）\n";
            return 0;
        }

        for (const auto& g : gestures) {
            std::cout
                << "  " << std::setw(12) << std::left << g.name
                << "  " << std::setw(8) << std::right << g.duration_ms << " ms"
                << "  " << g.description << "\n";
        }

        // ── 2. 站起来，准备播放动作 ───────────────────────────
        std::cout << "\n使能并站立中...\n";
        dog.enable();
        dog.stand_up();
        std::this_thread::sleep_for(std::chrono::seconds(2));

        // ── 3. 逐一播放每个动作 ───────────────────────────────
        std::cout << "\n=== 开始播放动作序列 ===\n";
        for (const auto& g : gestures) {
            std::cout << "播放：" << g.name
                      << "（预计 " << g.duration_ms << " ms）...\n";
            try {
                dog.play_gesture(g.name, g.duration_ms / 1000.0 + 5.0);
                std::cout << "  完成。\n";
            } catch (const orix::TimeoutError& e) {
                std::cerr << "  超时: " << e.what() << "\n";
            } catch (const orix::InvalidStateError& e) {
                std::cerr << "  状态错误: " << e.what() << "\n";
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
        }

        std::cout << "\n动作序列播放完毕。\n";

    } catch (const orix::OrixError& e) {
        std::cerr << "错误: " << e.what() << "\n";
    }

    try { dog.sit_down(); } catch (...) {}
    try { dog.disable();  } catch (...) {}
    return 0;
}
