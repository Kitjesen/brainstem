import 'dart:async';

import 'package:cms/cms.dart';
import 'package:logging/logging.dart';
import 'package:han_dog_brain/src/brain.dart';
import 'package:han_dog_brain/src/common.dart';
import 'package:vector_math/vector_math.dart';

import 's.dart';
import 'a.dart';

export 's.dart';
export 'a.dart';

final _log = Logger('han_dog_brain.cms');

class M extends Cms<S, A> {
  final Brain _brain;

  M(this._brain) : super(const Zero());

  /// 监听 idle 行为（由时钟驱动的无限流）。
  /// 正常运行时 onDone 不应触发；若触发说明时钟流中断，强制触发 Fault 保持 FSM 一致性。
  StreamSubscription<History> _listenIdle() {
    return _brain.idle.doing.listen(
      _brain.memory.add,
      onError: (Object error, StackTrace st) {
        _log.severe('Idle stream error', error, st);
        Future.microtask(() => add(A.fault('Idle error: $error')));
      },
      onDone: () {
        _log.severe('Idle stream closed unexpectedly — clock interrupted?');
        Future.microtask(
          () => add(A.fault('Idle stream closed unexpectedly')),
        );
      },
    );
  }

  /// 监听过渡行为（有限流：StandUp、SitDown 或 Gesture）。
  /// 行为完成时触发 [Done]。
  StreamSubscription<History> _listenTransition(Command target) {
    final stream = switch (target) {
      StandUpCommand() => _brain.standUp.doing,
      SitDownCommand() => _brain.sitDown.doing,
      GestureCommand(:final name) => _brain.createGesture(name)?.doing
          ?? (throw StateError('Unknown gesture: $name')),
      _ => throw StateError('Invalid transition target: $target'),
    };
    return stream.listen(
      _brain.memory.add,
      onError: (Object error, StackTrace st) {
        _log.severe('Transition(${target.runtimeType}) stream error', error, st);
        Future.microtask(() => add(A.fault('Transition error: $error')));
      },
      onDone: () {
        Future.microtask(() => add(const A.done()));
      },
    );
  }

  /// 监听行走行为（由时钟驱动的无限流）。
  /// 正常运行时 onDone 不应触发；若触发说明时钟流中断，强制触发 Fault 保持 FSM 一致性。
  StreamSubscription<History> _listenWalk(Vector3 direction) {
    return _brain.walk.doing(direction).listen(
      _brain.memory.add,
      onError: (Object error, StackTrace st) {
        _log.severe('Walk stream error', error, st);
        Future.microtask(() => add(A.fault('Walk error: $error')));
      },
      onDone: () {
        _log.severe('Walk stream closed unexpectedly — clock interrupted?');
        Future.microtask(
          () => add(A.fault('Walk stream closed unexpectedly')),
        );
      },
    );
  }

  @override
  Future<void> close() async {
    // 取消当前状态持有的行为流订阅，防止资源泄漏
    switch (state) {
      case Grounded(:final sub):
      case Standing(:final sub):
      case Walking(:final sub):
      case Transitioning(:final sub):
        await sub.cancel();
      case Zero():
        break;
    }
    return super.close();
  }

  @override
  Future<S?> kernel(S s, A a) async {
    final next = await _kernelImpl(s, a);
    if (next != null) {
      _log.info('FSM ${s.runtimeType} + ${a.runtimeType} → ${next.runtimeType}');
    }
    return next;
  }

  Future<S?> _kernelImpl(S s, A a) async => switch ((s, a)) {
    // ── Zero ────────────────────────────────────────────────
    (Zero(), Init()) => Grounded(_listenIdle()),
    (Zero(), _) => () {
      _log.warning('${a.runtimeType} ignored: FSM not initialized (call Init first)');
      return null;
    }(),

    // ── Init 重入：任何已运行状态收到 Init 一律忽略 ──────────
    (_, Init()) => () {
      _log.fine('Duplicate Init ignored in ${s.runtimeType}');
      return null;
    }(),

    // ── Grounded (sitting / lying idle) ─────────────────────
    (Grounded(:final sub), CmdStandUp()) => () async {
      await sub.cancel();
      return Transitioning(
        const Command.standUp(),
        _listenTransition(const Command.standUp()),
        null,
      );
    }(),
    (Grounded(), Fault(:final reason)) => () {
      _log.fine('Fault: $reason — already grounded, safe');
      return null;
    }(),
    (Grounded(), _) => null,

    // ── Standing (idle, upright) ────────────────────────────
    (Standing(:final sub), CmdWalk(:final direction)) => () async {
      await sub.cancel();
      return Walking(_listenWalk(direction));
    }(),
    (Standing(:final sub), CmdSitDown()) => () async {
      await sub.cancel();
      return Transitioning(
        const Command.sitDown(),
        _listenTransition(const Command.sitDown()),
        null,
      );
    }(),
    (Standing(:final sub), CmdGesture(:final name)) => () async {
      if (_brain.gestureLibrary?.contains(name) != true) {
        _log.warning('Unknown gesture: $name — ignored');
        return null;
      }
      await sub.cancel();
      return Transitioning(
        Command.gesture(name),
        _listenTransition(Command.gesture(name)),
        null,
      );
    }(),
    (Standing(), CmdStandUp()) => null, // 已站立
    (Standing(), Fault(:final reason)) => () {
      _log.fine('Fault: $reason — already standing, safe');
      return null;
    }(),
    (Standing(), _) => null,

    // ── Walking (active control) ────────────────────────────
    (Walking(), CmdWalk(:final direction)) => () {
      _brain.walk.direction = direction;
      return null; // 仅更新方向，不切换状态
    }(),
    (Walking(:final sub), CmdIdle()) => () async {
      _log.fine('Idle — Walking → StandUp');
      await sub.cancel();
      return Transitioning(
        const Command.standUp(),
        _listenTransition(const Command.standUp()),
        null,
      );
    }(),
    (Walking(:final sub), CmdStandUp()) => () async {
      await sub.cancel();
      return Transitioning(
        const Command.standUp(),
        _listenTransition(const Command.standUp()),
        null,
      );
    }(),
    (Walking(:final sub), CmdSitDown()) => () async {
      await sub.cancel();
      // 复合：先站稳再坐下
      return Transitioning(
        const Command.standUp(),
        _listenTransition(const Command.standUp()),
        const A.sitDown(),
      );
    }(),
    (Walking(:final sub), Fault(:final reason)) => () async {
      _log.warning('Fault: $reason — Walking → StandUp');
      await sub.cancel();
      return Transitioning(
        const Command.standUp(),
        _listenTransition(const Command.standUp()),
        null,
      );
    }(),
    (Walking(), _) => null,

    // ── Transitioning (protected) ───────────────────────────
    (Transitioning(:final target), CmdStandUp() || CmdSitDown() || CmdWalk() || CmdIdle()) => () {
      _log.warning('${a.runtimeType} rejected: transition in progress (${target.runtimeType})');
      return null;
    }(),

    // StandUp 完成，无 pending → Standing
    (
      Transitioning(target: StandUpCommand(), :final sub, pending: null),
      Done(),
    ) => () async {
      await sub.cancel();
      return Standing(_listenIdle());
    }(),

    // StandUp 完成，pending SitDown → 继续坐下
    (
      Transitioning(target: StandUpCommand(), :final sub, pending: CmdSitDown()),
      Done(),
    ) => () async {
      await sub.cancel();
      return Transitioning(
        const Command.sitDown(),
        _listenTransition(const Command.sitDown()),
        null,
      );
    }(),

    // Gesture 完成 → Standing
    (
      Transitioning(target: GestureCommand(), :final sub),
      Done(),
    ) => () async {
      await sub.cancel();
      return Standing(_listenIdle());
    }(),

    // SitDown 完成 → Grounded
    (
      Transitioning(target: SitDownCommand(), :final sub),
      Done(),
    ) => () async {
      await sub.cancel();
      return Grounded(_listenIdle());
    }(),

    // StandUp 途中故障 → 中止，改为坐下
    (
      Transitioning(target: StandUpCommand(), :final sub),
      Fault(:final reason),
    ) => () async {
      _log.warning('Fault: $reason — StandUp aborted → SitDown');
      await sub.cancel();
      return Transitioning(
        const Command.sitDown(),
        _listenTransition(const Command.sitDown()),
        null,
      );
    }(),

    // SitDown 途中故障 → 强制接受 Grounded（避免死循环）
    (
      Transitioning(target: SitDownCommand(), :final sub),
      Fault(:final reason),
    ) => () async {
      _log.warning('Fault: $reason — SitDown aborted → forced Grounded');
      await sub.cancel();
      return Grounded(_listenIdle());
    }(),

    // Gesture 途中故障 → 安全回到 Standing
    (
      Transitioning(target: GestureCommand(), :final sub),
      Fault(:final reason),
    ) => () async {
      _log.warning('Fault: $reason — Gesture aborted → Standing');
      await sub.cancel();
      return Standing(_listenIdle());
    }(),

    (Transitioning(), _) => null,
  };
}
