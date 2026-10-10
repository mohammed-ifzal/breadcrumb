/// Passes on only turns that walking confirms (D29), following the TurnConfirmer
/// rules in docs/CONTRACTS.md. Pure Dart.
library;

import 'dart:async';

import 'contracts.dart';
import 'tuning.dart';

/// A raw turn is a candidate until [confirmSteps] steps follow it within
/// [windowMs]; then its net angle (every candidate since the last confirmed
/// heading added up) is emitted on [confirmed], if it is at least [minAngle].
/// Candidates during [MotionState.handling], or with no steps in the window, are
/// dropped.
class StepTurnConfirmer implements TurnConfirmer {
  StepTurnConfirmer({
    this.confirmSteps = turnConfirmSteps,
    this.windowMs = turnConfirmWindowMs,
    this.minAngle = turnMinAngle,
  });

  final int confirmSteps;
  final int windowMs;
  final double minAngle;

  final _confirmed = StreamController<TurnEvent>.broadcast(sync: true);
  MotionState _state = MotionState.walking;

  /// Net angle of the waiting candidates.
  double _net = 0;

  /// Time of the first and the latest waiting candidate; null when none waits.
  int? _since;
  int? _lastT;

  /// Steps since the latest candidate.
  int _steps = 0;

  @override
  Stream<TurnEvent> get confirmed => _confirmed.stream;

  /// True while a candidate waits for its confirming steps.
  bool get pending => _lastT != null;

  /// Time of the first waiting candidate, or null.
  int? get pendingSince => _since;

  @override
  void onTurn(TurnEvent e) {
    _expire(e.t);
    if (_state == MotionState.handling) return;
    _net += e.angle;
    _since ??= e.t;
    _lastT = e.t;
    _steps = 0;
  }

  @override
  void onStep(StepEvent e) {
    _expire(e.t);
    final last = _lastT;
    if (last == null) return;
    if (++_steps < confirmSteps) return;
    final net = _net;
    _drop();
    if (net.abs() >= minAngle) _confirmed.add(TurnEvent(last, net));
  }

  @override
  void onMotionState(MotionStateEvent e) {
    _state = e.state;
    if (e.state == MotionState.handling) _drop();
  }

  /// Drops a waiting candidate, if any.
  void dropPending() => _drop();

  void _expire(int t) {
    final last = _lastT;
    if (last != null && t - last > windowMs) _drop();
  }

  void _drop() {
    _net = 0;
    _since = null;
    _lastT = null;
    _steps = 0;
  }
}

/// Runs a sensing event stream through a [StepTurnConfirmer] and keeps it in
/// order: the steps that follow a candidate are held, then come after the
/// confirmed turn (or alone, when it is dropped). So the Tracker and the
/// MapBuilder see the turn where it happened, not [turnConfirmSteps] late.
/// [MotionStateEvent]s go to the confirmer and are passed on; anything else is
/// passed on unchanged.
class ConfirmedEvents {
  ConfirmedEvents([StepTurnConfirmer? confirmer])
    : confirmer = confirmer ?? StepTurnConfirmer() {
    this.confirmer.confirmed.listen(_turns.add);
  }

  final StepTurnConfirmer confirmer;
  final _turns = <TurnEvent>[];
  final _held = <StepEvent>[];

  /// The events to pass on now, in order, for one incoming [event].
  List<Object> add(Object event) {
    final out = <Object>[];
    switch (event) {
      case TurnEvent():
        final since = confirmer.pendingSince;
        confirmer.onTurn(event);
        // The waiting candidate expired: its held steps go first.
        if (since != null && confirmer.pendingSince != since) out.addAll(_release());
      case StepEvent():
        if (!confirmer.pending) {
          out.add(event);
        } else {
          confirmer.onStep(event);
          _held.add(event);
          if (!confirmer.pending) out.addAll(_release());
        }
      case MotionStateEvent():
        confirmer.onMotionState(event);
        if (!confirmer.pending) out.addAll(_release());
        out.add(event);
      default:
        out.add(event);
    }
    return out;
  }

  /// At the end of the stream: a waiting candidate is dropped, its steps pass.
  List<Object> close() {
    confirmer.dropPending();
    return _release();
  }

  List<Object> _release() {
    final out = <Object>[..._turns, ..._held];
    _turns.clear();
    _held.clear();
    return out;
  }
}

/// [source]'s events and motion states through a fresh [ConfirmedEvents]
/// (D29). A broadcast stream, like `SensingSource.events()`; it ends when
/// `events()` ends.
Stream<Object> confirmedEvents(SensingSource source, [StepTurnConfirmer? confirmer]) {
  late final StreamController<Object> controller;
  final subs = <StreamSubscription<Object>>[];
  ConfirmedEvents? pipe;
  void push(Object e) {
    for (final out in pipe!.add(e)) {
      controller.add(out);
    }
  }

  controller = StreamController<Object>.broadcast(
    onListen: () {
      pipe = ConfirmedEvents(confirmer ?? StepTurnConfirmer());
      subs
        ..add(
          source.events().listen(
            push,
            onError: controller.addError,
            // The walk is over: a waiting candidate is dropped, its steps pass.
            onDone: () {
              pipe!.close().forEach(controller.add);
              controller.close();
            },
          ),
        )
        ..add(source.motionStates().listen(push, onError: controller.addError));
    },
    onCancel: () {
      for (final s in subs) {
        s.cancel();
      }
      subs.clear();
    },
  );
  return controller.stream;
}
