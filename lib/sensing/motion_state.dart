import 'dart:collection';
import 'dart:math' as math;

import '../core/tuning.dart' as tuning;
import 'raw_events.dart';
import 'state_events.dart';

class _GravityPoint {
  const _GravityPoint(this.t, this.x, this.y, this.z);
  final int t;
  final double x, y, z;
}

/// UI state classifier independent of the handling gate's enabled flag.
/// Exceeding the angle enters handling immediately and refreshes the hold.
class MotionStateDetector {
  MotionStateDetector({
    this.handlingGravityDeg = tuning.handlingGravityDeg,
    this.handlingWindowMs = tuning.handlingWindowMs,
    this.handlingHoldMs = tuning.handlingHoldMs,
  }) {
    if (!handlingGravityDeg.isFinite ||
        handlingGravityDeg <= 0 ||
        handlingGravityDeg > 180 ||
        handlingWindowMs <= 0 ||
        handlingHoldMs < 0) {
      throw ArgumentError(
        'Invalid gravity angle, observation window or handling hold',
      );
    }
  }
  final double handlingGravityDeg;
  final int handlingWindowMs, handlingHoldMs;
  final _history = Queue<_GravityPoint>();
  int? _lastGravityT, _handlingUntil;
  String? _lastSource;
  int _clock = -1;
  MotionState _state = MotionState.still;
  MotionState get state => _state;

  MotionStateEvent? onGravity(
    GravitySample sample, {
    bool inWalkingBout = false,
  }) {
    if (sample.t < 0 ||
        (_lastGravityT != null && sample.t <= _lastGravityT!) ||
        !sample.x.isFinite ||
        !sample.y.isFinite ||
        !sample.z.isFinite) {
      return null;
    }
    final norm = math.sqrt(
      sample.x * sample.x + sample.y * sample.y + sample.z * sample.z,
    );
    if (!norm.isFinite || norm == 0) return null;
    final previousT = _lastGravityT;
    if ((previousT != null && sample.t - previousT > tuning.maxMotionGapMs) ||
        (_lastSource != null && sample.source != _lastSource)) {
      _history.clear();
    }
    _lastGravityT = sample.t;
    _lastSource = sample.source;
    final point = _GravityPoint(
      sample.t,
      sample.x / norm,
      sample.y / norm,
      sample.z / norm,
    );
    while (_history.isNotEmpty &&
        _history.first.t < sample.t - handlingWindowMs) {
      _history.removeFirst();
    }
    for (final previous in _history) {
      final dot =
          (previous.x * point.x + previous.y * point.y + previous.z * point.z)
              .clamp(-1.0, 1.0);
      final angle = math.acos(dot) * 180 / math.pi;
      if (angle > handlingGravityDeg) {
        _handlingUntil = sample.t + handlingHoldMs;
        break;
      }
    }
    _history.add(point);
    return advanceTo(math.max(_clock, sample.t), inWalkingBout: inWalkingBout);
  }

  MotionStateEvent? advanceTo(int tMs, {bool inWalkingBout = false}) {
    if (tMs < 0 || tMs < _clock) return null;
    _clock = tMs;
    final until = _handlingUntil;
    final next = until != null && tMs < until
        ? MotionState.handling
        : inWalkingBout
        ? MotionState.walking
        : MotionState.still;
    if (next == _state) return null;
    _state = next;
    return MotionStateEvent(next, tMs);
  }
}
