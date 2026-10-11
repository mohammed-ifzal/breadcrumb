import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:breadcrumb/core/contracts.dart' show StepEvent, TurnEvent;
import 'package:breadcrumb/core/turn_confirmer.dart';
import 'package:breadcrumb/core/tuning.dart' as tuning;
import 'package:breadcrumb/sensing/trace_replay.dart';
import 'package:flutter_test/flutter_test.dart';

import 'turn_replay.dart' as harness;

const _truth = {
  'pocket_right_2': [-90.0, -90.0, -90.0, -90.0],
  'pocket_left_2': [-90.0, -90.0, -90.0, -90.0],
  'hand_prox': [-90.0, 90.0, -90.0],
};
const _notes = {
  'pocket_left_2': 'fresh validation walk, 4-step legs, phone in left pocket, four right turns; earlier label (+90) was wrong; step count not recorded; not used for tuning',
  'hand_prox': "fresh validation walk, 4-step legs, finger covered the sensor during the middle turn, first mark misspelled 'hamd prox'; not used for tuning",
};
String _n(num? value) => value == null ? 'NA' : value.toStringAsFixed(2);
String _angles(List<TurnEvent> turns) => turns.isEmpty
    ? '[]'
    : turns.map((e) => '${e.angle >= 0 ? '+' : ''}${_n(e.angle)}').join(', ');
String _time(int t, TraceReplayData data) =>
    ((t - data.timing.firstTimestampMs!) / 1000).toStringAsFixed(3);

/// Same chronological hardware-step + turn merge and ConfirmedEvents.close
/// semantics as the private helpers in combined_scenarios_test.dart.
/// Use public replay helper's PRODUCTION TurnDetector profile implementation,
/// not the old analysis-only rate-zero proxy. Do not run existing tests.
List<TurnEvent> _confirmed(TraceReplayData data, List<TurnEvent> turns) {
  final events = <Object>[
    for (final row in data.records)
      if (row['type'] == 'step') StepEvent((row['t'] as num).toInt()),
    ...turns,
  ];
  int t(Object e) => e is StepEvent ? e.t : (e as TurnEvent).t;
  events.sort((a, b) => t(a).compareTo(t(b)));
  final pipe = ConfirmedEvents(
    StepTurnConfirmer(confirmSteps: 2, windowMs: 8000),
  );
  final output = [for (final e in events) ...pipe.add(e), ...pipe.close()];
  expect(
    output.whereType<StepEvent>().map((e) => e.t),
    events.whereType<StepEvent>().map((e) => e.t),
  );
  return output.whereType<TurnEvent>().toList();
}

List<(int, int)> _nearIntervals(TraceReplayData data) {
  final rows = data.records.where((r) => r['type'] == 'proximity').toList()
    ..sort((a, b) => (a['t'] as num).compareTo(b['t'] as num));
  final intervals = <(int, int)>[];
  int? since;
  for (final row in rows) {
    final t = (row['t'] as num).toInt();
    if (row['near'] == true) {
      since ??= t;
    } else if (since != null) {
      intervals.add((since, t));
      since = null;
    }
  }
  if (since != null) intervals.add((since, data.timing.lastTimestampMs!));
  return intervals;
}

bool _inside(int t, List<(int, int)> near) =>
    near.any((i) => t >= i.$1 && t < i.$2);

Future<void> _inventory() async {
  final staging = Platform.environment['FRESH_STAGING'];
  if (staging == null) return;
  final manifest = jsonDecode(
    await File('$staging/fresh_inventory.json').readAsString(),
  ) as Map<String, dynamic>;
  final inventory = manifest['inventory'] as List;
  expect(inventory, hasLength(8));
  stdout.writeln(
    'PROVEN pulled inventory: duration uses TraceReplayData, excludes info/meta. All eight byte sizes matched device listing.',
  );
  stdout.writeln(
    '| source filename | bytes | duration s | hardware steps | marks (sample-relative time: text) | match |',
  );
  stdout.writeln('|---|---:|---:|---:|---|---|');
  for (final item in inventory) {
    final row = item as Map<String, dynamic>;
    final data = TraceReplayData.parse(
      await File('$staging/${row['file']}').readAsString(),
    );
    expect(data.timing.durationSeconds, row['duration']);
    expect(await File('$staging/${row['file']}').length(), row['size']);
    final marks = row['marks'] as List;
    stdout.writeln(
      '| ${row['file']} | ${row['size']} | ${_n(row['duration'] as num)} | '
      '${row['hardwareSteps']} | ${marks.length}: ${marks.map((m) => '${(m['seconds'] as num).toStringAsFixed(3)}s: "${m['note']}"').join('; ')} | '
      '${row['identified'] ?? 'ignored'} |',
    );
  }
}

void main() {
  test('analysis scores signs and ordered +/-25 matches separately', () {
    final turns = [
      for (final angle in [-135.0, -108.0, -79.0, -85.0, -74.0])
        TurnEvent(0, angle),
    ];
    final labels = [-90.0, -90.0, -90.0, -90.0];
    final sign = harness.scoreTurns(labels, turns, directionsOnly: true);
    expect((sign.matched, sign.falseOrSplit, sign.missed), (4, 1, 0));
    expect(harness.scoreTurns(labels, turns, angleTolerance: 25).matched, 4);
    expect(
      harness
          .scoreTurns(labels, turns.take(4).toList(), angleTolerance: 25)
          .matched,
      3,
    );
  });
  test(
    'raw audit normalizes gravity and respects strict burst duration/gaps',
    () {
      final gravity = TraceReplayData.fromRecords([
        {'type': 'meta'},
        {'type': 'gravity', 't': 0, 'x': 0, 'y': 0, 'z': 2},
        {'type': 'gravity', 't': 20, 'x': 0, 'y': 0, 'z': 12},
      ]);
      expect(_meanGravity(gravity, 0, 100).vector, [0, 0, 1]);
      final samples = <harness.MotionSample>[
        const harness.MotionSample(0, 0),
        for (var t = 20; t <= 300; t += 20) harness.MotionSample(t, 90),
        const harness.MotionSample(320, 0),
        for (var t = 340; t <= 740; t += 20) harness.MotionSample(t, -90),
        const harness.MotionSample(1000, 150),
        const harness.MotionSample(1020, 150),
        const harness.MotionSample(1040, 150),
        const harness.MotionSample(1060, 0),
      ];
      final audit = _rotation(harness.TraceData('synthetic', samples, []));
      expect(audit.bursts, hasLength(1));
      expect((audit.bursts.single.start, audit.bursts.single.end), (320, 740));
      expect(audit.bursts.single.angle, closeTo(-37.8, .0001));
      expect(audit.net, closeTo(34.2, .0001));
      expect((audit.gaps, audit.maxGap), (1, 260));
    },
  );
  test('fresh validation inventory and four-mode replay, no retuning', () async {
    await _inventory();
    stdout.writeln(
      'PROVEN: A global15/300; B production usePocketTurnProfile=true '
      '(near30/300, otherwise15/300), C=2steps/8000ms. '
      'Chronological hardware-step+turn merge; no gates, inferred proximity, '
      'synthetic tail or parameter sweep. Ordered one-to-one sign matching; '
      'MAE only over sign matches; NA when none. Within25 is a SEPARATE ordered one-to-one angle-tolerant score, inclusive +/-25. Steps are observations, not truth.',
    );
    for (final entry in _truth.entries) {
      final name = entry.key;
      final file = File('traces/$name.jsonl');
      if (!await file.exists()) {
        stdout.writeln(
          'MISSING $name: no eligible first-mark match; not labelled or scored.',
        );
        continue;
      }
      final data = TraceReplayData.parse(await file.readAsString());
      final label = jsonDecode(
        await File('traces/expected_$name.json').readAsString(),
      ) as Map<String, dynamic>;
      expect(label['trace'], '$name.jsonl');
      expect(label['turns'], entry.value);
      expect(label['steps'], isNull);
      expect(
        label['notes'],
        _notes[name] ??
            'fresh validation walk, 4-step legs, not used for tuning',
      );
      final firstMark = data.records.firstWhere((r) => r['type'] == 'mark');
      final normalized = (firstMark['note'] as String).toLowerCase().replaceAll(
        RegExp(r'[\s_]'),
        '',
      );
      expect(
        normalized,
        name == 'hand_prox' ? 'hamdprox' : name.replaceAll('_', ''),
      );
      final trace = await harness.loadTrace(file.path);
      List<TurnEvent> run(bool enabled) => harness
          .replay(
            trace,
            turnRateMin: 15,
            turnSettleMs: 300,
            usePocketTurnProfile: enabled,
            pocketTurnRateMin: 30,
            pocketTurnSettleMs: 300,
          )
          .turns;
      final a = run(false), b = run(true);
      final modes = {
        'A': a,
        'A+C': _confirmed(data, a),
        'B': b,
        'B+C': _confirmed(data, b),
      };
      stdout.writeln(
        'PROVEN $name; expected=${entry.value}; duration=${data.timing.durationSeconds}s; '
        'hardware steps=${data.records.where((r) => r['type'] == 'step').length}',
      );
      stdout.writeln(
        '| mode | expected | detected signed angles | false | missed | mean angle error | within +/-25 |',
      );
      stdout.writeln('|---|---|---|---:|---:|---:|---:|');
      for (final mode in modes.entries) {
        final score = harness.scoreTurns(
          entry.value,
          mode.value,
          directionsOnly: true,
        );
        expect(mode.value.length, score.matched + score.falseOrSplit);
        final within25 = harness
            .scoreTurns(entry.value, mode.value, angleTolerance: 25)
            .matched;
        stdout.writeln(
          '| ${mode.key} | ${entry.value} | ${_angles(mode.value)} | '
          '${score.falseOrSplit} | ${score.missed} | ${_n(score.meanMatchedError)} | $within25 |',
        );
      }
      final prox = data.records.where((r) => r['type'] == 'proximity').toList();
      stdout.writeln('PROVEN every proximity record $name:');
      stdout.writeln('| time s | near | provenance |');
      stdout.writeln('|---:|---|---|');
      for (final row in prox) {
        stdout.writeln(
          '| ${_time((row['t'] as num).toInt(), data)} | ${row['near']} | '
          '${row['origin'] ?? 'not recorded'}${row['snapshot'] == true ? ' snapshot' : ''} |',
        );
      }
      final near = _nearIntervals(data);
      final lux =
          data.records
              .where((r) => r['type'] == 'light')
              .map((r) => (r['lux'] as num).toDouble())
              .toList()
            ..sort();
      stdout.writeln(
        'PROVEN $name lux whole-trace min/max='
        '${_n(lux.isEmpty ? null : lux.first)}/${_n(lux.isEmpty ? null : lux.last)}; '
        'recorded near intervals=${near.isEmpty ? 'none' : near.map((i) => '[${_time(i.$1, data)},${_time(i.$2, data)})s').join(', ')}. '
        'Unknown before first observation; unfinished near clipped at Stop.',
      );
      if (name == 'hand_prox') {
        stdout.writeln(
          'PROVEN hand_prox near audit: emission times only, '
          'not physical-turn start/end. A/B correspondence by index is '
          'diagnostic when counts/signs differ, not an asserted physical match.',
        );
        stdout.writeln(
          '| mode | angle | emission s | within recorded near interval |',
        );
        stdout.writeln('|---|---:|---:|---|');
        for (final mode in {'A': a, 'B': b}.entries) {
          for (final turn in mode.value) {
            stdout.writeln(
              '| ${mode.key} | ${_n(turn.angle)} | ${_time(turn.t, data)} | '
              '${_inside(turn.t, near)} |',
            );
          }
        }
        String bytes(List<TurnEvent> ts) => jsonEncode([
          for (final t in ts) [t.t, t.angle],
        ]);
        stdout.writeln(
          'PROVEN hand_prox B changes timestamp/angle sequence=${bytes(a) != bytes(b)}',
        );
        for (var i = 0; i < a.length || i < b.length; i++) {
          final before = i < a.length ? a[i] : null,
              after = i < b.length ? b[i] : null;
          stdout.writeln(
            'PROVEN ordinal${i + 1}: A=${before == null ? 'missing' : '${_n(before.angle)}@${_time(before.t, data)}s'}, '
            'B=${after == null ? 'missing' : '${_n(after.angle)}@${_time(after.t, data)}s'}',
          );
        }
      }
      stdout.writeln('PROVEN PROGRESS completed $name');
    }
    await _signCheck();
    stdout.writeln(
      'HYPOTHESIS: fresh-walk replay may generalize prior calibration; '
      'these measurements alone do not prove field accuracy or justify changing tuning.',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}

class _MeanGravity {
  _MeanGravity(this.vector, this.count, this.nearCount);
  final List<double> vector;
  final int count, nearCount;
}

_MeanGravity _meanGravity(TraceReplayData data, int from, int to) {
  final sum = [0.0, 0.0, 0.0];
  var count = 0, nearCount = 0;
  final near = _nearIntervals(data);
  for (final row in data.records.where((r) => r['type'] == 'gravity')) {
    final t = (row['t'] as num).toInt();
    if (t < from || t >= to) continue;
    final v = [
      for (final axis in ['x', 'y', 'z']) (row[axis] as num).toDouble(),
    ];
    final norm = math.sqrt(v.fold<double>(0, (a, b) => a + b * b));
    if (!norm.isFinite || norm == 0) continue;
    for (var axis = 0; axis < 3; axis++) {
      sum[axis] += v[axis] / norm;
    }
    count++;
    if (_inside(t, near)) nearCount++;
  }
  return _MeanGravity(
    [for (final v in sum) count == 0 ? double.nan : v / count],
    count,
    nearCount,
  );
}

class _Burst {
  _Burst(this.start, this.end, this.sign, this.angle);
  final int start, sign;
  int end;
  double angle;
}

class _Rotation {
  final bursts = <_Burst>[];
  double net = 0;
  int gaps = 0, maxGap = 0;
}

_Rotation _rotation(harness.TraceData trace) {
  final result = _Rotation();
  _Burst? active;
  int? previous;
  void finish() {
    if (active != null && active!.end - active!.start > 300) {
      result.bursts.add(active!);
    }
    active = null;
  }

  for (final sample in trace.motion) {
    final before = previous;
    if (before == null) {
      previous = sample.t;
      continue;
    }
    final dt = sample.t - before;
    if (dt <= 0) continue;
    previous = sample.t;
    result.net += sample.yawRate * dt / 1000;
    result.maxGap = math.max(result.maxGap, dt);
    if (dt > tuning.maxMotionGapMs) result.gaps++;
    if (dt > tuning.maxMotionGapMs || sample.yawRate.abs() <= 15) {
      finish();
      continue;
    }
    final sign = sample.yawRate.sign.toInt();
    if (active?.sign != sign) {
      finish();
      active = _Burst(before, sample.t, sign, 0);
    }
    active!.end = sample.t;
    active!.angle += sample.yawRate * dt / 1000;
  }
  finish();
  return result;
}

Future<void> _signCheck() async {
  stdout.writeln(
    'PROVEN SIGN AUDIT: first[0,2)s and a 2s window centred on '
    'trace midpoint. Arithmetic mean of EACH normalized gravity sample '
    '(mean not renormalized); near% is recorded-state coverage, not proof '
    'of physical placement. Net is unfiltered right-endpoint yaw integral '
    'over all positive intervals, including gaps. Burst samples must be '
    'contiguous, same sign, abs(yawRate)>15 and total interval duration>0.3s; '
    'below-threshold/sign-change/>maxMotionGapMs ends a burst. '
    'A qualifying sample describes its preceding interval. Bursts are not '
    'labelled corners. Info/meta never define the clock.',
  );
  stdout.writeln(
    '| trace | first2 mean unit gravity | middle2 range s | middle2 mean unit gravity | samples first/middle | recorded near% first/middle | net raw degrees | >200ms gaps / max gap ms |',
  );
  stdout.writeln('|---|---|---|---|---|---|---:|---|');
  final rows = <String>[], bursts = <String>[];
  for (final name in [
    'pocket_left_loop',
    'pocket_left_2',
    'pocket_right_loop',
    'pocket_right_2',
  ]) {
    final data = TraceReplayData.parse(
      await File('traces/$name.jsonl').readAsString(),
    );
    final start = data.timing.firstTimestampMs!,
        end = data.timing.lastTimestampMs!;
    final centre = start + (end - start) ~/ 2;
    final first = _meanGravity(data, start, start + 2000);
    final middle = _meanGravity(data, centre - 1000, centre + 1000);
    final rotation = _rotation(await harness.loadTrace('traces/$name.jsonl'));
    String vector(_MeanGravity m) => m.count == 0
        ? 'NA'
        : '[${m.vector.map((v) => v.toStringAsFixed(4)).join(', ')}]';
    String near(_MeanGravity m) =>
        m.count == 0 ? 'NA' : (100 * m.nearCount / m.count).toStringAsFixed(1);
    rows.add(
      '| $name | ${vector(first)} | [${_time(centre - 1000, data)},${_time(centre + 1000, data)}) | '
      '${vector(middle)} | ${first.count}/${middle.count} | '
      '${near(first)}/${near(middle)} | ${_n(rotation.net)} | ${rotation.gaps}/${rotation.maxGap} |',
    );
    for (final b in rotation.bursts) {
      bursts.add(
        '| $name | ${_time(b.start, data)}–${_time(b.end, data)} | '
        '${((b.end - b.start) / 1000).toStringAsFixed(3)} | ${_n(b.angle)} |',
      );
    }
    final direction = rotation.net < 0
        ? 'negative/right'
        : rotation.net > 0
        ? 'positive/left'
        : 'zero';
    stdout.writeln(
      'PROVEN $name net direction=$direction; tester labels are four right turns.',
    );
  }
  for (final row in rows) {
    stdout.writeln(row);
  }
  stdout.writeln('PROVEN every qualifying signed yaw burst:');
  stdout.writeln(
    '| trace | range s | duration s | signed integrated angle degrees |',
  );
  stdout.writeln('|---|---|---:|---:|');
  for (final row in bursts) {
    stdout.writeln(row);
  }
  stdout.writeln(
    'HYPOTHESIS: gravity orientation changes might accompany '
    'pocket handling, but averaged gravity vectors alone cannot establish '
    'a yaw sign inversion or distinguish body turns from phone motion. '
    'Compare raw signs with corrected tester labels; no sign correction applied.',
  );
}
