import 'dart:async';
// Run: dart run test/sensing/turn_replay.dart --sweep
// Or:  dart run test/sensing/turn_replay.dart --rate=15 --settle=700
// Optional: --file=trace.jsonl --traces=folder --expected=file.json --angle-tolerance=15
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:breadcrumb/core/contracts.dart' show TurnEvent;
import 'package:breadcrumb/core/tuning.dart' as tuning;
import 'package:breadcrumb/sensing/turn_detector.dart';

class MotionSample {
  const MotionSample(this.t, this.yawRate);
  final int t;
  final double yawRate;
}

class TraceData {
  TraceData(this.name, this.motion, this.marks);
  final String name;
  final List<MotionSample> motion;
  final List<Map<String, Object?>> marks;
}

class ReplayResult {
  ReplayResult(this.turns, this.settled);
  final List<TurnEvent> turns;
  final List<TurnEvent> settled;
}

Future<TraceData> loadTrace(String path) async {
  final file = File(path);
  final lines = await file.readAsLines();
  final motion = <MotionSample>[];
  final marks = <Map<String, Object?>>[];
  for (var i = 0; i < lines.length; i++) {
    try {
      final row = Map<String, Object?>.from(jsonDecode(lines[i]) as Map);
      if (i == 0 && row['type'] != 'meta') {
        throw const FormatException('Meta must be first');
      }
      if (row['type'] == 'motion') {
        final t = row['t'] as num;
        final rate = row['yawRate'] as num;
        if (!t.isFinite || t < 0 || !rate.isFinite) {
          throw const FormatException('Invalid motion');
        }
        motion.add(MotionSample(t.toInt(), rate.toDouble()));
      } else if (row['type'] == 'mark') {
        marks.add(row);
      }
    } catch (error) {
      throw FormatException('$path line ${i + 1}: $error');
    }
  }
  if (lines.isEmpty) throw FormatException('$path: empty trace');
  return TraceData(file.uri.pathSegments.last, motion, marks);
}

Future<Map<String, List<double>>> loadExpectedTurns(String path) async {
  final file = File(path);
  if (!await file.exists()) return {};
  final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  return json.map(
    (name, values) => MapEntry(name, [
      for (final value in values as List) _finiteAngle(value),
    ]),
  );
}

double _finiteAngle(Object? value) {
  if (value is! num || !value.isFinite) {
    throw const FormatException('Expected angles must be finite numbers');
  }
  return value.toDouble();
}

ReplayResult replay(
  TraceData trace, {
  required double turnRateMin,
  required int turnSettleMs,
}) {
  final turns = <TurnEvent>[];
  final candidates = <TurnEvent>[];
  final detector = TurnDetector(
    turnRateMin: turnRateMin,
    turnSettleMs: turnSettleMs,
    onSettled: (t, angle) => candidates.add(TurnEvent(t, angle)),
  );
  for (final sample in trace.motion) {
    final event = detector.onMotion(sample.t, sample.yawRate);
    if (event != null) turns.add(event);
  }
  // Do not append synthetic quiet samples: an unfinished turn stays unfinished.
  return ReplayResult(turns, candidates);
}

class TurnScore {
  const TurnScore(
    this.matched,
    this.falseOrSplit,
    this.missed,
    this.totalError,
    this.maxMatchedError,
  );
  final int matched;
  final int falseOrSplit;
  final int missed;
  final double totalError;
  final double maxMatchedError;
  double? get meanMatchedError => matched == 0 ? null : totalError / matched;
}

class _Cell {
  const _Cell(this.matched, this.error, this.maxError);
  final int matched;
  final double error;
  final double maxError;
}

_Cell _better(_Cell a, _Cell b) =>
    b.matched > a.matched || (b.matched == a.matched && b.error < a.error)
    ? b
    : a;

/// One-to-one ordered angle matches, inclusive of the explicit tolerance.
/// Unmatched detections are the requested combined false/split benchmark count;
/// that category alone cannot establish the physical cause of a bad angle.
TurnScore scoreTurns(
  List<double> expected,
  List<TurnEvent> detected, {
  double angleTolerance = 15,
  bool directionsOnly = false,
}) {
  if (!angleTolerance.isFinite || angleTolerance < 0) {
    throw ArgumentError.value(angleTolerance);
  }
  final table = List.generate(
    expected.length + 1,
    (_) => List.filled(detected.length + 1, const _Cell(0, 0, 0)),
  );
  for (var i = expected.length - 1; i >= 0; i--) {
    for (var j = detected.length - 1; j >= 0; j--) {
      var best = _better(table[i + 1][j], table[i][j + 1]);
      final error = (expected[i] - detected[j].angle).abs();
      if (directionsOnly
          ? expected[i].sign == detected[j].angle.sign
          : error <= angleTolerance) {
        final rest = table[i + 1][j + 1];
        best = _better(
          best,
          _Cell(
            rest.matched + 1,
            rest.error + error,
            math.max(rest.maxError, error),
          ),
        );
      }
      table[i][j] = best;
    }
  }
  final best = table[0][0];
  return TurnScore(
    best.matched,
    detected.length - best.matched,
    expected.length - best.matched,
    best.error,
    best.maxError,
  );
}

void _confirmMarks(TraceData trace, List<double> expected) {
  final directions = <int>[];
  for (final mark in trace.marks) {
    final note = mark['note']?.toString().trim().toLowerCase();
    if (note == 'right turn') directions.add(-1);
    if (note == 'left turn') directions.add(1);
  }
  if (directions.isNotEmpty &&
      (directions.length != expected.length ||
          List.generate(
            expected.length,
            (i) => expected[i].sign != directions[i],
          ).any((v) => v))) {
    throw FormatException(
      '${trace.name}: expected labels disagree with the direction marks; not scoring',
    );
  }
}

String _number(num? value) => value == null ? 'NA' : value.toStringAsFixed(2);

class _Summary {
  _Summary(this.rate, this.settle);
  final double rate;
  final int settle;
  int matched = 0, extra = 0, missed = 0, labelled = 0;
  int above75 = 0, targets = 0;
  int straightWalks = 0, straightTurns = 0;
  bool get allAtLeast75 => above75 >= targets && targets > 0;
  double error = 0;
  double get meanError => matched == 0 ? double.infinity : error / matched;
}

String currentReplayWork = 'not started';

Future<void> main(List<String> args) async {
  try {
    final options = <String, String>{};
    for (final arg in args) {
      if (arg == '--sweep') {
        options['sweep'] = 'true';
        continue;
      }
      final split = arg.indexOf('=');
      if (!arg.startsWith('--') || split < 0) {
        throw ArgumentError('Use --name=value arguments');
      }
      options[arg.substring(2, split)] = arg.substring(split + 1);
    }
    final folder = Directory(options['traces'] ?? 'traces');
    final files =
        folder
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.jsonl'))
            .where(
              (f) =>
                  options['file'] == null ||
                  f.uri.pathSegments.last == options['file'],
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    if (files.isEmpty) throw StateError('No JSONL traces in ${folder.path}');
    final traces = <TraceData>[];
    for (final file in files) {
      currentReplayWork = 'loading ${file.path}';
      stdout.writeln('PROGRESS $currentReplayWork');
      traces.add(await loadTrace(file.path));
    }
    final expected = await loadExpectedTurns(
      options['expected'] ??
          '${folder.path}${Platform.pathSeparator}expected_turns.json',
    );
    final tolerance = double.parse(options['angle-tolerance'] ?? '15');
    for (final trace in traces) {
      if (expected[trace.name] case final labels?) _confirmMarks(trace, labels);
    }
    final sweep =
        options['sweep'] == 'true' ||
        (!options.containsKey('rate') && !options.containsKey('settle'));
    final rates = sweep
        ? [10.0, 15.0, 20.0, 25.0, 30.0]
        : [double.parse(options['rate'] ?? '${tuning.turnRateMin}')];
    final settles = sweep
        ? [300, 500, 700, 900, 1200]
        : [int.parse(options['settle'] ?? '${tuning.turnSettleMs}')];
    stdout.writeln(
      'Labels come only from expected_turns.json; ordered one-to-one tolerance +/-$tolerance deg. NA = unlabelled. No synthetic tail is appended.',
    );
    stdout.writeln(
      '| trace | rate | settle | angles | >=75 | min signed | max signed | min abs | max abs | F/S | missed | mean matched error |',
    );
    stdout.writeln(
      '|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|',
    );
    final summaries = <_Summary>[];
    final baselineResults = <String, ReplayResult>{};
    var completedPairs = 0;
    for (final rate in rates) {
      for (final settle in settles) {
        final summary = _Summary(rate, settle);
        for (final trace in traces) {
          currentReplayWork = 'rate=$rate settle=$settle trace=${trace.name}';
          stdout.writeln('PROGRESS starting $currentReplayWork');
          final result = replay(trace, turnRateMin: rate, turnSettleMs: settle);
          if (rate == tuning.turnRateMin && settle == tuning.turnSettleMs) {
            baselineResults[trace.name] = result;
          }
          final angles = result.turns.map((e) => e.angle).toList();
          final magnitudes = angles.map((a) => a.abs()).toList();
          final labels = expected[trace.name];
          final score = labels == null
              ? null
              : scoreTurns(
                  labels,
                  result.turns,
                  angleTolerance: tolerance,
                  directionsOnly: true,
                );
          if (score != null) {
            if (labels!.isEmpty) {
              summary.straightWalks++;
              summary.straightTurns += result.turns.length;
            } else {
              summary.labelled++;
              summary.above75 += magnitudes.where((a) => a >= 75).length;
            }
            summary.matched += score.matched;
            summary.extra += math.max(0, result.turns.length - labels.length);
            summary.targets += labels.length;
            summary.missed += score.missed;
            summary.error += score.totalError;
          }
          stdout.writeln(
            '| ${trace.name} | $rate | $settle | ${angles.map(_number).join(', ')} | ${magnitudes.where((a) => a >= 75).length} | '
            '${_number(angles.isEmpty ? null : angles.reduce(math.min))} | ${_number(angles.isEmpty ? null : angles.reduce(math.max))} | '
            '${_number(magnitudes.isEmpty ? null : magnitudes.reduce(math.min))} | ${_number(magnitudes.isEmpty ? null : magnitudes.reduce(math.max))} | '
            '${score?.falseOrSplit ?? 'NA'} | ${score?.missed ?? 'NA'} | ${_number(score?.meanMatchedError)} |',
          );
          for (final turn in result.turns) {
            stdout.writeln(
              'TURN ${trace.name} rate=$rate settle=$settle t=${turn.t} angle=${_number(turn.angle)}',
            );
          }
          if (trace.motion.isEmpty) {
            stdout.writeln(
              'NOTE ${trace.name}: no raw motion, not replayable for turn calibration',
            );
          }
        }
        summaries.add(summary);
        completedPairs++;
        stdout.writeln(
          'PROGRESS finished pair $completedPairs/${rates.length * settles.length}: rate=$rate settle=$settle',
        );
        // Yield between finite pairs so the test timeout can report active work.
        await Future<void>.delayed(Duration.zero);
      }
    }
    final labelled = summaries.where((s) => s.labelled > 0).toList()
      ..sort((a, b) {
        var order = a.straightTurns.compareTo(b.straightTurns);
        if (order == 0) order = a.extra.compareTo(b.extra);
        if (order == 0) {
          order = (b.allAtLeast75 ? 1 : 0).compareTo(a.allAtLeast75 ? 1 : 0);
        }
        if (order == 0) order = a.missed.compareTo(b.missed);
        if (order == 0) order = a.meanError.compareTo(b.meanError);
        return order;
      });
    if (labelled.isNotEmpty) {
      final accuracyBest = labelled.first;
      final close =
          labelled
              .where(
                (s) =>
                    s.straightTurns == accuracyBest.straightTurns &&
                    s.extra == accuracyBest.extra &&
                    s.allAtLeast75 == accuracyBest.allAtLeast75 &&
                    s.missed == accuracyBest.missed &&
                    s.meanError <= accuracyBest.meanError + 1,
              )
              .toList()
            ..sort((a, b) {
              final order = b.rate.compareTo(a.rate);
              return order == 0 ? a.settle.compareTo(b.settle) : order;
            });
      final best = close.first;
      stdout.writeln(
        'RECOMMEND provisional rate=${best.rate}, settle=${best.settle}: matched=${best.matched}, extras=${best.extra}, >=75=${best.above75}/${best.targets}, missed=${best.missed}, mean_error=${_number(best.meanError)}; ${best.labelled} turn walks, ${best.straightWalks} straight walks, straight_turns=${best.straightTurns}. Accuracy minimum=${_number(accuracyBest.meanError)}; close means within 1 degree, prefer higher rate then shorter settle. Production tuning unchanged.',
      );
    } else {
      stdout.writeln(
        'No turn-accuracy recommendation: no labelled turn walks in this selection.',
      );
    }
    for (final trace in traces) {
      final baseline = baselineResults[trace.name];
      if (baseline == null) continue;
      final discarded = baseline.settled
          .where((e) => e.angle.abs() < tuning.turnMinAngle)
          .map((e) => e.angle.abs())
          .toList();
      stdout.writeln(
        'DIAGNOSTIC ${trace.name}: baseline reported=${baseline.turns.length}, largest discarded candidate=${_number(discarded.isEmpty ? null : discarded.reduce(math.max))} deg',
      );
      for (final turn in baseline.turns) {
        final nextMarks = trace.marks
            .where(
              (m) =>
                  m['t'] is num &&
                  (m['t'] as num) > turn.t &&
                  (m['note'] == 'left turn' || m['note'] == 'right turn'),
            )
            .toList();
        if (nextMarks.isEmpty) continue;
        final end = (nextMarks.first['t'] as num).toInt();
        var net = 0.0;
        for (var i = 1; i < trace.motion.length; i++) {
          final sample = trace.motion[i];
          final dt = sample.t - trace.motion[i - 1].t;
          if (sample.t > turn.t &&
              sample.t <= end &&
              dt > 0 &&
              dt <= tuning.maxMotionGapMs) {
            net += sample.yawRate * dt / 1000;
          }
        }
        stdout.writeln(
          'TAIL after emission t=${turn.t} until mark t=$end: unfiltered signed yaw=${_number(net)} deg (measurement, not a new expected label)',
        );
      }
    }
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
