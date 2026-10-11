import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:breadcrumb/core/contracts.dart' hide TurnDetector;
import 'package:breadcrumb/core/turn_confirmer.dart';
import 'package:breadcrumb/core/tuning.dart' as tuning;
import 'package:breadcrumb/sensing/turn_detector.dart';
import 'package:flutter_test/flutter_test.dart';

import 'turn_replay.dart' show loadTrace, replay, scoreTurns;

const _scenarios = [
  'look_around',
  'queue',
  'pullout',
  'curve',
  'pocket_left_loop',
  'pocket_right_loop',
  'bag_loop',
];
String _active = 'not started';

/// Same raw-events harness as test/core/turn_confirmer_replay_test.dart.
/// Those helpers are library-private, so mirror their chronological merge here
/// without editing or running the existing test. Keep hardware steps, production
/// TurnDetector defaults, and its emission timestamps. Do not infer handling or
/// placement from gravity/proximity, apply other gates, or append a settling tail.
List<Object> _rawEvents(String path) {
  final events = <(int, Object)>[];
  final detector = TurnDetector();
  for (final line in File(path).readAsLinesSync()) {
    final row = jsonDecode(line) as Map<String, dynamic>;
    final t = (row['t'] as num?)?.toInt();
    switch (row['type']) {
      case 'step':
        events.add((t!, StepEvent(t)));
      case 'motion':
        final turn = detector.onMotion(t!, (row['yawRate'] as num).toDouble());
        if (turn != null) events.add((turn.t, turn));
    }
  }
  events.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final (_, event) in events) event];
}

/// Local analysis switch: explicitly bypass or use the real D29 pipe even though
/// tuning.useTurnConfirmer is false. Close drops pending turns, releasing steps,
/// exactly as the captain's replay harness does. No shared flag is changed.
List<Object> _run(List<Object> raw, {required bool enabled}) {
  if (!enabled) return List.of(raw);
  final pipe = ConfirmedEvents();
  return [for (final event in raw) ...pipe.add(event), ...pipe.close()];
}

String _angles(List<TurnEvent> turns) => turns.isEmpty
    ? '[]'
    : turns
          .map((t) => '${t.angle >= 0 ? '+' : ''}${t.angle.toStringAsFixed(2)}')
          .join(', ');

Future<void> _report() async {
  stdout.writeln(
    'PROVEN replay: default rate=${tuning.turnRateMin}, '
    'settle=${tuning.turnSettleMs}, '
    'confirmSteps=${tuning.turnConfirmSteps}, '
    'windowMs=${tuning.turnConfirmWindowMs}, minAngle=${tuning.turnMinAngle}. '
    'Shared useTurnConfirmer=${tuning.useTurnConfirmer}; '
    'ON is an explicit analysis-only pipeline, not a production flag edit.',
  );
  stdout.writeln(
    'PROVEN scoring: tester labels from each expected_<scenario>.json; ordered '
    'one-to-one sign matching, ties minimize angle error. False=unmatched '
    'detection, missed=unmatched expected label. Large events match at most '
    'one corner. No inferred motion states; hardware steps are observations, '
    'not independently verified walking. Step truth remains null.',
  );
  stdout.writeln(
    '| trace | expected angles | off angles | off false | off missed | '
    'on angles | on false | on missed |',
  );
  stdout.writeln('|---|---|---|---:|---:|---|---:|---:|');
  var offFalse = 0, offMissed = 0, onFalse = 0, onMissed = 0;
  for (final name in _scenarios) {
    _active = name;
    final path = 'traces/$name.jsonl';
    final label = jsonDecode(
      await File('traces/expected_$name.json').readAsString(),
    ) as Map<String, dynamic>;
    expect(label['trace'], '$name.jsonl');
    expect(label['steps'], isNull);
    final expected = (label['turns'] as List)
        .map((angle) => (angle as num).toDouble())
        .toList();
    final raw = _rawEvents(path);
    final off = _run(raw, enabled: false);
    final on = _run(raw, enabled: true);
    final offTurns = off.whereType<TurnEvent>().toList();
    final onTurns = on.whereType<TurnEvent>().toList();
    // Check copied harness semantics against the existing public replay helper.
    final existingTurns = replay(
      await loadTrace(path),
      turnRateMin: tuning.turnRateMin,
      turnSettleMs: tuning.turnSettleMs,
    ).turns;
    expect(
      offTurns.map((t) => (t.t, t.angle)),
      existingTurns.map((t) => (t.t, t.angle)),
      reason: name,
    );
    expect(
      on.whereType<StepEvent>().map((step) => step.t),
      raw.whereType<StepEvent>().map((step) => step.t),
      reason: 'Confirmation must preserve all hardware step events in $name',
    );
    final a = scoreTurns(expected, offTurns, directionsOnly: true);
    final b = scoreTurns(expected, onTurns, directionsOnly: true);
    offFalse += a.falseOrSplit;
    offMissed += a.missed;
    onFalse += b.falseOrSplit;
    onMissed += b.missed;
    stdout.writeln(
      '| $name | $expected | ${_angles(offTurns)} | ${a.falseOrSplit} | '
      '${a.missed} | ${_angles(onTurns)} | ${b.falseOrSplit} | ${b.missed} |',
    );
    stdout.writeln(
      'PROVEN PROGRESS: completed $name; '
      'hardware steps preserved=${on.whereType<StepEvent>().length}',
    );
    await Future<void>.delayed(Duration.zero);
  }
  stdout.writeln(
    '| TOTAL | | | $offFalse | $offMissed | | $onFalse | $onMissed |',
  );
  stdout.writeln(
    'HYPOTHESIS: Confirmation may reject phone-only yaw when no walking '
    'follows. This replay does not infer handling states, correct false '
    'hardware steps, or establish deployment safety.',
  );
}

/// Print verbatim source rather than maintaining another declaration copy.
void _printD29Source() {
  final contracts = File('lib/core/contracts.dart').readAsStringSync();
  final tuningSource = File('lib/core/tuning.dart').readAsStringSync();
  String block(String first, String next) {
    final start = contracts.indexOf(first);
    final end = contracts.indexOf(next, start);
    if (start < 0 || end < start) {
      throw StateError('Missing D29 declaration block: $first');
    }
    return contracts.substring(start, end).trimRight();
  }

  stdout.writeln('PROVEN exact D29 declarations from lib/core/contracts.dart:');
  stdout.writeln(block('/// What the walker is doing', 'enum ReaderKind'));
  stdout.writeln(
    block("/// The walker's motion state changed", 'class SignReading'),
  );
  stdout.writeln(
    block('/// Owner: Teammate 2. [events]', '/// Owner: Ifzal. Sits between'),
  );
  final section = tuningSource.indexOf('// D29: robust core.');
  if (section < 0) throw StateError('D29 tuning section missing');
  stdout.writeln('PROVEN exact D29 additions from lib/core/tuning.dart:');
  stdout.writeln(tuningSource.substring(section).trimRight());
}

void main() {
  test('analysis switch bypasses or confirms with shared D29 defaults', () {
    const raw = <Object>[TurnEvent(0, -90), StepEvent(1000), StepEvent(2000)];
    expect(_run(raw, enabled: false), raw);
    final on = _run(raw, enabled: true);
    expect(on.whereType<TurnEvent>().single.angle, -90);
    expect(on.whereType<StepEvent>().map((step) => step.t), [1000, 2000]);
  });

  test('closing the harness drops unconfirmed turns without losing steps', () {
    final on = _run(const [TurnEvent(0, 90), StepEvent(1000)], enabled: true);
    expect(on.whereType<TurnEvent>(), isEmpty);
    expect(on.whereType<StepEvent>().single.t, 1000);
  });

  test('recorded scenarios: D29 confirmer off versus on', () async {
    await _report().timeout(
      const Duration(minutes: 2),
      onTimeout: () => throw TimeoutException('Active scenario: $_active'),
    );
  }, timeout: const Timeout(Duration(seconds: 125)));

  test('print exact current D29 contracts and tuning declarations', () {
    _printD29Source();
  });
}
