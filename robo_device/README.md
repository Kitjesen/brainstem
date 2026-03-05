## quick start

pcan 通信

```dart
// 通过范型制定不同的协议
final device = PcanController<RSEvent, RSState>(PcanChannel.usbbus1)..open();
// 监听状态
device.state.listen(print);
// 发送事件
device.add(RSEvent.enable(127));
```

serial port 通信

```dart
final device = SerialPortController<RSEvent, RSState>('/dev/ttyUSB0')..open();
// 监听状态
device.state.listen(print);
// 发送事件
device.add(RSEvent.enable(127));
```
