## robstride

### Han Dog 电机型号与 CAN 编解码

每条腿的 CAN 总线都使用同一套 ID。当前实机配置如下：

| CAN ID | 关节 | 电机 | 速度字段 | 转矩字段 | Kp 字段 | Kd 字段 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 1 | Hip | RS04 | ±15 rad/s | ±120 Nm | 0..5000 | 0..100 |
| 2 | Thigh | RS04 | ±15 rad/s | ±120 Nm | 0..5000 | 0..100 |
| 3 | Calf | RS04 | ±15 rad/s | ±120 Nm | 0..5000 | 0..100 |
| 4 | Wheel | RS02 | ±44 rad/s | ±17 Nm | 0..500 | 0..5 |

以上是 RobStride MIT 协议中 16 位字段的**映射量程**，不是电机的连续额定能力。
命令编码和反馈解码必须使用同一型号的量程；CAN 帧即使使用了错误量程，在格式上仍然完全合法，因此不会自然报错，只会表现为跟踪比例错误、阻尼异常或控制不稳。

硬件型号的唯一配置入口是：
[`lib/src/robostride/motor_config.dart`](lib/src/robostride/motor_config.dart) 中的
`hanDogMotorLayout`。启动日志 `MOTOR_CODEC` 也由这张表自动生成，不再手写另一份参数。

更换电机时：

1. 如果换成代码已支持的型号，只修改 `hanDogMotorLayout` 对应 CAN ID 的 `model`。
2. 如果是新型号，先在 `RSMotorModel` 添加型号及厂家协议规定的四个映射量程，再加入穷尽式 `limits` 分支。
3. 运行 `dart test robo_device_proto`；未知 CAN ID 会直接报错，不再静默套用 RS04。
4. 上实机前核对启动日志中的每个 CAN ID、关节角色、型号和量程。

RS02/RS04 量程误用的典型比例：RS04 方式编码的 `10 rad/s` 被 RS02 解读为约
`29.33 rad/s`；RS02 实际反馈 `10 rad/s` 被 RS04 方式解码后只显示约
`3.41 rad/s`。

## install

```yaml
dependencies:
  device_proto:
    git:
      url: https://github.com/QiongPei/device_proto
      path: dart/device_proto
      tag_pattern: v{{version}}
    version: ^1.0.0
```


## 达妙

### g6620


## develop

- [ ] 测试一下参数的读写
- [x] 添加测试用例，比如文档里有 loc_ref 的示例
