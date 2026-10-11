import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:breadcrumb/core/contracts.dart' show TurnEvent;
import 'package:breadcrumb/sensing/trace_replay.dart';
import 'package:breadcrumb/sensing/turn_detector.dart';
import 'package:flutter_test/flutter_test.dart';

import 'turn_replay.dart' as existing;

const _names = [
  'spike_walk_talha',
  'turns_walk1_talha',
  'turns_walk2_talha',
  'straight_walk_talha',
  'pocket_left_loop',
  'pocket_right_loop',
  'bag_loop',
  'curve',
  'look_around',
  'queue',
  'pullout',
];
const _loops = ['pocket_left_loop', 'pocket_right_loop', 'bag_loop'];
String _active = 'not started';

class _Fixture {
  _Fixture(this.name, this.trace, this.data, this.labels);
  final String name;
  final existing.TraceData trace;
  final TraceReplayData data;
  final List<double> labels;
}

List<Map<String, Object?>> _proximity(TraceReplayData data) =>
    data.records.where((r) => r['type'] == 'proximity').toList()
      ..sort((a, b) => (a['t'] as num).compareTo(b['t'] as num));

/// Analysis ONLY: retain one production detector's timestamp, angle and settle
/// state across proximity changes. A near sample at <=30 deg/s is represented
/// as below-threshold (zero) at the same timestamp: exactly the existing
/// detector's low-rate branch, not a dropped sample or invented proximity.
/// Missing/unknown proximity uses 15. No gates or synthetic tail are added.
List<TurnEvent> _adaptive(
  existing.TraceData trace,
  List<Map<String, Object?>> proximity,
) {
  final detector = TurnDetector(turnRateMin: 15, turnSettleMs: 300);
  final turns = <TurnEvent>[];
  var index = 0;
  var near = false;
  for (final sample in trace.motion) {
    for (; index < proximity.length; index++) {
      if ((proximity[index]['t'] as num) > sample.t) break;
      near = proximity[index]['near'] as bool;
    }
    final rate = near && sample.yawRate.abs() <= 30 ? 0.0 : sample.yawRate;
    final turn = detector.onMotion(sample.t, rate);
    if (turn != null) turns.add(turn);
  }
  return turns;
}

String _n(num? value) => value == null ? 'NA' : value.toStringAsFixed(2);
String _angles(List<TurnEvent> turns) => turns.isEmpty
    ? '[]'
    : turns.map((t) => '${t.angle >= 0 ? '+' : ''}${_n(t.angle)}').join(',');
double _net(List<TurnEvent> turns) =>
    turns.fold(0.0, (sum, turn) => sum + turn.angle);
existing.TurnScore _score(_Fixture f, List<TurnEvent> turns) =>
    existing.scoreTurns(f.labels, turns, directionsOnly: true);
bool _correct(_Fixture f, List<TurnEvent> turns) =>
    turns.length == f.labels.length &&
    List.generate(
      turns.length,
      (i) => turns[i].angle.sign == f.labels[i].sign,
    ).every((match) => match);

String _sweepCell(_Fixture f, List<TurnEvent> turns) {
  final score = _score(f, turns);
  return '${_angles(turns)}; ${score.matched}/${score.missed}; '
      '${_n(_net(turns))}/${_n(f.labels.fold<double>(0.0, (a, b) => a + b))}; '
      '${_correct(f, turns) ? 'YES' : 'no'}';
}

String _comparisonCell(_Fixture f, List<TurnEvent> turns) {
  final score = _score(f, turns);
  return '${_angles(turns)}; ${score.falseOrSplit}/${score.missed}; '
      '${_n(score.meanMatchedError)}';
}

Future<List<_Fixture>> _load() async {
  final global = await existing.loadExpectedTurns('traces/expected_turns.json');
  final fixtures = <_Fixture>[];
  for (final name in _names) {
    _active = 'loading $name';
    final jsonl = await File('traces/$name.jsonl').readAsString();
    final trace = await existing.loadTrace('traces/$name.jsonl');
    final data = TraceReplayData.parse(jsonl);
    final List<double> labels;
    if (global.containsKey('$name.jsonl')) {
      labels = global['$name.jsonl']!;
    } else {
      final expected = jsonDecode(
        await File('traces/expected_$name.json').readAsString(),
      ) as Map<String, dynamic>;
      expect(expected['trace'], '$name.jsonl');
      expect(expected['steps'], isNull);
      labels = (expected['turns'] as List)
          .map((a) => (a as num).toDouble())
          .toList();
    }
    fixtures.add(_Fixture(name, trace, data, labels));
  }
  return fixtures;
}

Future<void> _report() async {
  final fixtures = await _load();
  stdout.writeln(
    'PROVEN: 11 explicitly named labelled traces (request said 10). '
    'Existing replay/score helpers, production detector, no gates, no tail. '
    'Ordered sign-only one-to-one matches; ties minimize angle error. '
    'False=unmatched detection; missed=unmatched label; MAE over matches only '
    '(NA when none). A huge event matches at most one corner.',
  );
  final correctPairs = {for (final name in _loops) name: <String>[]};
  stdout.writeln(
    'PROVEN SWEEP: each cell = signed angles; matched/missed; '
    'detected net/expected net degrees; correct count+signs.',
  );
  stdout.writeln('| rate/settle | left pocket | right pocket | bag |');
  stdout.writeln('|---|---|---|---|');
  var pairs = 0;
  final stopwatch = Stopwatch()..start();
  for (final rate in [10.0, 15.0, 20.0, 25.0, 30.0]) {
    for (final settle in [300, 500, 700, 900, 1200]) {
      final cells = <String>[];
      for (final name in _loops) {
        _active = '$rate/$settle $name';
        if (stopwatch.elapsed > const Duration(minutes: 2)) {
          throw TimeoutException('Replay stalled at $_active');
        }
        final fixture = fixtures.singleWhere((f) => f.name == name);
        final result = existing.replay(
          fixture.trace,
          turnRateMin: rate,
          turnSettleMs: settle,
        );
        cells.add(_sweepCell(fixture, result.turns));
        if (_correct(fixture, result.turns)) {
          correctPairs[name]!.add('${rate.toInt()}/$settle');
        }
      }
      stdout.writeln('| ${rate.toInt()}/$settle | ${cells.join(' | ')} |');
      stdout.writeln('PROVEN PROGRESS: finished pair ${++pairs}/25');
      await Future<void>.delayed(Duration.zero);
    }
  }
  expect(pairs, 25);
  for (final name in _loops) {
    stdout.writeln(
      'PROVEN correct count+signs $name: ${correctPairs[name]!.join(', ')}',
    );
  }
  stdout.writeln(
    'HYPOTHESIS B: threshold 15 far/unknown, 30 near; settle 300 throughout. '
    'Uses only recorded proximity; does not reset on transitions. '
    'A is 15/300 everywhere. No production change.',
  );
  stdout.writeln(
    'PROVEN A/B replay: each cell = signed angles; false/missed; matched MAE deg.',
  );
  stdout.writeln('| trace | expected | A global 15/300 | B near 30/300 |');
  stdout.writeln('|---|---|---|---|');
  for (final f in fixtures) {
    _active = 'A/B ${f.name}';
    final a = existing
        .replay(f.trace, turnRateMin: 15, turnSettleMs: 300)
        .turns;
    final proximity = _proximity(f.data);
    final b = _adaptive(f.trace, proximity);
    if (!proximity.any((r) => r['near'] == true)) {
      expect(b.map((t) => (t.t, t.angle)), a.map((t) => (t.t, t.angle)));
    }
    stdout.writeln(
      '| ${f.name} | ${f.labels} | ${_comparisonCell(f, a)} | '
      '${_comparisonCell(f, b)} |',
    );
    stdout.writeln(
      'PROVEN ${f.name}: proximity records=${proximity.length}, '
      'near records=${proximity.where((r) => r['near'] == true).length}; '
      'B same as A=${jsonEncode(b.map((t) => [t.t, t.angle]).toList()) == jsonEncode(a.map((t) => [t.t, t.angle]).toList())}',
    );
  }
  stdout.writeln(
    'PROVEN lux: values held only after recorded light observations; '
    'median and fractions are TIME-WEIGHTED, not event-count weighted. '
    'Denominator is total recorded near time; unknown light reported separately. '
    'Cached proximity snapshots count as recorded state, not fresh sensor proof.',
  );
  stdout.writeln(
    '| pocket trace | near seconds | known-light coverage | min/median/max lux | '
    '<=10 | <=30 | <=50 |',
  );
  stdout.writeln('|---|---:|---:|---|---:|---:|---:|');
  for (final name in _loops.take(2)) {
    stdout.writeln(_luxRow(fixtures.singleWhere((f) => f.name == name)));
  }
}

String _luxRow(_Fixture f) {
  final start = f.data.timing.firstTimestampMs!;
  final end = f.data.timing.lastTimestampMs!;
  final changes =
      f.data.records
          .where((r) => r['type'] == 'proximity' || r['type'] == 'light')
          .toList()
        ..sort((a, b) => (a['t'] as num).compareTo(b['t'] as num));
  var near = false;
  double? lux;
  var clock = start;
  var nearMs = 0, knownMs = 0;
  final weighted = <(double, int)>[];
  void accumulate(int next) {
    final capped = next.clamp(start, end);
    final dt = capped - clock;
    if (dt > 0 && near) {
      nearMs += dt;
      if (lux != null) {
        knownMs += dt;
        weighted.add((lux, dt));
      }
    }
    if (capped > clock) clock = capped;
  }

  for (final r in changes) {
    accumulate((r['t'] as num).toInt());
    if (r['type'] == 'proximity') {
      near = r['near'] as bool;
    } else {
      lux = (r['lux'] as num).toDouble();
    }
  }
  accumulate(end);
  weighted.sort((a, b) => a.$1.compareTo(b.$1));
  double? median;
  var elapsed = 0;
  for (final entry in weighted) {
    elapsed += entry.$2;
    if (median == null && elapsed * 2 >= knownMs) median = entry.$1;
  }
  String fraction(double threshold) => nearMs == 0
      ? 'NA'
      : '${(100 * weighted.where((e) => e.$1 <= threshold).fold(0, (a, b) => a + b.$2) / nearMs).toStringAsFixed(2)}%';
  return '| ${f.name} | ${_n(nearMs / 1000)} | '
      '${nearMs == 0 ? 'NA' : '${_n(100 * knownMs / nearMs)}%'} | '
      '${_n(weighted.isEmpty ? null : weighted.first.$1)}/'
      '${_n(median)}/${_n(weighted.isEmpty ? null : weighted.last.$1)} | '
      '${fraction(10)} | ${fraction(30)} | ${fraction(50)} |';
}

void main() {
  test('corrected left-pocket label is independent tester truth', () async {
    final label = jsonDecode(
      await File('traces/expected_pocket_left_loop.json').readAsString(),
    ) as Map<String, dynamic>;
    expect(label['turns'], [-90, -90, -90, -90]);
    expect(label['steps'], isNull);
    expect(
      label['notes'],
      'phone in left pocket, four right turns; earlier label was wrong; '
      'short 4-step legs; step count not recorded',
    );
  });
  test(
    'analysis proxy equals fixed thresholds without dropping timestamps',
    () {
      final samples = <existing.MotionSample>[
        const existing.MotionSample(0, 0),
        for (var t = 20; t <= 4000; t += 20)
          existing.MotionSample(t, t <= 1000 ? 90 : 20),
        for (var t = 4020; t <= 4400; t += 20) existing.MotionSample(t, 0),
      ];
      final trace = existing.TraceData('synthetic', samples, []);
      for (final near in [false, true]) {
        final adaptive = _adaptive(trace, [
          {'type': 'proximity', 't': 0, 'near': near},
        ]);
        final fixed = existing
            .replay(trace, turnRateMin: near ? 30 : 15, turnSettleMs: 300)
            .turns;
        expect(
          adaptive.map((t) => (t.t, t.angle)),
          fixed.map((t) => (t.t, t.angle)),
        );
      }
    },
  );
  test('proximity transition preserves integration instead of restarting', () {
    final trace = existing.TraceData('synthetic', [
      const existing.MotionSample(0, 0),
      for (var t = 20; t <= 1000; t += 20) existing.MotionSample(t, 90),
      for (var t = 1020; t <= 1340; t += 20) existing.MotionSample(t, 0),
    ], []);
    final turns = _adaptive(trace, [
      {'type': 'proximity', 't': 500, 'near': true},
      {'type': 'proximity', 't': 800, 'near': false},
    ]);
    expect(turns.single.angle, closeTo(90, .0001));
  });
  test(
    'serial bounded existing replay and analysis-only diagnostics',
    () async {
      await _report().timeout(
        const Duration(minutes: 2),
        onTimeout: () => throw TimeoutException('Active replay: $_active'),
      );
    },
    timeout: const Timeout(Duration(seconds: 125)),
  );
}
