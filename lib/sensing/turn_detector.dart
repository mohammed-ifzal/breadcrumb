import '../core/contracts.dart' as contracts;
import '../core/tuning.dart' as tuning;
import 'raw_events.dart';

/// Integrates qualifying yaw samples, then emits the full angle after settling.
class TurnDetector implements contracts.TurnDetector {
  /// Overrides are for replay experiments; production defaults stay in tuning.
  /// [onSettled] audits candidates including those below the minimum angle.
  TurnDetector({
    double turnRateMin = tuning.turnRateMin,
    int turnSettleMs = tuning.turnSettleMs,
    this.usePocketTurnProfile = tuning.usePocketTurnProfile,
    double pocketTurnRateMin = tuning.pocketTurnRateMin,
    int pocketTurnSettleMs = tuning.pocketTurnSettleMs,
    this.onSettled,
  }) : _rateMin = turnRateMin,
       _settleMs = turnSettleMs,
       _pocketRateMin = pocketTurnRateMin,
       _pocketSettleMs = pocketTurnSettleMs {
    if (!turnRateMin.isFinite || turnRateMin < 0) {
      throw ArgumentError.value(
        turnRateMin,
        'turnRateMin',
        'Must be finite and non-negative',
      );
    }
    if (!pocketTurnRateMin.isFinite || pocketTurnRateMin < 0) {
      throw ArgumentError.value(pocketTurnRateMin, 'pocketTurnRateMin');
    }
    if (pocketTurnSettleMs < 0) {
      throw ArgumentError.value(pocketTurnSettleMs, 'pocketTurnSettleMs');
    }
    if (turnSettleMs < 0) {
      throw ArgumentError.value(
        turnSettleMs,
        'turnSettleMs',
        'Must be non-negative',
      );
    }
  }
  final bool usePocketTurnProfile;
  final double _pocketRateMin;
  final int _pocketSettleMs;
  bool _near = false;

  /// Raw proximity/capability input shared by live sensing and trace replay.
  /// Unknown/unavailable uses normal thresholds. Changing the profile never
  /// resets angle, previous motion timestamp or an in-progress settle interval.
  void onRaw(RawSensingEvent event) {
    if (!usePocketTurnProfile) return;
    if (event is ProximitySample &&
        event.t >= 0 &&
        event.cm.isFinite &&
        event.cm >= 0) {
      _near = event.near;
    } else if (event is DeviceInfo && event.proximityAvailable == false) {
      _near = false;
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
    final pocket = usePocketTurnProfile && _near;
    final rateMin = pocket ? _pocketRateMin : _rateMin;
    final settleMs = pocket ? _pocketSettleMs : _settleMs;
    if (yawRate.abs() > rateMin) {
      // Each sample describes the interval since the preceding sample. Milliseconds
      // become seconds here; 1000 is a unit conversion, not a tuning threshold.
      _angle += yawRate * (t - previousT) / 1000;
      _settleStart = null;
    } else {
      _settleStart ??= t;
      if (t - _settleStart! >= settleMs) {
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
