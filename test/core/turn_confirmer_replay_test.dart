import 'dart:convert';
import 'dart:io';

import 'package:breadcrumb/core/contracts.dart' hide TurnDetector;
import 'package:breadcrumb/core/turn_confirmer.dart';
import 'package:breadcrumb/sensing/turn_detector.dart';
import 'package:flutter_test/flutter_test.dart';

import '../sensing/turn_replay.dart' show scoreTurns, loadExpectedTurns;

/// D29: replays every recorded walk in traces/ through the production
/// TurnDetector, with and without the TurnConfirmer, and scores the turns
/// against traces/expected_turns.json (direction only, one-to-one, in order).
///
/// The raw stream of a trace: hardware steps from its `step` lines and turns
/// from its `motion` samples, merged in time order.
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
  return [for (final (_, e) in events) e];
}

List<Object> _confirmed(List<Object> raw, [StepTurnConfirmer? confirmer]) {
  final pipe = ConfirmedEvents(confirmer);
  return [for (final e in raw) ...pipe.add(e), ...pipe.close()];
}

class _Score {
  int expected = 0, matched = 0, extra = 0, missed = 0, steps = 0;
}

void main() {
  test('trace replay: confirmer on vs off', () async {
    final labels = await loadExpectedTurns('traces/expected_turns.json');
    final files = Directory('traces')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jsonl'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty);

    final off = _Score(), on = _Score();
    final rows = <String>[];
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final expected = labels[name];
      if (expected == null) continue;
      final raw = _rawEvents(file.path);
      final confirmed = _confirmed(raw);
      final rawTurns = raw.whereType<TurnEvent>().toList();
      final onTurns = confirmed.whereType<TurnEvent>().toList();
      final a = scoreTurns(expected, rawTurns, directionsOnly: true);
      final b = scoreTurns(expected, onTurns, directionsOnly: true);
      for (final (s, score, turns, events) in [
        (off, a, rawTurns, raw),
        (on, b, onTurns, confirmed),
      ]) {
        s.expected += expected.length;
        s.matched += score.matched;
        s.extra += score.falseOrSplit;
        s.missed += score.missed;
        s.steps += events.whereType<StepEvent>().length;
        expect(turns.length, score.matched + score.falseOrSplit);
      }
      rows.add(
        '| $name | ${expected.length} | '
        '${rawTurns.map((e) => e.angle.round()).join(', ')} | ${a.falseOrSplit} | ${a.missed} | '
        '${onTurns.map((e) => e.angle.round()).join(', ')} | ${b.falseOrSplit} | ${b.missed} |',
      );
      // The confirmer only drops or merges turns; it never loses a step.
      expect(
        confirmed.whereType<StepEvent>().length,
        raw.whereType<StepEvent>().length,
        reason: name,
      );
    }
    // ignore: avoid_print
    print([
      '| trace | expected | off: angles | off: false | off: missed | on: angles | on: false | on: missed |',
      '|---|---:|---|---:|---:|---|---:|---:|',
      ...rows,
      '| total | ${off.expected} | | ${off.extra} | ${off.missed} | | ${on.extra} | ${on.missed} |',
    ].join('\n'));

    // Sweep: total missed / false turns over the labelled walks.
    final sweep = <String>['| steps / window ms | 3000 | 4000 | 5000 | 6000 | 8000 | 10000 |', '|---|---|---|---|---|---|---|'];
    final traces = {
      for (final f in files)
        if (labels[f.uri.pathSegments.last] != null)
          f.uri.pathSegments.last: _rawEvents(f.path),
    };
    for (final steps in [1, 2, 3]) {
      final cells = <String>[];
      for (final window in [3000, 4000, 5000, 6000, 8000, 10000]) {
        var missed = 0, extra = 0;
        traces.forEach((name, raw) {
          final turns = _confirmed(
            raw,
            StepTurnConfirmer(confirmSteps: steps, windowMs: window),
          ).whereType<TurnEvent>().toList();
          final score = scoreTurns(labels[name]!, turns, directionsOnly: true);
          missed += score.missed;
          extra += score.falseOrSplit;
        });
        cells.add('$missed missed / $extra false');
      }
      sweep.add('| $steps | ${cells.join(' | ')} |');
    }
    // ignore: avoid_print
    print(sweep.join('\n'));

    // On these walks the confirmer must not do worse than the raw detector.
    expect(on.missed, lessThanOrEqualTo(off.missed));
    expect(on.extra, lessThanOrEqualTo(off.extra));
  });

  /// Synthetic, not recorded: the real straight walk with three sidesteps (a
  /// turn and its return 1.2 s later) and two phone handlings (a turn inside a
  /// handling motion state) added. The real traces have no false turns, so this
  /// is the only check of what the confirmer is for.
  test('straight walk with added sidesteps and handling: confirmer on vs off', () {
    final raw = _rawEvents('traces/straight_walk_talha.jsonl');
    final steps = raw.whereType<StepEvent>().map((e) => e.t).toList();
    expect(steps.length, greaterThanOrEqualTo(30));
    final added = <(int, Object)>[];
    for (final k in [5, 15, 25]) {
      final t = steps[k] + 100;
      added
        ..add((t, TurnEvent(t, 80)))
        ..add((t + 1200, TurnEvent(t + 1200, -85)));
    }
    for (final k in [10, 20]) {
      final t = steps[k] + 100;
      added
        ..add((t - 50, MotionStateEvent(MotionState.handling, t - 50)))
        ..add((t, TurnEvent(t, 95)))
        ..add((t + 900, MotionStateEvent(MotionState.walking, t + 900)));
    }
    final events = [
      for (final e in raw) ((e as StepEvent).t, e as Object),
      ...added,
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final script = [for (final (_, e) in events) e];

    final off = script.whereType<TurnEvent>().length;
    final on = _confirmed(script).whereType<TurnEvent>().length;
    // ignore: avoid_print
    print('Synthetic straight walk: 8 false turns added; off passes $off, on passes $on');
    expect(off, 8);
    expect(on, 0);
  });
}
