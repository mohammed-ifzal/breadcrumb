import '../core/contracts.dart' as contracts;
import '../core/tuning.dart' as tuning;

/// Integrates qualifying yaw samples, then emits the full angle after settling.
class TurnDetector implements contracts.TurnDetector {
  /// Overrides are for replay experiments; production defaults stay in tuning.
  /// [onSettled] audits candidates including those below the minimum angle.
  TurnDetector({
    double turnRateMin = tuning.turnRateMin,
    int turnSettleMs = tuning.turnSettleMs,
    this.onSettled,
  }) : _rateMin = turnRateMin,
       _settleMs = turnSettleMs {
    if (!turnRateMin.isFinite || turnRateMin < 0) {
      throw ArgumentError.value(
        turnRateMin,
        'turnRateMin',
        'Must be finite and non-negative',
      );
    }
    if (turnSettleMs < 0) {
      throw ArgumentError.value(
        turnSettleMs,
        'turnSettleMs',
        'Must be non-negative',
      );
    }
  }
  final double _rateMin;
  final int _settleMs;
  final void Function(int, double)? onSettled;
  int? _lastT;
  int? _settleStart;
  double _angle = 0;

  @override
  contracts.TurnEvent? onMotion(int t, double yawRate) {
    if (t < 0 || !yawRate.isFinite || (_lastT != null && t <= _lastT!)) {
      return null;
    }
    final previousT = _lastT;
    _lastT = t;
    if (previousT == null) return null;
    if (t - previousT > tuning.maxMotionGapMs) {
      _angle = 0;
      _settleStart = null;
      return null;
    }
    if (yawRate.abs() > _rateMin) {
      // Each sample describes the interval since the preceding sample. Milliseconds
      // become seconds here; 1000 is a unit conversion, not a tuning threshold.
      _angle += yawRate * (t - previousT) / 1000;
      _settleStart = null;
    } else {
      _settleStart ??= t;
      if (t - _settleStart! >= _settleMs) {
        final angle = _angle;
        _angle = 0;
        _settleStart = null;
        onSettled?.call(t, angle);
        if (angle.abs() >= tuning.turnMinAngle) {
          return contracts.TurnEvent(t, angle);
        }
      }
    }
    return null;
  }
}
