// orix/errors.h — ORIX C++ SDK 异常类型
#pragma once

#include <stdexcept>
#include <string>

namespace orix {

// 所有 ORIX SDK 异常的基类
class OrixError : public std::runtime_error {
public:
    explicit OrixError(const std::string& msg) : std::runtime_error(msg) {}
};

// 无法连接到机器人（gRPC UNAVAILABLE）
class ConnectionError : public OrixError {
public:
    explicit ConnectionError(const std::string& msg) : OrixError(msg) {}
};

// 机器人状态不符合操作前提（gRPC FAILED_PRECONDITION）
// 例：机器人未站立时调用 walk()
class InvalidStateError : public OrixError {
public:
    explicit InvalidStateError(const std::string& msg) : OrixError(msg) {}
};

// RPC 超时（gRPC DEADLINE_EXCEEDED）
class TimeoutError : public OrixError {
public:
    explicit TimeoutError(const std::string& msg) : OrixError(msg) {}
};

} // namespace orix
