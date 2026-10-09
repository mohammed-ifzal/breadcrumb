import '../core/contracts.dart' as contracts;
import '../core/tuning.dart' as tuning;

/// Integrates qualifying yaw samples, then emits the full angle after settling.
class TurnDetector implements contracts.TurnDetector {
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
    if (yawRate.abs() > tuning.turnRateMin) {
      // Each sample describes the interval since the preceding sample. Milliseconds
      // become seconds here; 1000 is a unit conversion, not a tuning threshold.
      _angle += yawRate * (t - previousT) / 1000;
      _settleStart = null;
    } else {
      _settleStart ??= t;
      if (t - _settleStart! >= tuning.turnSettleMs) {
        final angle = _angle;
        _angle = 0;
        _settleStart = null;
        if (angle.abs() >= tuning.turnMinAngle) {
          return contracts.TurnEvent(t, angle);
        }
      }
    }
    return null;
  }
}
