// orix/orix_client.h — ORIX C++ SDK 主客户端类
//
// 3 行走路示例：
//
//   orix::OrixClient dog("192.168.66.190");
//   dog.enable();
//   dog.stand_up();
//   dog.walk(0.3);   // 前进 30% 速度
//   dog.sit_down();
//   dog.disable();
#pragma once

#include "orix/errors.h"
#include "orix/types.h"

#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace orix {

class OrixClient {
public:
    // ── 构造 / 析构 ──────────────────────────────────────────
    /**
     * 创建客户端并建立 gRPC channel（不立即连接，首次 RPC 时才握手）。
     *
     * @param host     机器人 IP，默认 "192.168.66.190"
     * @param port     gRPC 端口，默认 13145
     * @param timeout  默认 RPC 超时秒数，默认 5.0s
     */
    explicit OrixClient(
        std::string host    = "192.168.66.190",
        int         port    = 13145,
        double      timeout = 5.0);

    ~OrixClient();

    OrixClient(const OrixClient&)            = delete;
    OrixClient& operator=(const OrixClient&) = delete;
    OrixClient(OrixClient&&) noexcept;
    OrixClient& operator=(OrixClient&&) noexcept;

    // ── 连接检查 ─────────────────────────────────────────────
    /** 检测机器人是否可达。2 秒内无响应返回 false，不抛异常。 */
    bool ping();

    // ── 电机开关 ─────────────────────────────────────────────
    /** 使能所有电机（硬件级，不经仲裁）。 */
    void enable();
    /** 禁用所有电机（安全停止）。 */
    void disable();

    // ── 运动指令 ─────────────────────────────────────────────
    /**
     * 发送行走指令。
     * 首次调用须在 Standing 状态（触发 Standing → Walking 转换）；
     * 行走中可持续调用以更新速度；传 (0,0,0) 停止行走。
     *
     * @param vx    前后速度 [-1, 1]，正 = 前进
     * @param vy    左右速度 [-1, 1]，正 = 向左
     * @param vyaw  旋转速度 [-1, 1]，正 = 逆时针
     */
    void walk(double vx = 0.0, double vy = 0.0, double vyaw = 0.0);

    /** 从坐姿过渡到站立（需在 Grounded 状态）。 */
    void stand_up();

    /** 从站立过渡到坐姿（需在 Standing/Walking 状态）。 */
    void sit_down();

    // ── 速度模式 ─────────────────────────────────────────────
    /**
     * 开启/关闭高速模式（最大 2.5 m/s）。
     * 需在开阔平坦场地使用，机器人须处于 Standing 状态。
     */
    void        set_high_speed(bool enabled = true);
    /** 返回 "normal" 或 "high_speed"。 */
    std::string get_speed_mode();

    // ── 状态查询 ─────────────────────────────────────────────
    /** 获取当前 FSM 状态。 */
    RobotState             get_state();
    /** 读取全部 16 个电机总线电压（V）。 */
    std::vector<double>    get_voltage();
    /** 查询全部 16 个电机健康状态。 */
    std::vector<MotorInfo> get_motor_status();

    // ── 策略管理 ─────────────────────────────────────────────
    /** 获取当前策略及可用策略列表。 */
    ProfileInfo get_profile();
    /**
     * 切换策略（机器人须处于 Grounded 状态）。
     * @param name  策略名，见 get_profile().available
     */
    ProfileInfo switch_profile(const std::string& name);

    // ── 动作系统 ─────────────────────────────────────────────
    /** 列出所有可用预设动作。 */
    std::vector<GestureInfo> list_gestures();
    /**
     * 播放预设动作（机器人须处于 Standing 状态）。
     * 可用动作：bow（鞠躬）、nod（点头）、wiggle（扭动）、
     *           stretch（伸展）、dance（跳舞）。
     * @param name       动作名，见 list_gestures()
     * @param timeout_s  最大等待秒数，默认 30s
     */
    void play_gesture(const std::string& name, double timeout_s = 30.0);

    // ── 诊断 ─────────────────────────────────────────────────
    /**
     * 清除电机故障码。
     * @param joint_ids  要清除的关节索引(0-15)；空 = 清除全部
     */
    void clear_motor_fault(const std::vector<int>& joint_ids = {});
    /** 将当前位置标记为零点（须在 Grounded 状态）。 */
    void set_zero();

    // ── 流式接口（阻塞，建议在独立线程中调用）───────────────
    /**
     * 订阅实时 IMU 数据流（~50 Hz）。
     *
     * callback 返回 true 继续接收，返回 false 停止流。
     *
     * 示例（5 秒后停止）：
     * @code
     *   auto t0 = std::chrono::steady_clock::now();
     *   dog.listen_imu([&](const orix::ImuData& d) {
     *       std::cout << d.gyroscope.x << "\n";
     *       auto elapsed = std::chrono::steady_clock::now() - t0;
     *       return elapsed < std::chrono::seconds(5);
     *   });
     * @endcode
     */
    void listen_imu(const std::function<bool(const ImuData&)>& callback);

    /**
     * 订阅实时关节数据流。
     * callback 返回 true 继续，false 停止。
     */
    void listen_joint(const std::function<bool(const JointData&)>& callback);

    /**
     * 订阅 FSM 状态变更事件。
     * callback 返回 true 继续，false 停止。
     */
    void listen_state(const std::function<bool(RobotState)>& callback);

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace orix
