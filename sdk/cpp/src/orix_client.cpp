// orix_client.cpp — OrixClient 实现
#include "orix/orix_client.h"

#include <grpcpp/grpcpp.h>
#include <google/protobuf/empty.pb.h>

// protoc 生成的头文件（由 CMake 放到 ${PROTO_OUT}）
#include "han_dog_message/common.pb.h"
#include "han_dog_message/cms.pb.h"
#include "han_dog_message/cms.grpc.pb.h"

#include <algorithm>
#include <chrono>
#include <string>

namespace orix {

// ── Impl ─────────────────────────────────────────────────────

struct OrixClient::Impl {
    std::string                          target;
    double                               timeout_s;
    std::shared_ptr<grpc::Channel>       channel;
    std::unique_ptr<han_dog::Cms::Stub>  stub;

    Impl(const std::string& host, int port, double timeout)
        : target(host + ":" + std::to_string(port))
        , timeout_s(timeout)
        , channel(grpc::CreateChannel(target, grpc::InsecureChannelCredentials()))
        , stub(han_dog::Cms::NewStub(channel))
    {}

    // 创建带 deadline 的 ClientContext
    std::unique_ptr<grpc::ClientContext> make_ctx(double override_s = -1.0) const {
        auto ctx = std::make_unique<grpc::ClientContext>();
        double t = override_s > 0.0 ? override_s : timeout_s;
        ctx->set_deadline(std::chrono::system_clock::now()
                          + std::chrono::duration<double>(t));
        return ctx;
    }

    // 将 gRPC status 映射为 OrixError 子类并抛出
    [[noreturn]] static void throw_for(const grpc::Status& s, const char* op = "") {
        std::string msg = std::string(op) + (op[0] ? ": " : "") + s.error_message();
        switch (s.error_code()) {
            case grpc::StatusCode::UNAVAILABLE:
                throw ConnectionError(msg);
            case grpc::StatusCode::DEADLINE_EXCEEDED:
                throw TimeoutError(msg);
            case grpc::StatusCode::FAILED_PRECONDITION:
                throw InvalidStateError(msg);
            default:
                throw OrixError(msg);
        }
    }
};

// ── State 转换 ────────────────────────────────────────────────

static RobotState from_proto(han_dog::CmsStateKind k) {
    switch (k) {
        case han_dog::CMS_STATE_KIND_ZERO:          return RobotState::Zero;
        case han_dog::CMS_STATE_KIND_GROUNDED:      return RobotState::Grounded;
        case han_dog::CMS_STATE_KIND_STANDING:      return RobotState::Standing;
        case han_dog::CMS_STATE_KIND_WALKING:       return RobotState::Walking;
        case han_dog::CMS_STATE_KIND_TRANSITIONING: return RobotState::Transitioning;
        default:                                    return RobotState::Unknown;
    }
}

// ── 构造 / 析构 ───────────────────────────────────────────────

OrixClient::OrixClient(std::string host, int port, double timeout)
    : impl_(std::make_unique<Impl>(host, port, timeout))
{}

OrixClient::~OrixClient() = default;

// Move 定义在 .cpp，确保 Impl 类型完整可见
OrixClient::OrixClient(OrixClient&&) noexcept            = default;
OrixClient& OrixClient::operator=(OrixClient&&) noexcept = default;

// ── 连接检查 ──────────────────────────────────────────────────

bool OrixClient::ping() {
    try {
        auto ctx = impl_->make_ctx(2.0);
        google::protobuf::Empty req;
        han_dog::CmsState resp;
        return impl_->stub->GetCmsState(ctx.get(), req, &resp).ok();
    } catch (...) {
        return false;
    }
}

// ── 电机开关 ──────────────────────────────────────────────────

void OrixClient::enable() {
    auto ctx = impl_->make_ctx();
    google::protobuf::Empty req, resp;
    auto s = impl_->stub->Enable(ctx.get(), req, &resp);
    if (!s.ok()) Impl::throw_for(s, "enable");
}

void OrixClient::disable() {
    auto ctx = impl_->make_ctx();
    google::protobuf::Empty req, resp;
    auto s = impl_->stub->Disable(ctx.get(), req, &resp);
    if (!s.ok()) Impl::throw_for(s, "disable");
}

// ── 运动指令 ──────────────────────────────────────────────────

void OrixClient::walk(double vx, double vy, double vyaw) {
    auto clamp = [](double v) { return std::max(-1.0, std::min(1.0, v)); };
    han_dog::Vector3 req;
    req.set_x(clamp(vx));
    req.set_y(clamp(vy));
    req.set_z(clamp(vyaw));

    auto ctx = impl_->make_ctx();
    google::protobuf::Empty resp;
    auto s = impl_->stub->Walk(ctx.get(), req, &resp);
    if (!s.ok()) Impl::throw_for(s, "walk");
}

void OrixClient::stand_up() {
    auto ctx = impl_->make_ctx();
    google::protobuf::Empty req, resp;
    auto s = impl_->stub->StandUp(ctx.get(), req, &resp);
    if (!s.ok()) Impl::throw_for(s, "stand_up");
}

void OrixClient::sit_down() {
    auto ctx = impl_->make_ctx();
    google::protobuf::Empty req, resp;
    auto s = impl_->stub->SitDown(ctx.get(), req, &resp);
    if (!s.ok()) Impl::throw_for(s, "sit_down");
}

// ── 速度模式 ──────────────────────────────────────────────────

void OrixClient::set_high_speed(bool enabled) {
    han_dog::SpeedModeRequest req;
    req.set_mode(enabled ? han_dog::SPEED_MODE_HIGH : han_dog::SPEED_MODE_NORMAL);
    auto ctx = impl_->make_ctx();
    google::protobuf::Empty resp;
    auto s = impl_->stub->SetSpeedMode(ctx.get(), req, &resp);
    if (!s.ok()) Impl::throw_for(s, "set_high_speed");
}

std::string OrixClient::get_speed_mode() {
    auto ctx = impl_->make_ctx();
    google::protobuf::Empty req;
    han_dog::SpeedModeRequest resp;
    auto s = impl_->stub->GetSpeedMode(ctx.get(), req, &resp);
    if (!s.ok()) Impl::throw_for(s, "get_speed_mode");
    return resp.mode() == han_dog::SPEED_MODE_HIGH ? "high_speed" : "normal";
}

// ── 状态查询 ──────────────────────────────────────────────────

RobotState OrixClient::get_state() {
    auto ctx = impl_->make_ctx();
    google::protobuf::Empty req;
    han_dog::CmsState resp;
    auto s = impl_->stub->GetCmsState(ctx.get(), req, &resp);
    if (!s.ok()) Impl::throw_for(s, "get_state");
    return from_proto(resp.kind());
}

std::vector<double> OrixClient::get_voltage() {
    auto ctx = impl_->make_ctx();
    google::protobuf::Empty req;
    han_dog::Voltage resp;
    auto s = impl_->stub->GetVoltage(ctx.get(), req, &resp);
    if (!s.ok()) Impl::throw_for(s, "get_voltage");
    return {resp.values().begin(), resp.values().end()};
}

std::vector<MotorInfo> OrixClient::get_motor_status() {
    auto ctx = impl_->make_ctx();
    google::protobuf::Empty req;
    han_dog::MotorStatusResponse resp;
    auto s = impl_->stub->GetMotorStatus(ctx.get(), req, &resp);
    if (!s.ok()) Impl::throw_for(s, "get_motor_status");

    std::vector<MotorInfo> result;
    result.reserve(resp.motors_size());
    for (const auto& m : resp.motors()) {
        MotorInfo info;
        info.id          = static_cast<int>(m.id());
        info.online      = m.online();
        info.temperature = m.temperature();
        info.voltage     = m.voltage();
        info.position    = m.position();
        info.velocity    = m.velocity();
        info.torque      = m.torque();
        info.errors.assign(m.errors().begin(), m.errors().end());
        result.push_back(std::move(info));
    }
    return result;
}

// ── 策略管理 ──────────────────────────────────────────────────

ProfileInfo OrixClient::get_profile() {
    auto ctx = impl_->make_ctx();
    google::protobuf::Empty req;
    han_dog::ProfileInfo resp;
    auto s = impl_->stub->GetProfile(ctx.get(), req, &resp);
    if (!s.ok()) Impl::throw_for(s, "get_profile");
    return {
        resp.current(),
        {resp.available().begin(), resp.available().end()},
        {resp.descriptions().begin(), resp.descriptions().end()},
    };
}

ProfileInfo OrixClient::switch_profile(const std::string& name) {
    han_dog::ProfileRequest req;
    req.set_name(name);
    auto ctx = impl_->make_ctx();
    han_dog::ProfileInfo resp;
    auto s = impl_->stub->SwitchProfile(ctx.get(), req, &resp);
    if (!s.ok()) Impl::throw_for(s, "switch_profile");
    return {
        resp.current(),
        {resp.available().begin(), resp.available().end()},
        {resp.descriptions().begin(), resp.descriptions().end()},
    };
}

// ── 动作系统 ──────────────────────────────────────────────────

std::vector<GestureInfo> OrixClient::list_gestures() {
    auto ctx = impl_->make_ctx();
    google::protobuf::Empty req;
    han_dog::GestureList resp;
    auto s = impl_->stub->ListGestures(ctx.get(), req, &resp);
    if (!s.ok()) Impl::throw_for(s, "list_gestures");

    std::vector<GestureInfo> result;
    result.reserve(resp.gestures_size());
    for (const auto& g : resp.gestures()) {
        result.push_back({g.name(), g.description(), g.duration_ms()});
    }
    return result;
}

void OrixClient::play_gesture(const std::string& name, double timeout_s) {
    han_dog::GestureRequest req;
    req.set_name(name);
    auto ctx = impl_->make_ctx(timeout_s);
    google::protobuf::Empty resp;
    auto s = impl_->stub->PlayGesture(ctx.get(), req, &resp);
    if (!s.ok()) Impl::throw_for(s, ("play_gesture(" + name + ")").c_str());
}

// ── 诊断 ──────────────────────────────────────────────────────

void OrixClient::clear_motor_fault(const std::vector<int>& joint_ids) {
    han_dog::ClearFaultRequest req;
    for (int id : joint_ids) req.add_joint_ids(static_cast<uint32_t>(id));
    auto ctx = impl_->make_ctx();
    google::protobuf::Empty resp;
    auto s = impl_->stub->ClearMotorFault(ctx.get(), req, &resp);
    if (!s.ok()) Impl::throw_for(s, "clear_motor_fault");
}

void OrixClient::set_zero() {
    auto ctx = impl_->make_ctx();
    google::protobuf::Empty req, resp;
    auto s = impl_->stub->SetZero(ctx.get(), req, &resp);
    if (!s.ok()) Impl::throw_for(s, "set_zero");
}

// ── 流式接口 ──────────────────────────────────────────────────

void OrixClient::listen_imu(const std::function<bool(const ImuData&)>& cb) {
    grpc::ClientContext ctx;
    google::protobuf::Empty req;
    auto reader = impl_->stub->ListenImu(&ctx, req);

    han_dog::Imu msg;
    while (reader->Read(&msg)) {
        ImuData data;
        data.gyroscope  = {msg.gyroscope().x(),
                           msg.gyroscope().y(),
                           msg.gyroscope().z()};
        data.quaternion = {msg.quaternion().w(),
                           msg.quaternion().x(),
                           msg.quaternion().y(),
                           msg.quaternion().z()};
        data.timestamp_ms = msg.timestamp().seconds() * 1000.0
                          + msg.timestamp().nanos() / 1e6;
        if (!cb(data)) {
            ctx.TryCancel();
            break;
        }
    }
    reader->Finish();
}

void OrixClient::listen_joint(const std::function<bool(const JointData&)>& cb) {
    grpc::ClientContext ctx;
    google::protobuf::Empty req;
    auto reader = impl_->stub->ListenJoint(&ctx, req);

    han_dog::Joint msg;
    while (reader->Read(&msg)) {
        if (!msg.has_single_joint()) continue;
        const auto& j = msg.single_joint();
        JointData data;
        data.id       = static_cast<int>(j.id());
        data.position = j.position();
        data.velocity = j.velocity();
        data.torque   = j.torque();
        data.status   = static_cast<int>(j.status());
        if (!cb(data)) {
            ctx.TryCancel();
            break;
        }
    }
    reader->Finish();
}

void OrixClient::listen_state(const std::function<bool(RobotState)>& cb) {
    grpc::ClientContext ctx;
    google::protobuf::Empty req;
    auto reader = impl_->stub->ListenCmsState(&ctx, req);

    han_dog::CmsState msg;
    while (reader->Read(&msg)) {
        if (!cb(from_proto(msg.kind()))) {
            ctx.TryCancel();
            break;
        }
    }
    reader->Finish();
}

} // namespace orix
