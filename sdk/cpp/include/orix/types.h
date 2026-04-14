// orix/types.h — ORIX C++ SDK 公共数据类型
//
// 所有角度单位 rad，角速度 rad/s，力矩 N·m。
#pragma once

#include <string>
#include <vector>

namespace orix {

struct Vec3 {
    double x = 0.0;
    double y = 0.0;
    double z = 0.0;
};

struct Quat {
    double w = 1.0;
    double x = 0.0;
    double y = 0.0;
    double z = 0.0;
};

struct ImuData {
    Vec3   gyroscope;     // 角速度 (rad/s), body frame
    Quat   quaternion;    // 姿态四元数，Hamilton 约定 (w, x, y, z)
    double timestamp_ms = 0.0;  // 相对于会话启动的时间 (ms)
};

struct JointData {
    int    id       = 0;    // 关节索引 0-15
    double position = 0.0;  // rad
    double velocity = 0.0;  // rad/s
    double torque   = 0.0;  // N·m
    int    status   = 0;    // 电机状态码
};

struct MotorInfo {
    int    id          = 0;
    bool   online      = false;
    double temperature = 0.0;   // °C
    double voltage     = 0.0;   // V
    double position    = 0.0;   // rad
    double velocity    = 0.0;   // rad/s
    double torque      = 0.0;   // N·m
    std::vector<int> errors;    // 空 = 无故障
};

struct ProfileInfo {
    std::string              current;
    std::vector<std::string> available;
    std::vector<std::string> descriptions;
};

struct GestureInfo {
    std::string name;
    std::string description;
    int         duration_ms = 0;
};

// 机器人 FSM 状态
enum class RobotState {
    Zero          = 0,
    Grounded      = 1,
    Standing      = 2,
    Walking       = 3,
    Transitioning = 4,
    Unknown       = -1,
};

// 将 RobotState 转为可读字符串
inline std::string to_string(RobotState s) {
    switch (s) {
        case RobotState::Zero:          return "zero";
        case RobotState::Grounded:      return "grounded";
        case RobotState::Standing:      return "standing";
        case RobotState::Walking:       return "walking";
        case RobotState::Transitioning: return "transitioning";
        default:                        return "unknown";
    }
}

} // namespace orix
