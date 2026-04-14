// 06_motor_control.cpp — 电机操作全流程：诊断、清错、标零、实时关节监控
#include "orix/orix.h"

#include <algorithm>
#include <chrono>
#include <iomanip>
#include <iostream>
#include <thread>

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
        // ── 1. 电机诊断 ───────────────────────────────────────
        std::cout << "=== 电机诊断 ===\n";
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
            std::string st = (m.online && m.errors.empty()) ? "OK   " : "FAULT";
            std::cout
                << "  [" << std::setw(2) << m.id << "] "
                << std::setw(10) << std::left << JOINT_NAMES[m.id] << std::right
                << "  " << st
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
        if (min_v < 42.0)
            std::cout << "  WARNING: 最低电压 " << min_v << "V < 42V，请充电!\n";
        else
            std::cout << "  电压正常 (阈值 42V)\n";

        // ── 3. 故障处理 ───────────────────────────────────────
        if (fault_count > 0) {
            std::cout << "\n=== 故障处理 ===\n";
            std::vector<int> faulted;
            for (const auto& m : motors)
                if (!m.errors.empty()) faulted.push_back(m.id);

            std::cout << "故障关节: ";
            for (int id : faulted) std::cout << JOINT_NAMES[id] << " ";
            std::cout << "\n清除故障中...\n";
            dog.clear_motor_fault(faulted);
            std::this_thread::sleep_for(std::chrono::milliseconds(500));

            auto motors2 = dog.get_motor_status();
            bool all_clear = true;
            for (const auto& m : motors2)
                if (!m.errors.empty()) { all_clear = false; break; }
            std::cout << (all_clear ? "  所有故障已清除!\n" : "  仍有故障，请检查硬件连接。\n");
        }

        // ── 4. 标零（须在 Grounded 状态）────────────────────
        std::cout << "\n=== 零点标定 ===\n";
        if (orix::to_string(dog.get_state()) == "grounded") {
            std::cout << "当前在 Grounded 状态，执行标零...\n";
            dog.set_zero();
            std::cout << "标零完成。\n";
        } else {
            std::cout << "当前状态非 Grounded，跳过标零。\n";
        }

        // ── 5. 实时关节监控（5 秒）───────────────────────────
        std::cout << "\n=== 实时关节监控（5 秒）===\n";
        dog.enable();
        dog.stand_up();
        std::this_thread::sleep_for(std::chrono::seconds(1));

        int count = 0;
        dog.listen_joint([&](const orix::JointData& j) -> bool {
            const char* name = j.id < 16 ? JOINT_NAMES[j.id] : "unknown";
            std::cout << "\r  [" << std::setw(2) << j.id << "] "
                      << std::setw(10) << std::left << name << std::right
                      << "  pos=" << std::setw(7) << j.position
                      << "  vel=" << std::setw(7) << j.velocity
                      << "  trq=" << std::setw(6) << j.torque
                      << std::flush;
            return ++count < 250; // ~5s at 50Hz
        });
        std::cout << "\n\n监控结束。\n";

    } catch (const orix::OrixError& e) {
        std::cerr << "错误: " << e.what() << "\n";
    }

    try { dog.sit_down(); } catch (...) {}
    try { dog.disable();  } catch (...) {}
    return 0;
}
