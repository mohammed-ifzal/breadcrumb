import 'package:breadcrumb/core/contracts.dart' as contracts;
import 'package:breadcrumb/core/tuning.dart' as tuning;
import 'package:breadcrumb/sensing/step_detector.dart';
import 'package:breadcrumb/sensing/turn_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<contracts.TurnEvent> walkTurn(double rate, int duration) {
    final detector = TurnDetector();
    final turns = <contracts.TurnEvent>[];
    detector.onMotion(0, 0);
    for (var t = 20; t <= duration; t += 20) {
      final turn = detector.onMotion(t, rate);
      if (turn != null) turns.add(turn);
    }
    for (var t = duration + 20; t <= duration + 1020; t += 20) {
      final turn = detector.onMotion(t, 0);
      if (turn != null) turns.add(turn);
    }
    return turns;
  }

  test('left turn emits the whole +90 degrees once after settling', () {
    final turns = walkTurn(90, 1000);
    expect(turns, hasLength(1));
    expect(turns.single.angle, closeTo(90, 0.01));
    expect(turns.single.t, 1020 + tuning.turnSettleMs);
  });
  test('right turn emits -90 degrees once', () {
    expect(walkTurn(-90, 1000).single.angle, closeTo(-90, 0.01));
  });
  test('slow 20 degree sway is ignored', () {
    expect(walkTurn(10, 2000), isEmpty);
  });
  test('short fast sway is discarded and does not contaminate next turn', () {
    final detector = TurnDetector();
    detector.onMotion(0, 0);
    detector.onMotion(200, 100);
    expect(detector.onMotion(220, 0), isNull);
    expect(detector.onMotion(220 + tuning.turnSettleMs, 0), isNull);
    detector.onMotion(740, 0);
    detector.onMotion(1740, -90);
    expect(detector.onMotion(1760, 0), isNull);
    expect(detector.onMotion(2260, 0)?.angle, closeTo(-90, 0.01));
  });
  test('brief settling interruption stays part of one turn', () {
    final detector = TurnDetector();
    detector.onMotion(0, 0);
    detector.onMotion(500, 90);
    detector.onMotion(520, 0);
    expect(detector.onMotion(700, 0), isNull);
    detector.onMotion(1200, 90);
    detector.onMotion(1220, 0);
    expect(detector.onMotion(1720, 0)?.angle, closeTo(90, 0.01));
  });
  test('duplicate and out of order motion times do not integrate', () {
    final detector = TurnDetector();
    detector.onMotion(0, 0);
    detector.onMotion(1000, 90);
    expect(detector.onMotion(1000, 90), isNull);
    expect(detector.onMotion(900, 90), isNull);
    detector.onMotion(1020, 0);
    expect(detector.onMotion(1520, 0)?.angle, closeTo(90, 0.01));
  });
  test('below threshold acceleration peaks do not count', () {
    final detector = StepDetector();
    expect(detector.onMotion(0, 9), isNull);
    expect(detector.onMotion(20, tuning.accelPeakThreshold - 0.1), isNull);
    expect(detector.onMotion(40, 9), isNull);
  });
  test('one plateau peak gives one step at the peak time', () {
    final detector = StepDetector();
    detector.onMotion(0, 9);
    detector.onMotion(20, 13);
    detector.onMotion(40, 13);
    expect(detector.onMotion(60, 9)?.t, 20);
    expect(detector.onMotion(80, 9), isNull);
  });
  test('step peaks respect tuning gap and recover for the next peak', () {
    final detector = StepDetector();
    detector.onMotion(0, 9);
    detector.onMotion(20, 13);
    expect(detector.onMotion(40, 9)?.t, 20);
    detector.onMotion(100, 13);
    expect(detector.onMotion(120, 9), isNull);
    detector.onMotion(20 + tuning.accelPeakMinGapMs, 13);
    expect(
      detector.onMotion(40 + tuning.accelPeakMinGapMs, 9)?.t,
      20 + tuning.accelPeakMinGapMs,
    );
  });
  test('invalid samples are ignored without poisoning detectors', () {
    final step = StepDetector();
    final turn = TurnDetector();
    expect(step.onMotion(0, double.nan), isNull);
    expect(turn.onMotion(0, double.infinity), isNull);
    step.onMotion(0, 9);
    step.onMotion(20, 13);
    expect(step.onMotion(40, 9)?.t, 20);
    turn.onMotion(0, 0);
    turn.onMotion(1000, 90);
    turn.onMotion(1020, 0);
    expect(turn.onMotion(1520, 0)?.angle, 90);
  });
}
