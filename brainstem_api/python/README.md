# han_dog_message (Python)

四足机器人 Han Dog 的 gRPC/Protobuf Python 客户端库。

详细文档请参阅 [项目根目录 README](../README.md)。

## 安装

```bash
pip install git+https://github.com/Kitjesen/han_dog_message.git#subdirectory=python
```

## 快速开始

```python
import grpc
from han_dog_message import cms_pb2, cms_pb2_grpc
from google.protobuf.empty_pb2 import Empty

channel = grpc.insecure_channel('localhost:13145')
stub = cms_pb2_grpc.CmsStub(channel)

# 发送站立指令
stub.StandUp(Empty())

# 订阅 IMU 数据
for imu in stub.ListenImu(Empty()):
    print(f'gyro: ({imu.gyroscope.x:.3f}, {imu.gyroscope.y:.3f}, {imu.gyroscope.z:.3f})')
```
