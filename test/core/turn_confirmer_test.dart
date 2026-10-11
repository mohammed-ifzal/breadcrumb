import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/fakes.dart';
import 'package:breadcrumb/core/turn_confirmer.dart';
import 'package:breadcrumb/core/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

/// Confirmed turns as (t, angle) for a script fed to a fresh confirmer.
List<(int, double)> _confirm(List<Object> script, {StepTurnConfirmer? c}) {
  final confirmer = c ?? StepTurnConfirmer(confirmSteps: 2, windowMs: 4000, minAngle: 60);
  final out = <(int, double)>[];
  confirmer.confirmed.listen((e) => out.add((e.t, e.angle)));
  for (final e in script) {
    switch (e) {
      case StepEvent():
        confirmer.onStep(e);
      case TurnEvent():
        confirmer.onTurn(e);
      case MotionStateEvent():
        confirmer.onMotionState(e);
    }
  }
  return out;
}

void main() {
  group('StepTurnConfirmer', () {
    test('defaults come from tuning.dart', () {
      final c = StepTurnConfirmer();
      expect(c.confirmSteps, turnConfirmSteps);
      expect(c.windowMs, turnConfirmWindowMs);
      expect(c.minAngle, turnMinAngle);
    });

    test('a turn followed by enough steps in the window is confirmed', () {
      expect(
        _confirm([const TurnEvent(1000, 88), const StepEvent(1500), const StepEvent(2000)]),
        [(1000, 88.0)],
      );
    });

    test('one step is not enough', () {
      final c = StepTurnConfirmer(confirmSteps: 2, windowMs: 4000, minAngle: 60);
      expect(_confirm([const TurnEvent(1000, 88), const StepEvent(1500)], c: c), isEmpty);
      expect(c.pending, isTrue);
    });

    test('a turn with no steps in the window is dropped', () {
      final c = StepTurnConfirmer(confirmSteps: 2, windowMs: 4000, minAngle: 60);
      expect(
        _confirm([
          const TurnEvent(1000, 88),
          const StepEvent(6000),
          const StepEvent(6500),
        ], c: c),
        isEmpty,
      );
      expect(c.pending, isFalse);
    });

    test('a step inside the window then one outside drops the turn', () {
      expect(
        _confirm([
          const TurnEvent(1000, 88),
          const StepEvent(2000),
          const StepEvent(5500),
        ]),
        isEmpty,
      );
    });

    test('a turn while handling the phone is dropped', () {
      expect(
        _confirm([
          const MotionStateEvent(MotionState.handling, 900),
          const TurnEvent(1000, 95),
          const MotionStateEvent(MotionState.walking, 1200),
          const StepEvent(1500),
          const StepEvent(2000),
        ]),
        isEmpty,
      );
    });

    test('handling while a candidate waits drops it', () {
      expect(
        _confirm([
          const TurnEvent(1000, 95),
          const StepEvent(1400),
          const MotionStateEvent(MotionState.handling, 1500),
          const MotionStateEvent(MotionState.walking, 2500),
          const StepEvent(3000),
          const StepEvent(3500),
        ]),
        isEmpty,
      );
    });

    test('a turn while standing still, then walking, is confirmed', () {
      expect(
        _confirm([
          const MotionStateEvent(MotionState.still, 500),
          const TurnEvent(1000, -90),
          const MotionStateEvent(MotionState.walking, 1800),
          const StepEvent(2000),
          const StepEvent(2500),
        ]),
        [(1000, -90.0)],
      );
    });

    test('a sidestep and back nets to zero and is dropped', () {
      expect(
        _confirm([
          const TurnEvent(1000, 85),
          const StepEvent(1500),
          const TurnEvent(2000, -80),
          const StepEvent(2500),
          const StepEvent(3000),
        ]),
        isEmpty,
      );
    });

    test('candidates with no step between them are not merged or confirmed (D32)', () {
      expect(
        _confirm([
          const TurnEvent(1000, 62),
          const TurnEvent(1600, 65),
          const StepEvent(2000),
          const StepEvent(2500),
        ]),
        isEmpty,
      );
    });

    test('T2 look_around: -76, -81, +96 on the spot, then 2 steps: no turn (D32)', () {
      // Raw candidates from traces/look_around.jsonl (branch t2/robust-sensing);
      // merged they made -60 and were confirmed.
      final script = [
        for (var t = 2690000; t < 2700000; t += 2000) StepEvent(t),
        const TurnEvent(2700886, -76),
        const TurnEvent(2703566, -81),
        const TurnEvent(2706506, 96),
        const StepEvent(2707200),
        const StepEvent(2707800),
      ];
      expect(_confirm(script), isEmpty);
      expect(_confirm(script, c: StepTurnConfirmer()), isEmpty);
    });

    test('after a burst, a turn after a step stands on its own', () {
      expect(
        _confirm([
          const TurnEvent(1000, -76),
          const TurnEvent(1500, 96),
          const StepEvent(2000),
          const TurnEvent(2500, -90),
          const StepEvent(3000),
          const StepEvent(3500),
        ]),
        [(2500, -90.0)],
      );
    });

    test('two corners far apart give two turns', () {
      expect(
        _confirm([
          const TurnEvent(1000, 90),
          const StepEvent(1500),
          const StepEvent(2000),
          for (var t = 2500; t <= 6000; t += 500) StepEvent(t),
          const TurnEvent(6500, -90),
          const StepEvent(7000),
          const StepEvent(7500),
        ]),
        [(1000, 90.0), (6500, -90.0)],
      );
    });

    test('steps with no turn do nothing', () {
      expect(_confirm([const StepEvent(1), const StepEvent(2)]), isEmpty);
    });
  });

  group('ConfirmedEvents keeps order', () {
    List<Object> run(List<Object> script) {
      final pipe = ConfirmedEvents(
        StepTurnConfirmer(confirmSteps: 2, windowMs: 4000, minAngle: 60),
      );
      return [for (final e in script) ...pipe.add(e), ...pipe.close()];
    }

    String show(List<Object> events) => events
        .map(
          (e) => switch (e) {
            StepEvent() => 's${e.t}',
            TurnEvent() => 't${e.t}:${e.angle.round()}',
            MotionStateEvent() => 'm:${e.state.name}',
            _ => '?',
          },
        )
        .join(' ');

    test('a confirmed turn comes before the steps that confirmed it', () {
      expect(
        show(run([
          const StepEvent(500),
          const TurnEvent(1000, 90),
          const StepEvent(1500),
          const StepEvent(2000),
          const StepEvent(2500),
        ])),
        's500 t1000:90 s1500 s2000 s2500',
      );
    });

    test('a dropped turn leaves its steps in place', () {
      expect(
        show(run([
          const TurnEvent(1000, 85),
          const StepEvent(1500),
          const TurnEvent(2000, -80),
          const StepEvent(2500),
          const StepEvent(3000),
        ])),
        's1500 s2500 s3000',
      );
    });

    test('an expired candidate releases its steps before the next one', () {
      expect(
        show(run([
          const TurnEvent(1000, 90),
          const StepEvent(1500),
          const TurnEvent(9000, -90),
          const StepEvent(9500),
          const StepEvent(10000),
        ])),
        's1500 t9000:-90 s9500 s10000',
      );
    });

    test('handling releases held steps and is passed on', () {
      expect(
        show(run([
          const TurnEvent(1000, 90),
          const StepEvent(1500),
          const MotionStateEvent(MotionState.handling, 1600),
          const StepEvent(2000),
        ])),
        's1500 m:handling s2000',
      );
    });

    test('a candidate waiting at the end of the stream is dropped', () {
      expect(show(run([const TurnEvent(1000, 90), const StepEvent(1500)])), 's1500');
    });
  });

  test('confirmedEvents runs a SensingSource through the confirmer', () async {
    final source = FakeSensingSource([
      const TurnEvent(1000, 90),
      const StepEvent(1500),
      const StepEvent(2000),
      const TurnEvent(3000, 80),
      const StepEvent(3500),
      const TurnEvent(4000, -80),
      const StepEvent(4500),
      const StepEvent(5000),
    ]);
    final events = await confirmedEvents(source).toList();
    expect(events.whereType<TurnEvent>().map((e) => e.angle), [90]);
    expect(events.whereType<StepEvent>(), hasLength(5));
    expect(events.whereType<MotionStateEvent>().single.state, MotionState.walking);
  });
}
