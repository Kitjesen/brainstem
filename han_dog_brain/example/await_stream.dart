import 'dart:async';

import 'package:rxdart/rxdart.dart';

void main() async {
  final mem = Mem(3);
  mem.stream.listen((v) {
    print('mem: $v');
  });
  mem.add(1);
  mem.add(2);

  mem.add(3);
  mem.add(4);
  final vSubs = mem.stream.first;
  mem.add(5);
  print('await first: ${await vSubs}');
  mem.add(6);
  mem.stream.listen((v) {
    print('mem2: $v');
  });
  mem.add(7);
  final vSubs2 = Completer<int>();
  mem.stream.listen((v) {
    if (!vSubs2.isCompleted) {
      vSubs2.complete(v);
    }
  });
  mem.add(8);
  print('await completer: ${await vSubs2.future}');
  mem.add(9);
}

class Mem {
  final ReplaySubject<int> controller;
  Mem([int size = 5]) : controller = ReplaySubject<int>(maxSize: size);
  void add(int v) => controller.add(v);
  Stream<int> get stream => controller.stream;
}

/**
 * 

关键点有两个：

1. 你 `Mem(3)` 其实只缓存 **3 个值**，不是 5 个。
2. `ReplaySubject` 对 **新订阅者 / `.first`** 会立刻把“缓存里已有的值”重放一遍，而不是只等“之后的值”。

下面按时间线拆一次，你就能对上为啥是 `first = 2`、`completer = 5`。

---

## 1. 先看缓存里到底有什么

```dart
final mem = Mem(3); // maxSize = 3
```

`ReplaySubject<int>(maxSize: 3)`：只记住**最后 3 个**元素。

### 第一个订阅者：`mem.stream.listen(...)`

```dart
mem.stream.listen((v) {
  print('mem: $v');
});
```

此时缓存为空，啥也不重放。之后：

```dart
mem.add(1); // buffer: [1]       -> mem: 1
mem.add(2); // buffer: [1, 2]    -> mem: 2
mem.add(3); // buffer: [1, 2, 3] -> mem: 3
mem.add(4); // buffer: [2, 3, 4] -> mem: 4   (超出 3，1 被丢掉)
```

> **此时缓存 = [2, 3, 4]（从旧到新）**

---

## 2. 为什么 `first` 是 2？

```dart
final vSubs = mem.stream.first;
```

`.first` 的本质是：**新建一个订阅，拿收到的第一个值，然后取消订阅**。

因为这是 `ReplaySubject`，这个“内部订阅”一建立，就会立即收到缓存里的值 `[2, 3, 4]`。
第一个收到的是 `2`，所以：

```dart
await vSubs  // -> 2
```

你看到的：

```text
await first: 2
```

**它不是等你 `add(5)` 之后的“下一个值”，而是立刻从缓存里拿“最老的那个值”。**

接着：

```dart
mem.add(5); // buffer: [3, 4, 5] -> mem: 5
```

---

## 3. 第二个订阅者：为什么 `mem2` 从 4 开始？

```dart
mem.add(6); // buffer: [4, 5, 6] -> mem: 6

mem.stream.listen((v) {
  print('mem2: $v');
});
```

当 `mem2` 的订阅刚建立时，`ReplaySubject` 会把当前缓存 `[4, 5, 6]` 全部重放给它：

```text
mem2: 4
mem2: 5
mem2: 6
```

然后：

```dart
mem.add(7); // buffer: [5, 6, 7]
            // -> mem: 7
            // -> mem2: 7
```

> 所以 `mem2` 从 **4** 开始，是因为当它订阅时，缓存正好是 `[4, 5, 6]`，3 已经被挤掉了。

---

## 4. 第三个订阅 + `Completer`：为什么是 5，而不是 8？

```dart
final vSubs2 = Completer<int>();
final sub = mem.stream.listen((v) {
  if (!vSubs2.isCompleted) {
    vSubs2.complete(v);
  }
});
mem.add(8);
print('await completer: ${await vSubs2.future}');
```

注意：**订阅先建立，再 `add(8)`**。

当这个第三个订阅建立时，此刻缓存是 `[5, 6, 7]`（刚刚 `add(7)` 完）：

* 订阅一连上，`ReplaySubject` 马上重放缓存 `[5, 6, 7]`；
* 第一个重放出来的是 `5`，你的回调里 `vSubs2.complete(5)`；
* 之后的 `6, 7` 虽然也会被这个订阅收到，但 `vSubs2` 已经完成了，你忽略掉了。

所以：

```text
await completer: 5
```

`add(8)` 是在订阅之后发生的没错，但你用的逻辑是 **“第一次收到的值就 complete”**，而第一次收到的是**重放的 5**，不是新来的 8。

---

## 5. 总结一下行为

* `ReplaySubject(maxSize: 3)` 只记 **最后 3 个**值。
* **新订阅者**（包括 `.first` 内部用的订阅）：

  * 会先收到缓存中**从旧到新**的所有值；
  * 然后才开始收到之后新 `add` 的值。
* `.first` 取的是“这次订阅从现在起收到的第一个值”，对 `ReplaySubject` 来说，就是“缓存里最老的那一个”。

---

## 如果你想实现你“以为”的行为……

你“以为”的是：

* `first`：从**现在开始**，拿第一个未来值（忽略缓存）；
* `completer`：从**现在开始**，拿第一个未来值（例如 8）。

那可以用几种方式：

1. **不用 ReplaySubject，用普通 `PublishSubject` / `StreamController.broadcast`**
   它们不会重放历史值，新订阅只会看到之后的值。

2. 如果必须保留 ReplaySubject 的缓存，又想忽略历史，可以在订阅时跳过缓存长度，比如：

   ```dart
   final futureNext = mem.stream
       .skip(mem.controller.values.length)
       .first; // 只等未来的事件
   ```

   （具体访问缓存长度的方式要看 RxDart 版本，可用 `ReplaySubject` 的 `values` 等属性）

---

总之，你现在看到的结果完全符合 ReplaySubject 的语义：**“重放最近 N 个值给每个新订阅者”**。
你脑子里的模型更像是：“有缓存，但 `first` / 新订阅只看未来”，那就需要换 Subject 类型或者在流上再包一层操作符。


 * 
 * 
 */
