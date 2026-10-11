import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:breadcrumb/core/contracts.dart' as core;
import 'package:breadcrumb/core/turn_confirmer.dart';
import 'package:breadcrumb/core/tuning.dart' as tuning;
import 'package:breadcrumb/sensing/motion_state.dart';
import 'package:breadcrumb/sensing/placement.dart';
import 'package:breadcrumb/sensing/raw_events.dart';
import 'package:breadcrumb/sensing/sensing_gates.dart';
import 'package:breadcrumb/sensing/state_events.dart' as local;
import 'package:breadcrumb/sensing/trace_replay.dart';
import 'package:breadcrumb/sensing/turn_detector.dart';
import 'package:breadcrumb/sensing/walking_bout.dart';
import 'package:flutter_test/flutter_test.dart';

import 'turn_replay.dart' as replay;

const _names = [
  'spike_walk_talha',
  'turns_walk1_talha',
  'turns_walk2_talha',
  'straight_walk_talha',
  'look_around',
  'queue',
  'pullout',
  'curve',
  'pocket_left_loop',
  'pocket_right_loop',
  'bag_loop',
];
const _scenarios = [
  'queue',
  'look_around',
  'pullout',
  'pocket_left_loop',
  'pocket_right_loop',
  'bag_loop',
  'curve',
];
const _modes = ['A', 'A+C', 'B', 'B+C'];
String _active = 'not started';
String _n(num? n) => n == null ? 'NA' : n.toStringAsFixed(2);
String _angles(Iterable<core.TurnEvent> turns) => turns.isEmpty
    ? '[]'
    : turns.map((t) => '${t.angle >= 0 ? '+' : ''}${_n(t.angle)}').join(', ');
String _seconds(int t, _Fixture f) => ((t - f.start) / 1000).toStringAsFixed(3);

class _Input {
  _Input(this.t, this.index, this.row);
  final int t, index;
  final Map<String, Object?> row;
}

class _Fixture {
  _Fixture(this.name, this.data, this.trace, this.labels) {
    var clock = start;
    for (var i = 0; i < data.records.length; i++) {
      final row = data.records[i];
      final t = traceSampleTimeMs(row);
      if (t != null) {
        clock = math.max(clock, t);
        input.add(_Input(t, i, row));
      } else if (row['type'] == 'info') {
        // Metadata t is NOT a sample time. Preserve availability notices at the
        // preceding capture clock (start for initial info), never at info.t.
        input.add(_Input(clock, i, row));
      }
    }
    input.sort((a, b) {
      final order = a.t.compareTo(b.t);
      return order == 0 ? a.index.compareTo(b.index) : order;
    });
  }
  final String name;
  final TraceReplayData data;
  final replay.TraceData trace;
  final List<double> labels;
  final input = <_Input>[];
  int get start => data.timing.firstTimestampMs!;
  int get end => data.timing.lastTimestampMs!;
}

Future<List<_Fixture>> _load() async {
  final global = await replay.loadExpectedTurns('traces/expected_turns.json');
  final fixtures = <_Fixture>[];
  for (final name in _names) {
    _active = 'loading $name';
    final path = 'traces/$name.jsonl';
    final data = TraceReplayData.parse(await File(path).readAsString());
    final List<double> labels;
    if (global.containsKey('$name.jsonl')) {
      labels = global['$name.jsonl']!;
    } else {
      final label = jsonDecode(
        await File('traces/expected_$name.json').readAsString(),
      ) as Map<String, dynamic>;
      expect(label['trace'], '$name.jsonl');
      expect(label['steps'], isNull);
      labels = (label['turns'] as List)
          .map((v) => (v as num).toDouble())
          .toList();
    }
    fixtures.add(_Fixture(name, data, await replay.loadTrace(path), labels));
  }
  return fixtures;
}

/// Reuse the production integrator; a near rate <=30 takes its low-rate branch
/// at the original timestamp. Preserve integration/settling across near/far.
/// No inferred proximity, gates, resets on placement changes or synthetic tail.
List<core.TurnEvent> _turns(_Fixture f, {required bool adaptive}) {
  final detector = TurnDetector(turnRateMin: 15, turnSettleMs: 300);
  final proximity = f.input.where((i) => i.row['type'] == 'proximity').toList();
  var next = 0;
  var near = false;
  final turns = <core.TurnEvent>[];
  for (final sample in f.trace.motion) {
    for (; next < proximity.length; next++) {
      if (proximity[next].t > sample.t) break;
      near = proximity[next].row['near'] as bool;
    }
    final rate = adaptive && near && sample.yawRate.abs() <= 30
        ? 0.0
        : sample.yawRate;
    final turn = detector.onMotion(sample.t, rate);
    if (turn != null) turns.add(turn);
  }
  return turns;
}

int _eventTime(Object event) => switch (event) {
  core.StepEvent() => event.t,
  core.TurnEvent() => event.t,
  _ => throw StateError('Unexpected confirmation event'),
};
List<Object> _raw(_Fixture f, List<core.TurnEvent> turns) {
  // Captain's harness: hardware steps + detected turns, chronological merge.
  final events = <Object>[
    for (final i in f.input)
      if (i.row['type'] == 'step') core.StepEvent(i.t),
    ...turns,
  ];
  events.sort((a, b) => _eventTime(a).compareTo(_eventTime(b)));
  return events;
}

List<Object> _confirm(List<Object> raw) {
  final pipe = ConfirmedEvents();
  return [for (final e in raw) ...pipe.add(e), ...pipe.close()];
}

replay.TurnScore _score(_Fixture f, List<core.TurnEvent> turns) =>
    replay.scoreTurns(f.labels, turns, directionsOnly: true);

class _Totals {
  int falseTurns = 0, missed = 0, matched = 0;
  double error = 0;
  double get meanError => matched == 0 ? 0 : error / matched;
  void add(replay.TurnScore score) {
    falseTurns += score.falseOrSplit;
    missed += score.missed;
    matched += score.matched;
    error += score.totalError;
  }
}

int _rank(_Totals a, _Totals b) {
  var order = a.falseTurns.compareTo(b.falseTurns);
  if (order == 0) order = a.missed.compareTo(b.missed);
  if (order == 0) order = a.meanError.compareTo(b.meanError);
  return order;
}

void _winners(
  String group,
  List<String> names,
  Map<String, Map<String, replay.TurnScore>> scores,
) {
  final totals = {for (final mode in _modes) mode: _Totals()};
  for (final name in names) {
    for (final mode in _modes) {
      totals[mode]!.add(scores[name]![mode]!);
    }
  }
  final ordered = _modes.toList()
    ..sort((a, b) => _rank(totals[a]!, totals[b]!));
  final best = totals[ordered.first]!;
  final tied = ordered.where((mode) => _rank(totals[mode]!, best) == 0);
  stdout.writeln(
    'PROVEN WINNER $group: ${tied.join(', ')} '
    '(false=${best.falseTurns},missed=${best.missed},'
    'matched MAE=${best.matched == 0 ? 'NA' : _n(best.meanError)}). '
    'Ranking: fewer false, then fewer missed, then smaller matched MAE.',
  );
}

void _lookAround(_Fixture f, List<core.TurnEvent> candidates) {
  stdout.writeln(
    'PROVEN look_around candidate/step/mark audit (sample-relative seconds):',
  );
  for (final turn in candidates) {
    stdout.writeln(
      'PROVEN candidate ${_angles([turn])} at ${_seconds(turn.t, f)}s',
    );
  }
  for (final i in f.input.where(
    (i) => i.row['type'] == 'step' || i.row['type'] == 'mark',
  )) {
    stdout.writeln(
      'PROVEN ${i.row['type']} at ${_seconds(i.t, f)}s ${i.row['note'] ?? ''}',
    );
  }
  final pipe = ConfirmedEvents();
  for (final event in _raw(f, candidates)) {
    for (final output in pipe.add(event).whereType<core.TurnEvent>()) {
      stdout.writeln(
        'PROVEN confirmed net ${_angles([output])}; '
        'timestamp retained=${_seconds(output.t, f)}s; '
        'actually released on input ${event.runtimeType} at ${_seconds(_eventTime(event), f)}s',
      );
    }
  }
  pipe.close();
  stdout.writeln(
    'PROVEN: the only mark names the whole look-around session; there are no '
    'individual physical-motion marks. HYPOTHESIS: phone/body look-around yaw '
    'followed by walking supplied a nonzero net candidate. Which specific '
    'physical motion caused it is not identifiable from these marks/steps alone.',
  );
}

RawSensingEvent _aux(_Input i) {
  final raw = RawSensingEvent.fromJson(i.row);
  if (raw is DeviceInfo) {
    return DeviceInfo(
      t: i.t,
      proximityAvailable: raw.proximityAvailable,
      lightAvailable: raw.lightAvailable,
    );
  }
  return raw;
}

List<Object> _feed(SensingGates gates, _Input input) {
  final row = input.row;
  switch (row['type']) {
    case 'step':
      return gates.onStep(core.StepEvent(input.t));
    case 'motion':
      return gates.onMotion(input.t, (row['yawRate'] as num).toDouble());
    case 'gravity':
    case 'proximity':
    case 'light':
    case 'info':
      return gates.onRaw(_aux(input));
    default:
      return gates.advanceTo(input.t);
  }
}

List<Object> _gates(_Fixture f, {required bool enabled}) {
  final gates = SensingGates(
    useBoutGating: enabled,
    useHandlingGate: enabled,
    usePlacement: enabled,
  );
  return [
    for (final input in f.input) ..._feed(gates, input),
    ...gates.advanceTo(f.end),
  ];
}

class _BoutReport {
  int raw = 0, retro = 0, releasedInBatches = 0, tooClose = 0;
  final kept = <core.StepEvent>[];
  int get isolated => raw - kept.length - tooClose;
}

_BoutReport _bouts(_Fixture f) {
  final gate = WalkingBoutGate(useBoutGating: true);
  final report = _BoutReport();
  int? candidate, seen;
  for (final i in f.input.where((i) => i.row['type'] == 'step')) {
    report.raw++;
    // Reason audit follows the unchanged gate's candidate baseline semantics.
    if (seen != null && i.t <= seen) {
      report.tooClose++;
    } else {
      seen = i.t;
      if (candidate != null && i.t - candidate < tuning.boutMinGapMs) {
        report.tooClose++;
      } else {
        candidate = i.t;
      }
    }
    final batch = gate.onStep(core.StepEvent(i.t));
    report.kept.addAll(batch);
    report.retro += batch.where((step) => step.t < i.t).length;
    if (batch.length > 1) report.releasedInBatches += batch.length;
  }
  gate.advanceTo(f.end); // No flush of unconfirmed tails.
  return report;
}

class _Peak {
  _Peak(this.t, this.angle);
  final int t;
  final double angle;
}

List<_Peak> _gravityPeaks(_Fixture f) {
  final history = <GravitySample>[];
  final peaks = <_Peak>[];
  GravitySample? last;
  for (final i in f.input.where((i) => i.row['type'] == 'gravity')) {
    final sample = _aux(i) as GravitySample;
    if (last != null && sample.t <= last.t) continue;
    double norm(GravitySample s) =>
        math.sqrt(s.x * s.x + s.y * s.y + s.z * s.z);
    final n = norm(sample);
    if (n == 0 || !n.isFinite) continue;
    if (last != null &&
        (sample.t - last.t > tuning.maxMotionGapMs ||
            sample.source != last.source)) {
      history.clear();
    }
    history.removeWhere((p) => p.t < sample.t - tuning.handlingWindowMs);
    var peak = 0.0;
    for (final p in history) {
      final dot =
          ((p.x * sample.x + p.y * sample.y + p.z * sample.z) / (norm(p) * n))
              .clamp(-1.0, 1.0);
      peak = math.max(peak, math.acos(dot) * 180 / math.pi);
    }
    peaks.add(_Peak(sample.t, peak));
    history.add(sample);
    last = sample;
  }
  return peaks;
}

class _Episode {
  _Episode(this.start);
  final int start;
  int? end;
}

String _episodes(_Fixture f) {
  // Direct MotionStateDetector replay, no inferred accelerometer gravity.
  final motion = MotionStateDetector();
  final bouts = WalkingBoutGate();
  final transitions = <local.MotionStateEvent>[];
  void add(local.MotionStateEvent? e) {
    if (e != null) transitions.add(e);
  }

  for (final i in f.input) {
    bouts.advanceTo(i.t);
    add(motion.advanceTo(i.t, inWalkingBout: bouts.inBout));
    if (i.row['type'] == 'step') {
      bouts.onStep(core.StepEvent(i.t));
      add(motion.advanceTo(i.t, inWalkingBout: bouts.inBout));
    }
    if (i.row['type'] == 'gravity') {
      add(
        motion.onGravity(_aux(i) as GravitySample, inWalkingBout: bouts.inBout),
      );
    }
  }
  add(motion.advanceTo(f.end, inWalkingBout: bouts.inBout));
  final episodes = <_Episode>[];
  _Episode? active;
  for (final e in transitions) {
    if (e.state == local.MotionState.handling && active == null) {
      if (episodes.isNotEmpty && episodes.last.end == e.tMs) {
        active = episodes.last
          ..end = null; // merge touching same-timestamp holds
      } else {
        active = _Episode(e.tMs);
        episodes.add(active);
      }
    } else if (e.state != local.MotionState.handling && active != null) {
      active.end = e.tMs;
      active = null;
    }
  }
  final peaks = _gravityPeaks(f);
  if (episodes.isEmpty) {
    return f.input.any((i) => i.row['type'] == 'gravity')
        ? 'none'
        : 'unobserved (no gravity)';
  }
  return episodes
      .map((e) {
        final end = e.end ?? f.end;
        final during = peaks.where((p) => p.t >= e.start && p.t <= end).toList()
          ..sort((a, b) => b.angle.compareTo(a.angle));
        final peak = during.isEmpty ? null : during.first;
        final first = e.start < f.start + 3000;
        final last = end > f.end - 3000;
        return '[${_seconds(e.start, f)}..${_seconds(end, f)}${e.end == null ? ' (open at Stop)' : ''}]s '
            'peak${_n(peak?.angle)}deg@${peak == null ? 'NA' : _seconds(peak.t, f)}s '
            'first3=$first,last3=$last';
      })
      .join('; ');
}

String _placement(_Fixture f, {required bool nearOnly}) {
  final result = <local.PlacementEvent>[
    local.PlacementEvent(local.Placement.unknown, f.start),
  ];
  final detector = PlacementDetector();
  local.Placement previous = local.Placement.unknown;
  bool? near;
  int? since;
  void add(local.PlacementEvent? event) {
    if (event != null && event.placement != previous) {
      result.add(event);
      previous = event.placement;
    }
  }

  for (final i in f.input) {
    if (nearOnly) {
      if (i.row['type'] == 'proximity') {
        final value = (_aux(i) as ProximitySample).near;
        if (value != near) since = value ? i.t : null;
        near = value;
      } else if (i.row['type'] == 'info') {
        if ((_aux(i) as DeviceInfo).proximityAvailable == false) {
          near = null;
          since = null;
        }
      }
      final next = near == null
          ? local.Placement.unknown
          : near && since != null && i.t - since > tuning.pocketHoldMs
          ? local.Placement.pocket
          : local.Placement.hand;
      add(local.PlacementEvent(next, i.t));
    } else {
      final local.PlacementEvent? event;
      switch (i.row['type']) {
        case 'proximity':
          event = detector.onProximity(_aux(i) as ProximitySample);
        case 'light':
          event = detector.onLight(_aux(i) as LightSample);
        case 'info':
          event = detector.onDeviceInfo(_aux(i) as DeviceInfo);
        default:
          event = detector.advanceTo(i.t);
      }
      add(event);
    }
  }
  return result
      .map((e) => '${e.placement.name}@${_seconds(e.tMs, f)}s')
      .join(' -> ');
}

Future<void> _report() async {
  final fixtures = await _load();
  final scores = <String, Map<String, replay.TurnScore>>{};
  stdout.writeln(
    'PROVEN: 11 independent labelled traces; ordered sign-only matching. '
    'False=unmatched detection; missed=unmatched expected turn. '
    'Mean angle error is absolute error over matched turns, NA when none. '
    'No gates in Part 1; confirmation uses hardware steps and no inferred handling. '
    'A=15/300, B=30/300 recorded near otherwise15/300, C=shared '
    '${tuning.turnConfirmSteps} steps/${tuning.turnConfirmWindowMs}ms. '
    'All experiment switches are local; production unchanged.',
  );
  for (final f in fixtures) {
    _active = 'four modes ${f.name}';
    final a = _turns(f, adaptive: false), b = _turns(f, adaptive: true);
    final ac = _confirm(_raw(f, a)), bc = _confirm(_raw(f, b));
    for (final confirmed in [ac, bc]) {
      expect(
        confirmed.whereType<core.StepEvent>().map((s) => s.t),
        _raw(f, a).whereType<core.StepEvent>().map((s) => s.t),
      );
    }
    final results = {
      'A': a,
      'A+C': ac.whereType<core.TurnEvent>().toList(),
      'B': b,
      'B+C': bc.whereType<core.TurnEvent>().toList(),
    };
    scores[f.name] = {};
    stdout.writeln('PROVEN ${f.name}; expected=${f.labels}');
    stdout.writeln(
      '| mode | expected | detected signed angles | false | missed | mean angle error |',
    );
    stdout.writeln('|---|---|---|---:|---:|---:|');
    for (final mode in _modes) {
      final turns = results[mode]!;
      final score = _score(f, turns);
      scores[f.name]![mode] = score;
      stdout.writeln(
        '| $mode | ${f.labels} | ${_angles(turns)} | '
        '${score.falseOrSplit} | ${score.missed} | ${_n(score.meanMatchedError)} |',
      );
    }
    _winners(f.name, [f.name], scores);
    if (f.name == 'look_around') _lookAround(f, a);
    stdout.writeln('PROVEN PROGRESS: completed four-mode trace ${f.name}');
    await Future<void>.delayed(Duration.zero);
  }
  _winners('pocket loops', ['pocket_left_loop', 'pocket_right_loop'], scores);
  _winners('all three loops', [
    'pocket_left_loop',
    'pocket_right_loop',
    'bag_loop',
  ], scores);
  _winners('hand walks', _names.take(4).toList(), scores);
  stdout.writeln(
    'PROVEN PART 2: unchanged standalone classes, stable sample-time ordering '
    '(file order breaks ties, matching chronological replay harness). '
    'Info sample time ignored; availability applied at capture clock. '
    'Hardware path only, no accel fallback or synthetic gravity/tail. '
    'Bout thresholds ${tuning.boutMinSteps}/${tuning.boutMinGapMs}..${tuning.boutMaxGapMs}ms; '
    'handling ${tuning.handlingGravityDeg}deg/${tuning.handlingWindowMs}ms, '
    'hold${tuning.handlingHoldMs}ms; placement lux<=${tuning.pocketLuxMax} '
    'and near for >${tuning.pocketHoldMs}ms.',
  );
  stdout.writeln(
    'PROVEN BOUT TABLE: retro=earlier timestamps recovered; '
    'batch counts include each confirming current step. Dropped isolated means '
    'unconfirmed short sequence/tail, not proof that the physical step was false.',
  );
  stdout.writeln(
    '| trace | raw hardware | bout kept | unconfirmed dropped | too-close/duplicate dropped | retro earlier / initial batch total |',
  );
  stdout.writeln('|---|---:|---:|---:|---:|---|');
  for (final name in _scenarios) {
    final f = fixtures.singleWhere((f) => f.name == name);
    final stats = _bouts(f);
    stdout.writeln(
      '| $name | ${stats.raw} | ${stats.kept.length} | '
      '${stats.isolated} | ${stats.tooClose} | ${stats.retro}/${stats.releasedInBatches} |',
    );
  }
  stdout.writeln(
    'PROVEN HANDLING TABLE: each episode has 600ms unit-gravity '
    'peak angle and time. Touching holds merged; first3/last3 mean overlaps '
    'trace boundary windows. Open episodes clipped at Stop, not force-ended.',
  );
  stdout.writeln('| trace | every handling episode |');
  stdout.writeln('|---|---|');
  for (final name in _scenarios) {
    final f = fixtures.singleWhere((f) => f.name == name);
    _active = 'handling $name';
    stdout.writeln('| $name | ${_episodes(f)} |');
  }
  stdout.writeln(
    'PROVEN PLACEMENT TABLE: existing near+lux rule replay below. '
    'HYPOTHESIS near-only column is an analysis counterfactual using explicit '
    'recorded near for >2s, no invented light or proximity. Unknown retained '
    'when observations are missing. Times are first observed qualifying sample.',
  );
  stdout.writeln(
    '| trace | existing near+lux<=10 | near-only >2s (HYPOTHESIS) |',
  );
  stdout.writeln('|---|---|---|');
  for (final name in _scenarios) {
    final f = fixtures.singleWhere((f) => f.name == name);
    stdout.writeln(
      '| $name | ${_placement(f, nearOnly: false)} | ${_placement(f, nearOnly: true)} |',
    );
  }
  stdout.writeln(
    'PROVEN GATE-WIRING REPLAY: all standalone flags off versus on. '
    'Turn output uses existing GLOBAL tuning, not B or confirmer. '
    'Changed compares complete timestamp/angle sequences, not only counts.',
  );
  stdout.writeln(
    '| trace | steps raw/bout-only/all-gates | turns off/on | step sequence changed | turn sequence changed | placement when on |',
  );
  stdout.writeln('|---|---|---|---|---|---|');
  for (final f in fixtures) {
    _active = 'all gates ${f.name}';
    final off = _gates(f, enabled: false), on = _gates(f, enabled: true);
    final os = off.whereType<core.StepEvent>().map((e) => e.t).toList();
    final ns = on.whereType<core.StepEvent>().map((e) => e.t).toList();
    final ot = off.whereType<core.TurnEvent>().toList();
    final nt = on.whereType<core.TurnEvent>().toList();
    final expectedA = _turns(f, adaptive: false);
    expect(
      ot.map((t) => (t.t, t.angle)),
      expectedA.map((t) => (t.t, t.angle)),
      reason: f.name,
    );
    final stepsChanged = jsonEncode(os) != jsonEncode(ns);
    final turnsChanged =
        jsonEncode(ot.map((e) => [e.t, e.angle]).toList()) !=
        jsonEncode(nt.map((e) => [e.t, e.angle]).toList());
    stdout.writeln(
      '| ${f.name} | ${os.length}/${_bouts(f).kept.length}/${ns.length} | '
      '${_angles(ot)} / ${_angles(nt)} | $stepsChanged | $turnsChanged | '
      '${_placement(f, nearOnly: false)} |',
    );
    final observed = on
        .whereType<local.PlacementEvent>()
        .map((e) => '${e.placement.name}@${_seconds(e.tMs, f)}s')
        .join(', ');
    stdout.writeln(
      'PROVEN adapter placement changes ${f.name}: ${observed.isEmpty ? 'none (unknown)' : observed}',
    );
    await Future<void>.delayed(Duration.zero);
  }
  stdout.writeln(
    'HYPOTHESIS: implementing gates would change outputs as replayed above, '
    'but physical step losses cannot be measured because scenario step truth '
    'is null. Recorded real-walk hardware events rejected by a gate are '
    'PROVEN observations, not proof they were false detections.',
  );
}

void main() {
  test(
    'B retains state across proximity changes; C uses actual following steps',
    () {
      final data = TraceReplayData.fromRecords([
        {'type': 'meta'},
        {'type': 'proximity', 't': 0, 'near': false, 'cm': 5},
        {'type': 'proximity', 't': 500, 'near': true, 'cm': 0},
        for (var t = 0; t <= 1340; t += 20)
          {
            'type': 'motion',
            't': t,
            'yawRate': t > 0 && t <= 1000 ? 90.0 : 0.0,
            'accel': 9.8,
          },
        {'type': 'step', 't': 1400},
        {'type': 'step', 't': 1900},
      ]);
      final trace = replay.TraceData('synthetic', [
        for (var t = 0; t <= 1340; t += 20)
          replay.MotionSample(t, t > 0 && t <= 1000 ? 90 : 0),
      ], []);
      final f = _Fixture('synthetic', data, trace, [90]);
      final turns = _turns(f, adaptive: true);
      expect(turns.single.angle, closeTo(90, .0001));
      final confirmed = _confirm(_raw(f, turns));
      expect(
        confirmed.whereType<core.TurnEvent>().single.angle,
        closeTo(90, .0001),
      );
    },
  );
  test(
    'bout diagnostics distinguish delayed recovery from unconfirmed steps',
    () {
      final f = _Fixture(
        'synthetic',
        TraceReplayData.fromRecords([
          {'type': 'meta'},
          for (final t in [0, 500, 1000, 6000]) {'type': 'step', 't': t},
        ]),
        replay.TraceData('synthetic', [], []),
        [],
      );
      final stats = _bouts(f);
      expect(stats.kept.length, 3);
      expect(stats.retro, 2);
      expect(stats.releasedInBatches, 3);
      expect(stats.isolated, 1);
    },
  );
  test(
    'analysis-only combined modes and standalone gates on labelled traces',
    () async {
      await _report().timeout(
        const Duration(minutes: 2),
        onTimeout: () => throw TimeoutException('Active diagnostics: $_active'),
      );
    },
    timeout: const Timeout(Duration(seconds: 125)),
  );
}
