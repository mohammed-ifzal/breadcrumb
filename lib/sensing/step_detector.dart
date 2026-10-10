import '../core/contracts.dart' as contracts;
import '../core/tuning.dart' as tuning;

/// Acceleration peaks used only when the hardware step detector is absent.
class StepDetector implements contracts.StepDetector {
  int? _lastT;
  double? _previous;
  bool _rising = false;
  int? _peakT;
  int? _lastStepT;

  @override
  contracts.StepEvent? onMotion(int t, double accel) {
    if (t < 0 || !accel.isFinite || (_lastT != null && t <= _lastT!)) {
      return null;
    }
    if (_lastT != null && t - _lastT! > tuning.maxMotionGapMs) {
      _lastT = t;
      _previous = accel;
      _rising = false;
      _peakT = null;
      _lastStepT = null;
      return null;
    }
    final previous = _previous;
    final previousT = _lastT;
    _previous = accel;
    _lastT = t;
    if (previous == null) return null;
    if (accel > previous) {
      _rising = true;
      _peakT = t;
    } else if (accel < previous) {
      final peakT = _peakT ?? previousT!;
      final isPeak = _rising && previous >= tuning.accelPeakThreshold;
      _rising = false;
      _peakT = null;
      if (isPeak &&
          (_lastStepT == null ||
              peakT - _lastStepT! >= tuning.accelPeakMinGapMs)) {
        _lastStepT = peakT;
        return contracts.StepEvent(peakT);
      }
    }
    return null;
  }
}
