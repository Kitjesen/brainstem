// 03_motor_diagnostics.cpp — 电机诊断：电压、状态、故障清除
#include "orix/orix.h"

#include <algorithm>
#include <iomanip>
#include <iostream>
#include <string>

static const char* JOINT_NAMES[16] = {
    "FR_hip",  "FR_thigh", "FR_calf",
    "FL_hip",  "FL_thigh", "FL_calf",
    "RR_hip",  "RR_thigh", "RR_calf",
    "RL_hip",  "RL_thigh", "RL_calf",
    "FR_foot", "FL_foot",  "RR_foot", "RL_foot",
};

int main() {
    orix::OrixClient dog("192.168.66.190");

    if (!dog.ping()) {
        std::cerr << "无法连接到机器人。\n";
        return 1;
    }

    try {
        // ── 1. 电机状态 ───────────────────────────────────────
        std::cout << "=== 电机状态 ===\n";
        auto motors = dog.get_motor_status();

        int online_count = 0, fault_count = 0;
        for (const auto& m : motors) {
            if (m.online) ++online_count;
            if (!m.errors.empty()) ++fault_count;
        }
        std::cout << "在线: " << online_count << "/16  "
                  << "故障: " << fault_count  << "/16\n\n";

        std::cout << std::fixed << std::setprecision(2);
        for (const auto& m : motors) {
            std::string status = (m.online && m.errors.empty()) ? "OK   " : "FAULT";
            std::cout
                << "  [" << std::setw(2) << m.id << "] "
                << std::setw(10) << std::left << JOINT_NAMES[m.id] << std::right
                << "  " << status
                << "  temp=" << std::setw(5) << m.temperature << "C"
                << "  V="    << std::setw(5) << m.voltage
                << "  pos="  << std::setw(7) << m.position  << "rad"
                << "  vel="  << std::setw(7) << m.velocity
                << "  trq="  << std::setw(6) << m.torque    << "Nm\n";
        }

        // ── 2. 电压检查 ───────────────────────────────────────
        std::cout << "\n=== 电压检查 ===\n";
        auto voltages = dog.get_voltage();

        double min_v = *std::min_element(voltages.begin(), voltages.end());
        double max_v = *std::max_element(voltages.begin(), voltages.end());
        std::cout << "电压范围: " << min_v << "V ~ " << max_v << "V\n";
        if (min_v < 42.0) {
            std::cout << "  WARNING: 最低电压 " << min_v << "V < 42V，请充电!\n";
        } else {
            std::cout << "  电压正常 (阈值 42V)\n";
        }

        // ── 3. 故障处理 ───────────────────────────────────────
        if (fault_count > 0) {
            std::cout << "\n=== 故障处理 ===\n";
            std::vector<int> faulted;
            for (const auto& m : motors) {
                if (!m.errors.empty()) faulted.push_back(m.id);
            }
            std::cout << "故障关节: ";
            for (int id : faulted) std::cout << JOINT_NAMES[id] << " ";
            std::cout << "\n清除故障中...\n";
            dog.clear_motor_fault(faulted);
            std::cout << "已发送清除指令。\n";
        }

        // ── 4. 当前状态 & 策略 ────────────────────────────────
        std::cout << "\n=== 运行信息 ===\n";
        std::cout << "FSM 状态: " << orix::to_string(dog.get_state()) << "\n";

        auto profile = dog.get_profile();
        std::cout << "当前策略: " << profile.current << "\n";
        std::cout << "可用策略: ";
        for (const auto& p : profile.available) std::cout << p << " ";
        std::cout << "\n";

        // ── 5. 可用动作 ───────────────────────────────────────
        std::cout << "\n=== 预设动作 ===\n";
        auto gestures = dog.list_gestures();
        for (const auto& g : gestures) {
            std::cout << "  " << std::setw(12) << std::left << g.name
                      << "  " << g.description
                      << "  (" << g.duration_ms << "ms)\n";
        }

    } catch (const orix::OrixError& e) {
        std::cerr << "错误: " << e.what() << "\n";
        return 1;
    }

    return 0;
}
