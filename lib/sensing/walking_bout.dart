import '../core/contracts.dart';
import '../core/tuning.dart' as tuning;

/// Confirms cadence before releasing original step objects/timestamps.
/// Too-close samples are rejected, not used as the next cadence baseline.
class WalkingBoutGate {
  WalkingBoutGate({
    this.useBoutGating = tuning.useBoutGating,
    this.boutMinSteps = tuning.boutMinSteps,
    this.boutMinGapMs = tuning.boutMinGapMs,
    this.boutMaxGapMs = tuning.boutMaxGapMs,
  }) {
    if (boutMinSteps < 1 || boutMinGapMs <= 0 || boutMaxGapMs < boutMinGapMs) {
      throw ArgumentError('Invalid walking bout cadence or minimum count');
    }
  }
  final bool useBoutGating;
  final int boutMinSteps, boutMinGapMs, boutMaxGapMs;
  final _pending = <StepEvent>[];
  int? _lastCandidateT, _lastSeenT;
  bool _inBout = false;
  bool get inBout => _inBout;

  List<StepEvent> onStep(StepEvent event) {
    if (event.t < 0) return const [];
    if (!useBoutGating) {
      if (_lastCandidateT == null || event.t > _lastCandidateT!) {
        _lastCandidateT = event.t;
      }
      _inBout = true;
      return [event];
    }
    if (_lastSeenT != null && event.t <= _lastSeenT!) return const [];
    _lastSeenT = event.t;
    final previous = _lastCandidateT;
    if (previous != null) {
      final gap = event.t - previous;
      if (gap < boutMinGapMs) return const [];
      if (gap > boutMaxGapMs) {
        _pending.clear();
        _inBout = false;
      }
    }
    _lastCandidateT = event.t;
    if (_inBout) return [event];
    _pending.add(event);
    if (_pending.length < boutMinSteps) return const [];
    _inBout = true;
    final confirmed = List<StepEvent>.unmodifiable(_pending);
    _pending.clear();
    return confirmed;
  }

  /// State expiration only; never flushes unconfirmed steps.
  void advanceTo(int tMs) {
    final last = _lastCandidateT;
    if (last != null && tMs - last > boutMaxGapMs) {
      _pending.clear();
      _inBout = false;
    }
  }

  void reset() {
    _pending.clear();
    _lastCandidateT = null;
    _lastSeenT = null;
    _inBout = false;
  }
}
