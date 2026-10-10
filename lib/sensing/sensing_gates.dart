import 'dart:math' as math;

import '../core/contracts.dart' show StepEvent;
import '../core/tuning.dart' as tuning;
import 'motion_state.dart';
import 'placement.dart';
import 'raw_events.dart';
import 'state_events.dart';
import 'step_detector.dart' as fallback;
import 'turn_detector.dart' as rotation;
import 'walking_bout.dart';

/// Standalone future adapter; deliberately NOT connected to SensingSource.
/// Input: existing raw auxiliary events, hardware steps, or primitive motion.
/// Output: StepEvent/TurnEvent and local state-change events only.
/// Supplying accel opts into the existing fallback detector; hardware users omit it.
class SensingGates {
  SensingGates({
    bool useBoutGating = tuning.useBoutGating,
    this.useHandlingGate = tuning.useHandlingGate,
    bool usePlacement = tuning.usePlacement,
    int boutMinSteps = tuning.boutMinSteps,
    int boutMinGapMs = tuning.boutMinGapMs,
    int boutMaxGapMs = tuning.boutMaxGapMs,
    double handlingGravityDeg = tuning.handlingGravityDeg,
    int handlingWindowMs = tuning.handlingWindowMs,
    int handlingHoldMs = tuning.handlingHoldMs,
    double pocketLuxMax = tuning.pocketLuxMax,
    int pocketHoldMs = tuning.pocketHoldMs,
  }) : _bouts = WalkingBoutGate(
         useBoutGating: useBoutGating,
         boutMinSteps: boutMinSteps,
         boutMinGapMs: boutMinGapMs,
         boutMaxGapMs: boutMaxGapMs,
       ),
       _motion = MotionStateDetector(
         handlingGravityDeg: handlingGravityDeg,
         handlingWindowMs: handlingWindowMs,
         handlingHoldMs: handlingHoldMs,
       ),
       _placement = PlacementDetector(
         usePlacement: usePlacement,
         pocketLuxMax: pocketLuxMax,
         pocketHoldMs: pocketHoldMs,
       );

  final bool useHandlingGate;
  final WalkingBoutGate _bouts;
  final MotionStateDetector _motion;
  final PlacementDetector _placement;
  rotation.TurnDetector _turns = rotation.TurnDetector();
  fallback.StepDetector _steps = fallback.StepDetector();
  bool _handling = false;
  int _clock = -1;
  MotionState get motionState => _motion.state;
  Placement get placement => _placement.placement;

  List<Object> onRaw(RawSensingEvent input) {
    if (input.t != null && input.t! < 0) return const [];
    final events = <Object>[];
    _before(input.t ?? math.max(0, _clock), events);
    if (input is GravitySample) {
      _add(_motion.onGravity(input, inWalkingBout: _bouts.inBout), events);
      _syncHandling();
      _add(_placement.advanceTo(_clock), events);
    } else if (input is ProximitySample) {
      _add(_placement.onProximity(input), events);
    } else if (input is LightSample) {
      _add(_placement.onLight(input), events);
    } else if (input is DeviceInfo) {
      _add(_placement.onDeviceInfo(input), events);
    }
    return events;
  }

  List<Object> onStep(StepEvent step) {
    if (step.t < 0) return const [];
    final events = <Object>[];
    _before(step.t, events);
    _add(_placement.advanceTo(_clock), events);
    _acceptStep(step, events);
    return events;
  }

  List<Object> onMotion(int tMs, double yawRate, {double? accel}) {
    if (tMs < 0) return const [];
    final events = <Object>[];
    _before(tMs, events);
    _add(_placement.advanceTo(_clock), events);
    if (_handling) return events;
    if (accel != null) {
      final step = _steps.onMotion(tMs, accel);
      if (step != null) _acceptStep(step, events);
    }
    _add(_turns.onMotion(tMs, yawRate), events);
    return events;
  }

  List<Object> advanceTo(int tMs) {
    if (tMs < 0 || tMs < _clock) return const [];
    final events = <Object>[];
    _before(tMs, events);
    _add(_placement.advanceTo(_clock), events);
    return events;
  }

  void _before(int tMs, List<Object> events) {
    _clock = math.max(_clock, tMs);
    _bouts.advanceTo(_clock);
    _add(_motion.advanceTo(_clock, inWalkingBout: _bouts.inBout), events);
    _syncHandling();
  }

  void _syncHandling() {
    final now = useHandlingGate && _motion.state == MotionState.handling;
    if (now == _handling) return;
    _handling = now;
    // Discard partial integration on entry and seed a fresh timestamp on exit.
    _turns = rotation.TurnDetector();
    _steps = fallback.StepDetector();
    if (now) _bouts.reset();
  }

  void _acceptStep(StepEvent step, List<Object> events) {
    if (_handling) return;
    events.addAll(_bouts.onStep(step));
    _add(_motion.advanceTo(_clock, inWalkingBout: _bouts.inBout), events);
  }

  void _add(Object? event, List<Object> output) {
    if (event != null) output.add(event);
  }
}
