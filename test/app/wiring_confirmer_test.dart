import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/fakes.dart';
import 'package:breadcrumb/core/tuning.dart' as tuning;
import 'package:flutter_test/flutter_test.dart';

/// D29: Wiring passes real sensor turns through the TurnConfirmer when
/// `useTurnConfirmer` is on.
void main() {
  // A real left turn, then a sidestep and back, each followed by steps.
  const script = <Object>[
    TurnEvent(1000, 90),
    StepEvent(1500),
    StepEvent(2000),
    TurnEvent(3000, 80),
    StepEvent(3500),
    TurnEvent(4000, -80),
    StepEvent(4500),
    StepEvent(5000),
  ];

  Future<List<Object>> run(bool confirmerOn) async {
    final wiring = Wiring.instance;
    final saved = (wiring.sensingSource, wiring.useTurnConfirmer);
    wiring
      ..sensingSource = FakeSensingSource(script)
      ..useTurnConfirmer = confirmerOn;
    final events = <Object>[];
    final sub = wiring.sensorEvents().listen(events.add);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    wiring
      ..sensingSource = saved.$1
      ..useTurnConfirmer = saved.$2;
    return events;
  }

  test('defaults to tuning.useTurnConfirmer', () {
    expect(Wiring.instance.useTurnConfirmer, tuning.useTurnConfirmer);
  });

  test('off: every raw turn reaches the Tracker', () async {
    final events = await run(false);
    expect(events.whereType<TurnEvent>().map((e) => e.angle), [90, 80, -80]);
    expect(events.whereType<StepEvent>(), hasLength(5));
  });

  test('on: only the confirmed turn reaches the Tracker, before its steps', () async {
    final events = await run(true);
    expect(events.whereType<TurnEvent>().map((e) => e.angle), [90]);
    expect(events.whereType<StepEvent>(), hasLength(5));
    expect(events.whereType<Object>().where((e) => e is StepEvent || e is TurnEvent).first,
        isA<TurnEvent>());
  });
}
