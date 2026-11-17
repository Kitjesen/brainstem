# Example

## 正式版本

- **main.dart** — 正式控制程序。使用 YUNZHUO 遥控器 + 真实电机/IMU，本地控制机器狗。

## 真实硬件

- **real_mini_dog_1.dart** — 真实硬件 + gRPC 服务器远程控制（电机动作未启用）。
- **real_mini_dog_2.dart** — main.dart 的原始版本，真实硬件 + YUNZHUO 本地控制。
- **real_control.dart** — 单独测试 YUNZHUO 遥控器收发。

## 仿真

- **sim_mini_dog.dart** — 仿真环境 + gRPC 服务器，模型 mini_policy6。
- **sim_mini_dog_2.dart** — 仿真环境 + gRPC 服务器，模型 mini_pose3_flat。

## 工具

- **compare.dart** — 对比真实与仿真的观测数据（case1_real.json vs case1.json）。

## mini/ 子目录

历史版本的实验脚本，使用 history_size=5 和 policy_1119 模型：

- **mini/1/sim.dart** — 仿真，history_size=1，模型 policy_3。
- **mini/2/sim1.dart** — 仿真，history_size=5，模型 policy_1119。
- **mini/2/real1.dart** — 真实硬件 + gRPC，模型 policy_1119。
- **mini/2/show1.dart** — 真实硬件 + YUNZHUO 控制，模型 policy_1119。
- **mini/2/case1.dart** — 仿真录制观测数据，用于对比分析。
