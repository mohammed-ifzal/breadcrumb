import 'dart:math' as math;

import 'package:breadcrumb/core/contracts.dart' as contracts;
import 'package:breadcrumb/core/tuning.dart' as tuning;
import 'package:breadcrumb/sensing/motion_state.dart';
import 'package:breadcrumb/sensing/placement.dart';
import 'package:breadcrumb/sensing/raw_events.dart';
import 'package:breadcrumb/sensing/sensing_gates.dart';
import 'package:breadcrumb/sensing/state_events.dart';
import 'package:breadcrumb/sensing/step_detector.dart';
import 'package:breadcrumb/sensing/turn_detector.dart';
import 'package:breadcrumb/sensing/walking_bout.dart';
import 'package:flutter_test/flutter_test.dart';

GravitySample pose(
  int t,
  double degrees, {
  double magnitude = 9.8,
  String source = 'sensor',
}) {
  final angle = degrees * math.pi / 180;
  return GravitySample(
    t,
    magnitude * math.sin(angle),
    0,
    magnitude * math.cos(angle),
    source: source,
  );
}

List<Object> flip(SensingGates gates) {
  final events = <Object>[];
  for (var t = 0; t <= 1600; t += 20) {
    events.addAll(gates.onRaw(pose(t, t <= 400 ? 60 * t / 400 : 60)));
    events.addAll(gates.onMotion(t, t > 0 && t <= 400 ? 150 : 0));
    if (t >= 400 && t % 400 == 0) {
      events.addAll(gates.onStep(contracts.StepEvent(t)));
    }
  }
  return events;
}

void main() {
  test('local state events keep exact enum values and millisecond fields', () {
    const motion = MotionStateEvent(MotionState.walking, 123);
    const placement = PlacementEvent(Placement.pocket, 456);
    expect((motion.state, motion.tMs), (MotionState.walking, 123));
    expect((placement.placement, placement.tMs), (Placement.pocket, 456));
    expect(MotionState.values, [
      MotionState.walking,
      MotionState.still,
      MotionState.handling,
    ]);
    expect(Placement.values, [
      Placement.hand,
      Placement.pocket,
      Placement.unknown,
    ]);
  });
  group('walking bouts', () {
    test('five isolated queue shuffles over twenty seconds emit no steps', () {
      final gate = WalkingBoutGate(useBoutGating: true);
      final emitted = <contracts.StepEvent>[];
      for (final t in [0, 5000, 10000, 15000, 20000]) {
        emitted.addAll(gate.onStep(contracts.StepEvent(t)));
      }
      expect(emitted, isEmpty);
      expect(gate.inBout, isFalse);
    });
    test(
      'ten normal steps all survive with first three emitted retroactively',
      () {
        final gate = WalkingBoutGate(useBoutGating: true);
        final steps = [
          for (var i = 0; i < 10; i++) contracts.StepEvent(i * 500),
        ];
        final emitted = <contracts.StepEvent>[];
        for (var i = 0; i < steps.length; i++) {
          final batch = gate.onStep(steps[i]);
          if (i < 2) expect(batch, isEmpty);
          if (i == 2) expect(batch, steps.take(3).toList());
          if (i > 2) expect(batch, [steps[i]]);
          emitted.addAll(batch);
        }
        expect(emitted, steps);
        expect(gate.inBout, isTrue);
        gate.advanceTo(4500 + tuning.boutMaxGapMs);
        expect(gate.inBout, isTrue);
        gate.advanceTo(4500 + tuning.boutMaxGapMs + 1);
        expect(gate.inBout, isFalse);
      },
    );
    for (final gap in [250, 333, 400, 1500]) {
      test('inclusive valid cadence $gap ms drops no steps', () {
        final gate = WalkingBoutGate(useBoutGating: true);
        final emitted = <contracts.StepEvent>[];
        for (var i = 0; i < 10; i++) {
          emitted.addAll(gate.onStep(contracts.StepEvent(i * gap)));
        }
        expect(emitted.map((e) => e.t), [for (var i = 0; i < 10; i++) i * gap]);
      });
    }
    test('too-fast duplicates and stale candidates cannot confirm a bout', () {
      final gate = WalkingBoutGate(useBoutGating: true);
      expect(gate.onStep(const contracts.StepEvent(0)), isEmpty);
      expect(gate.onStep(const contracts.StepEvent(100)), isEmpty);
      expect(gate.onStep(const contracts.StepEvent(100)), isEmpty);
      expect(gate.onStep(const contracts.StepEvent(-1)), isEmpty);
      expect(gate.onStep(const contracts.StepEvent(250)), isEmpty);
      gate.advanceTo(2000);
      expect(gate.onStep(const contracts.StepEvent(2000)), isEmpty);
      expect(gate.inBout, isFalse);
    });
    test('reset discards pending candidates and a confirmed bout', () {
      final gate = WalkingBoutGate(useBoutGating: true);
      gate.onStep(const contracts.StepEvent(0));
      gate.onStep(const contracts.StepEvent(500));
      gate.reset();
      expect(gate.onStep(const contracts.StepEvent(1000)), isEmpty);
      gate.onStep(const contracts.StepEvent(1500));
      expect(gate.onStep(const contracts.StepEvent(2000)), hasLength(3));
      gate.reset();
      expect(gate.inBout, isFalse);
    });
    test(
      'useBoutGating off passes isolated fast and delayed hardware steps',
      () {
        final gate = WalkingBoutGate(useBoutGating: false);
        for (final t in [0, 100, 50, 5000, 20000]) {
          final step = contracts.StepEvent(t);
          expect(gate.onStep(step), [step]);
        }
      },
    );
    test('invalid bout parameters fail clearly', () {
      expect(() => WalkingBoutGate(boutMinSteps: 0), throwsArgumentError);
      expect(() => WalkingBoutGate(boutMinGapMs: 0), throwsArgumentError);
      expect(
        () => WalkingBoutGate(boutMinGapMs: 1501, boutMaxGapMs: 1500),
        throwsArgumentError,
      );
    });
  });
  group('motion state and handling', () {
    test('sixty-degree flip in 400 ms immediately enters handling', () {
      final detector = MotionStateDetector();
      final events = <MotionStateEvent>[];
      for (var t = 0; t <= 400; t += 20) {
        final event = detector.onGravity(pose(t, 60 * t / 400));
        if (event != null) events.add(event);
      }
      expect(detector.state, MotionState.handling);
      expect(events, hasLength(1));
      expect(events.single.tMs, lessThanOrEqualTo(400));
      expect(events.single.state, MotionState.handling);
    });
    test('ten-degree tilt over two seconds never enters handling', () {
      final detector = MotionStateDetector();
      for (var t = 0; t <= 2000; t += 20) {
        expect(detector.onGravity(pose(t, 10 * t / 2000)), isNull);
      }
      expect(detector.state, MotionState.still);
    });
    test('handling takes precedence and holds after the last crossing', () {
      final detector = MotionStateDetector();
      detector.onGravity(pose(0, 0), inWalkingBout: true);
      final entry = detector.onGravity(pose(200, 60), inWalkingBout: true)!;
      expect(entry.state, MotionState.handling);
      expect(detector.advanceTo(1399, inWalkingBout: true), isNull);
      final exit = detector.advanceTo(1400, inWalkingBout: true)!;
      expect((exit.state, exit.tMs), (MotionState.walking, 1400));
      expect(
        detector.advanceTo(1500, inWalkingBout: false)!.state,
        MotionState.still,
      );
    });
    test('gravity magnitude does not change its angle; gaps and source changes reset history', () {
      final detector = MotionStateDetector();
      detector.onGravity(pose(0, 0, magnitude: 2));
      expect(detector.onGravity(pose(20, 0, magnitude: 20)), isNull);
      expect(detector.onGravity(pose(40, 60, source: 'accelerometer')), isNull);
      expect(
        detector.onGravity(pose(40 + tuning.maxMotionGapMs + 1, 0)),
        isNull,
      );
      expect(detector.onGravity(const GravitySample(500, 0, 0, 0)), isNull);
      expect(
        detector.onGravity(const GravitySample(520, double.nan, 0, 1)),
        isNull,
      );
      expect(detector.state, MotionState.still);
    });
    test('invalid handling parameters fail clearly', () {
      expect(
        () => MotionStateDetector(handlingWindowMs: 0),
        throwsArgumentError,
      );
      expect(
        () => MotionStateDetector(handlingGravityDeg: double.nan),
        throwsArgumentError,
      );
      expect(
        () => MotionStateDetector(handlingGravityDeg: 181),
        throwsArgumentError,
      );
      expect(
        () => MotionStateDetector(handlingHoldMs: -1),
        throwsArgumentError,
      );
    });
    test('handling gate suppresses steps and the entire flip turn', () {
      final gates = SensingGates(
        useBoutGating: false,
        useHandlingGate: true,
        usePlacement: true,
      );
      final events = flip(gates);
      expect(
        events.whereType<MotionStateEvent>().any(
          (e) => e.state == MotionState.handling,
        ),
        isTrue,
      );
      expect(events.whereType<contracts.StepEvent>(), isEmpty);
      expect(events.whereType<contracts.TurnEvent>(), isEmpty);
    });
    test(
      'handling entry drops an unconfirmed bout and exit starts a fresh one',
      () {
        final gates = SensingGates(
          useBoutGating: true,
          useHandlingGate: true,
          usePlacement: true,
        );
        gates.onStep(const contracts.StepEvent(0));
        gates.onStep(const contracts.StepEvent(300));
        gates.onRaw(pose(300, 0));
        gates.onRaw(pose(500, 60));
        expect(
          gates
              .onStep(const contracts.StepEvent(600))
              .whereType<contracts.StepEvent>(),
          isEmpty,
        );
        gates.advanceTo(1700);
        expect(
          gates
              .onStep(const contracts.StepEvent(1800))
              .whereType<contracts.StepEvent>(),
          isEmpty,
        );
        expect(
          gates
              .onStep(const contracts.StepEvent(2200))
              .whereType<contracts.StepEvent>(),
          isEmpty,
        );
        expect(
          gates
              .onStep(const contracts.StepEvent(2600))
              .whereType<contracts.StepEvent>()
              .map((e) => e.t),
          [1800, 2200, 2600],
        );
      },
    );
    test(
      'after handling a fresh yaw baseline still yields exactly ninety degrees',
      () {
        final gates = SensingGates(
          useBoutGating: false,
          useHandlingGate: true,
          usePlacement: true,
        );
        flip(gates);
        final events = <Object>[...gates.advanceTo(3000)];
        events.addAll(gates.onMotion(3000, 0));
        for (var t = 3020; t <= 4000; t += 20) {
          events.addAll(gates.onMotion(t, 90));
        }
        for (var t = 4020; t <= 4520; t += 20) {
          events.addAll(gates.onMotion(t, 0));
        }
        expect(
          events.whereType<contracts.TurnEvent>().single.angle,
          closeTo(90, .01),
        );
      },
    );
    test(
      'useHandlingGate off retains the flip turn and all hardware steps',
      () {
        final gates = SensingGates(
          useBoutGating: false,
          useHandlingGate: false,
          usePlacement: true,
        );
        final events = flip(gates);
        expect(events.whereType<contracts.StepEvent>(), hasLength(4));
        expect(
          events.whereType<contracts.TurnEvent>().single.angle,
          closeTo(60, .01),
        );
      },
    );
    test('bout confirmation and expiration publish walking then still', () {
      final gates = SensingGates(
        useBoutGating: true,
        useHandlingGate: true,
        usePlacement: true,
      );
      gates.onStep(const contracts.StepEvent(0));
      gates.onStep(const contracts.StepEvent(500));
      final batch = gates.onStep(const contracts.StepEvent(1000));
      expect(batch.whereType<contracts.StepEvent>().map((e) => e.t), [
        0,
        500,
        1000,
      ]);
      expect(
        batch.whereType<MotionStateEvent>().single.state,
        MotionState.walking,
      );
      expect(
        gates.advanceTo(2501).whereType<MotionStateEvent>().single.state,
        MotionState.still,
      );
    });
  });
  group('placement', () {
    test('near and dark become pocket only after two continuous seconds', () {
      final detector = PlacementDetector(usePlacement: true);
      expect(detector.onProximity(const ProximitySample(0, true, 0)), isNull);
      expect(
        detector.onLight(const LightSample(0, 10))!.placement,
        Placement.hand,
      );
      expect(detector.advanceTo(2000), isNull);
      final pocket = detector.advanceTo(2001)!;
      expect((pocket.placement, pocket.tMs), (Placement.pocket, 2001));
      expect(
        detector.onLight(const LightSample(2100, 500))!.placement,
        Placement.hand,
      );
    });
    test('near with bright light stays hand; far cancels dark dwell', () {
      final detector = PlacementDetector(usePlacement: true);
      detector.onProximity(const ProximitySample(0, true, 0));
      detector.onLight(const LightSample(0, 100));
      expect(detector.advanceTo(5000), isNull);
      expect(detector.placement, Placement.hand);
      detector.onLight(const LightSample(5100, 5));
      detector.onProximity(const ProximitySample(6000, false, 5));
      expect(detector.advanceTo(9000), isNull);
      expect(detector.placement, Placement.hand);
    });
    test('a bright interruption resets the dwell rather than accumulating darkness', () {
      final detector = PlacementDetector(usePlacement: true);
      detector.onProximity(const ProximitySample(0, true, 0));
      detector.onLight(const LightSample(0, 1));
      detector.onLight(const LightSample(1500, 20));
      detector.onLight(const LightSample(1600, 1));
      expect(detector.advanceTo(3500), isNull);
      expect(detector.advanceTo(3601)!.placement, Placement.pocket);
    });
    test(
      'missing sensors mean unknown; RAM notices do not change placement',
      () {
        final detector = PlacementDetector(usePlacement: true);
        detector.onProximity(const ProximitySample(0, true, 0));
        detector.onLight(const LightSample(0, 1));
        detector.advanceTo(2001);
        expect(
          detector.onDeviceInfo(const DeviceInfo(t: 2100, totalRamMb: 8192)),
          isNull,
        );
        expect(
          detector
              .onDeviceInfo(
                const DeviceInfo(t: 2200, proximityAvailable: false),
              )!
              .placement,
          Placement.unknown,
        );
        expect(
          detector.onProximity(const ProximitySample(2300, true, 0)),
          isNull,
        );
        expect(detector.advanceTo(5000), isNull);
        detector.onDeviceInfo(
          const DeviceInfo(t: 5100, proximityAvailable: true),
        );
        detector.onProximity(const ProximitySample(5200, true, 0));
        expect(detector.advanceTo(7201)!.placement, Placement.pocket);
      },
    );
    test('invalid or old samples do not flip placement', () {
      final detector = PlacementDetector(usePlacement: true);
      detector.onProximity(const ProximitySample(100, false, 5));
      detector.onLight(const LightSample(100, 100));
      expect(detector.onLight(const LightSample(200, double.nan)), isNull);
      expect(detector.onLight(const LightSample(50, 0)), isNull);
      expect(detector.onProximity(const ProximitySample(50, true, 0)), isNull);
      expect(detector.placement, Placement.hand);
    });
    test('usePlacement off has no output or classification', () {
      final detector = PlacementDetector(usePlacement: false);
      expect(detector.onProximity(const ProximitySample(0, true, 0)), isNull);
      expect(detector.onLight(const LightSample(0, 1)), isNull);
      expect(detector.advanceTo(3000), isNull);
      expect(
        detector.onDeviceInfo(const DeviceInfo(t: 4000, lightAvailable: false)),
        isNull,
      );
      expect(detector.placement, Placement.unknown);
    });
    test('invalid placement parameters fail clearly', () {
      expect(() => PlacementDetector(pocketLuxMax: -1), throwsArgumentError);
      expect(
        () => PlacementDetector(pocketLuxMax: double.infinity),
        throwsArgumentError,
      );
      expect(() => PlacementDetector(pocketHoldMs: -1), throwsArgumentError);
    });
    test('placement never changes accepted steps or turn integration', () {
      List<Object> run(bool usePlacement) {
        final gates = SensingGates(
          useBoutGating: true,
          useHandlingGate: true,
          usePlacement: usePlacement,
        );
        final output = <Object>[];
        output.addAll(gates.onRaw(const ProximitySample(0, true, 0)));
        output.addAll(gates.onRaw(const LightSample(0, 1)));
        for (var t = 0; t <= 5000; t += 20) {
          output.addAll(gates.onMotion(t, t > 0 && t <= 1000 ? 90 : 0));
          if (t % 500 == 0 && t < 5000) {
            output.addAll(gates.onStep(contracts.StepEvent(t)));
          }
        }
        return output;
      }

      final on = run(true), off = run(false);
      expect(
        on.whereType<PlacementEvent>().any(
          (e) => e.placement == Placement.pocket,
        ),
        isTrue,
      );
      expect(
        on.whereType<contracts.StepEvent>().map((e) => e.t),
        off.whereType<contracts.StepEvent>().map((e) => e.t),
      );
      expect(on.whereType<contracts.StepEvent>(), hasLength(10));
      expect(
        on.whereType<contracts.TurnEvent>().single.angle,
        closeTo(90, .01),
      );
      expect(off.whereType<PlacementEvent>(), isEmpty);
    });
  });
  test(
    'all flags off preserves today\'s fallback and turn detector results',
    () {
      final gates = SensingGates(
        useBoutGating: false,
        useHandlingGate: false,
        usePlacement: false,
      );
      final steps = StepDetector(), turns = TurnDetector();
      final expectedSteps = <contracts.StepEvent>[],
          expectedTurns = <contracts.TurnEvent>[],
          actual = <Object>[];
      for (var t = 0; t <= 5000; t += 20) {
        final distance = ((t % 500) - 100).abs();
        final accel = distance < 60 ? 13.0 - distance * 3.2 / 60 : 9.8;
        final rate = t > 0 && t <= 1000 ? 90.0 : 0.0;
        final step = steps.onMotion(t, accel), turn = turns.onMotion(t, rate);
        if (step != null) expectedSteps.add(step);
        if (turn != null) expectedTurns.add(turn);
        actual.addAll(gates.onMotion(t, rate, accel: accel));
      }
      expect(
        actual.whereType<contracts.StepEvent>().map((e) => e.t),
        expectedSteps.map((e) => e.t),
      );
      expect(
        actual.whereType<contracts.TurnEvent>().map((e) => (e.t, e.angle)),
        expectedTurns.map((e) => (e.t, e.angle)),
      );
      expect(actual.whereType<PlacementEvent>(), isEmpty);
    },
  );
  test('flag-off detector validation remains independent per motion field', () {
    final gates = SensingGates(
      useBoutGating: false,
      useHandlingGate: false,
      usePlacement: false,
    );
    final output = <Object>[];
    output.addAll(gates.onMotion(0, 0, accel: 9.8));
    output.addAll(gates.onMotion(20, double.nan, accel: 13));
    output.addAll(gates.onMotion(40, double.nan, accel: 9.8));
    expect(output.whereType<contracts.StepEvent>().single.t, 20);
    output.clear();
    // Invalid accel must not prevent yaw processing by the unchanged detector.
    output.addAll(gates.onMotion(100, 0, accel: double.nan));
    for (var t = 120; t <= 1100; t += 20) {
      output.addAll(gates.onMotion(t, 90, accel: double.nan));
    }
    for (var t = 1120; t <= 1620; t += 20) {
      output.addAll(gates.onMotion(t, 0, accel: double.nan));
    }
    expect(
      output.whereType<contracts.TurnEvent>().single.angle,
      closeTo(90, .01),
    );
  });
}
