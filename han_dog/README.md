## quick start

```bash
git pull
dart pub get
```

目前是运行 example/mini/2/real1.dart


## issue

拉取失败, 则先ping一下：

```bash
ssh -T git@github.com
```

---

[bloc](https://bloclibrary.dev/bloc-concepts/#stream-usage)

```dart
final M m = M(brain)..add(Init());
await Future.delayed(Duration.zero); // 必须切换事件循环来完成初始化
```

---

tick 需要 timeout，因为切换可能会丢失 tick

---

quat 的计算有误
