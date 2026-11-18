import 'dart:async';

import 'package:cms/cms.dart';
import 'package:logging/logging.dart';
import 'package:thunder_brain/src/brain.dart';
import 'package:thunder_brain/src/common.dart';
import 'package:thunder_brain/src/gesture.dart';
import 'package:vector_math/vector_math.dart';

import 's.dart';
import 'a.dart';

export 's.dart';
export 'a.dart';

final _log = Logger('thunder_brain.cms');

class M extends Cms<S, A> {
  final Brain _brain;
  bool _closing = false;
  int _commandVersion = 0;

  int get commandVersion => _commandVersion;

  @override
  void add(A event) {
    if (_closing) return;
    _commandVersion++;
    super.add(event);
  }

  bool profileSwitchInProgress = false;
  bool _handlingEvent = false;
  S? _pendingState;

  /// Grounded is either the boot lie-down pose or the official sitting pose.
  /// Standing and Walking are standing; this field is only read while grounded.
  GesturePose groundedPose = GesturePose.lying;

  bool get isHandlingEvent =>
      _closing ||
      _handlingEvent ||
      (_pendingState != null && !identical(state, _pendingState));

  // Cancellation is asynchronous. Concurrent handlers can all observe the same
  // old state and create subscriptions which the final state can no longer cancel.
  M(this._brain)
    : super(const Zero(), (events, mapper) => events.asyncExpand(mapper));

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
        Future.microtask(() => add(A.fault('Idle stream closed unexpectedly')));
      },
    );
  }

  /// 监听过渡行为（有限流：StandUp、SitDown 或 Gesture）。
  /// 行为完成时触发 [Done]。
  StreamSubscription<History> _listenTransition(Command target) {
    final Stream<History> stream;
    try {
      stream = switch (target) {
        StandUpCommand() => _brain.standUp.doing,
        SitDownCommand() => _brain.sitDown.doing,
        GestureCommand(:final name) =>
          _brain.createGesture(name)?.doing ??
              (throw StateError('Unknown gesture: $name')),
        _ => throw StateError('Invalid transition target: $target'),
      };
    } catch (e, st) {
      _log.severe(
        'Failed to create transition stream for ${target.runtimeType}',
        e,
        st,
      );
      Future.microtask(() => add(A.fault('Transition setup error: $e')));
      return const Stream<History>.empty().listen((_) {});
    }
    // 用 late 捕获订阅引用，onError 时取消订阅防止 onDone 竞态。
    // 竞态场景：流 emit error → 排队 Fault → 流 emit done → 排队 Done
    // → Fault 触发新 transition → 旧 Done 误完成新 transition。
    late final StreamSubscription<History> sub;
    var faulted = false;
    sub = stream.listen(
      _brain.memory.add,
      onError: (Object error, StackTrace st) {
        faulted = true;
        _log.severe(
          'Transition(${target.runtimeType}) stream error',
          error,
          st,
        );
        sub.cancel(); // 阻止后续 onDone
        Future.microtask(() => add(A.fault('Transition error: $error')));
      },
      onDone: () {
        if (faulted) return; // 已经 fault 了，忽略 stale Done
        Future.microtask(() => add(const A.done()));
      },
    );
    return sub;
  }

  /// 监听行走行为（由时钟驱动的无限流）。
  /// 正常运行时 onDone 不应触发；若触发说明时钟流中断，强制触发 Fault 保持 FSM 一致性。
  StreamSubscription<History> _listenWalk(
    Vector3 direction, {
    bool forceWheelStop = false,
  }) {
    final Stream<History> stream;
    try {
      _brain.walk.forceWheelStop = forceWheelStop;
      stream = _brain.walk.doing(direction);
    } catch (e, st) {
      _log.severe('Failed to create walk stream', e, st);
      Future.microtask(() => add(A.fault('Walk setup error: $e')));
      return const Stream<History>.empty().listen((_) {});
    }
    return stream.listen(
      _brain.memory.add,
      onError: (Object error, StackTrace st) {
        _log.severe('Walk stream error', error, st);
        Future.microtask(() => add(A.fault('Walk error: $error')));
      },
      onDone: () {
        _log.severe('Walk stream closed unexpectedly — clock interrupted?');
        Future.microtask(() => add(A.fault('Walk stream closed unexpectedly')));
      },
    );
  }

  @override
  Future<void> close() async {
    _closing = true;
    _commandVersion++;
    await super.close();
    await _cancelState(state);
  }

  Future<void> _cancelState(S s) async {
    switch (s) {
      case Grounded(:final sub):
      case Standing(:final sub):
      case Walking(:final sub):
      case Transitioning(:final sub):
        await sub.cancel();
      case Zero():
        break;
    }
  }

  @override
  Future<S?> kernel(S s, A a) async {
    if (_closing) return null;
    // Also reject queued/remote motion while the standing model is loading.
    if (profileSwitchInProgress &&
        (a is CmdWalk || a is CmdStandUp || a is CmdGesture)) {
      _log.warning('${a.runtimeType} ignored during profile switch');
      return null;
    }
    _handlingEvent = true;
    S? next;
    try {
      next = await _kernelImpl(s, a);
      _pendingState = next; // Stay busy until CMS publishes the returned state.
    } finally {
      _handlingEvent = false;
    }
    if (_closing) {
      if (next != null) await _cancelState(next);
      return null;
    }
    if (next != null) {
      _log.info(
        'FSM ${s.runtimeType} + ${a.runtimeType} → ${next.runtimeType}',
      );
    }
    return next;
  }

  Future<S?> _kernelImpl(S s, A a) async => switch ((s, a)) {
    // ── Zero ────────────────────────────────────────────────
    (Zero(), Init()) => () {
      groundedPose = GesturePose.lying;
      return Grounded(_listenIdle());
    }(),
    (Zero(), _) => () {
      _log.warning(
        '${a.runtimeType} ignored: FSM not initialized (call Init first)',
      );
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
    (Grounded(:final sub), CmdGesture(:final name)) => () async {
      final definition = _brain.gestureLibrary?.get(name);
      if (definition == null) {
        _log.warning('Unknown gesture: $name — ignored');
        return null;
      }
      if (definition.startPose == GesturePose.standing) {
        if (libraryStandClipNames.contains(name)) {
          _log.warning(
            'Refusing to stand with library clip "$name"; '
            'use official StandUp',
          );
          return null;
        }
        _log.info('Official StandUp before gesture "$name"');
        await sub.cancel();
        return Transitioning(
          const Command.standUp(),
          _listenTransition(const Command.standUp()),
          A.gesture(name),
        );
      }
      if (definition.startPose != groundedPose) {
        _log.warning(
          'Gesture "$name" requires ${definition.startPose.name} '
          'but grounded pose is ${groundedPose.name}',
        );
        return null;
      }
      await sub.cancel();
      return Transitioning(
        Command.gesture(name),
        _listenTransition(Command.gesture(name)),
        null,
      );
    }(),
    (Grounded(), _) => null,

    // ── Standing (idle, upright) ────────────────────────────
    (Standing(:final sub), CmdWalk(:final direction, :final forceWheelStop)) =>
      () async {
        await sub.cancel();
        return Walking(_listenWalk(direction, forceWheelStop: forceWheelStop));
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
      final definition = _brain.gestureLibrary?.get(name);
      if (definition == null) {
        _log.warning('Unknown gesture: $name — ignored');
        return null;
      }
      if (definition.startPose != GesturePose.standing) {
        _log.warning(
          'Gesture "$name" requires ${definition.startPose.name}; '
          'robot is standing',
        );
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
    (Walking(), CmdWalk(:final direction, :final forceWheelStop)) => () {
      _brain.walk.direction = direction;
      _brain.walk.forceWheelStop = forceWheelStop;
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
    (Transitioning(target: StandUpCommand(), :final sub), CmdSitDown()) =>
      () async {
        _log.info('SitDown interrupts StandUp transition');
        await sub.cancel();
        return Transitioning(
          const Command.sitDown(),
          _listenTransition(const Command.sitDown()),
          null,
        );
      }(),
    (
      Transitioning(:final target),
      CmdStandUp() || CmdSitDown() || CmdWalk() || CmdIdle(),
    ) =>
      () {
        _log.warning(
          '${a.runtimeType} rejected: transition in progress (${target.runtimeType})',
        );
        return null;
      }(),

    // StandUp 完成，无 pending → Standing
    (
      Transitioning(target: StandUpCommand(), :final sub, pending: null),
      Done(),
    ) =>
      () async {
        await sub.cancel();
        return Standing(_listenIdle());
      }(),

    // StandUp 完成，pending SitDown → 继续坐下
    (
      Transitioning(
        target: StandUpCommand(),
        :final sub,
        pending: CmdSitDown(),
      ),
      Done(),
    ) =>
      () async {
        await sub.cancel();
        return Transitioning(
          const Command.sitDown(),
          _listenTransition(const Command.sitDown()),
          null,
        );
      }(),

    // Official StandUp finished; play the clip that was waiting.
    // The pending name is the requested clip, never wake_stand/stand_up
    // substituted in as the stand itself.
    (
      Transitioning(
        target: StandUpCommand(),
        :final sub,
        pending: CmdGesture(:final name),
      ),
      Done(),
    ) =>
      () async {
        await sub.cancel();
        if (libraryStandClipNames.contains(name)) {
          _log.warning(
            'Dropping pending library stand clip "$name" after official StandUp',
          );
          return Standing(_listenIdle());
        }
        if (_brain.gestureLibrary?.contains(name) != true) {
          _log.warning('Pending gesture "$name" missing after StandUp');
          return Standing(_listenIdle());
        }
        return Transitioning(
          Command.gesture(name),
          _listenTransition(Command.gesture(name)),
          null,
        );
      }(),

    // Gesture 完成 → 停在该动作的 end_pose。
    (Transitioning(target: GestureCommand(:final name), :final sub), Done()) =>
      () async {
        await sub.cancel();
        final end =
            _brain.gestureLibrary?.get(name)?.endPose ?? GesturePose.standing;
        if (end == GesturePose.standing) {
          return Standing(_listenIdle());
        }
        groundedPose = end;
        return Grounded(_listenIdle());
      }(),

    // SitDown 完成 → Grounded（官方坐姿）
    (Transitioning(target: SitDownCommand(), :final sub), Done()) => () async {
      await sub.cancel();
      groundedPose = GesturePose.sitting;
      return Grounded(_listenIdle());
    }(),

    // StandUp 途中故障 → 中止，改为坐下
    (
      Transitioning(target: StandUpCommand(), :final sub),
      Fault(:final reason),
    ) =>
      () async {
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
    ) =>
      () async {
        _log.warning('Fault: $reason — SitDown aborted → forced Grounded');
        await sub.cancel();
        return Grounded(_listenIdle());
      }(),

    // Gesture 途中故障 → 安全回到 Standing
    (
      Transitioning(target: GestureCommand(), :final sub),
      Fault(:final reason),
    ) =>
      () async {
        _log.warning('Fault: $reason — Gesture aborted → Standing');
        await sub.cancel();
        return Standing(_listenIdle());
      }(),

    (Transitioning(), _) => null,
  };
}
