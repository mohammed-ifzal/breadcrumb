import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:breadcrumb/core/contracts.dart' show TurnEvent;
import 'package:breadcrumb/sensing/turn_detector.dart';
import 'package:flutter_test/flutter_test.dart';

import 'turn_replay.dart' hide main;
import 'turn_replay.dart' as cli show main;

void main() {
  test('bounded 25-pair sweep with progress and active-work timeout', () async {
    final previousExitCode = exitCode;
    exitCode = 0;
    try {
      await runSweepForTest().timeout(
        const Duration(minutes: 2),
        onTimeout: () {
          throw TimeoutException('Replay stalled at: $currentReplayWork');
        },
      );
      expect(exitCode, 0);
    } finally {
      exitCode = previousExitCode;
    }
  }, timeout: const Timeout(Duration(seconds: 125)));
  test(
    'angle scoring uses ordered expected values, not detected angles as labels',
    () {
      final score = scoreTurns(
        [-90, 90, -90],
        [
          const TurnEvent(1, -87.24),
          const TurnEvent(2, 92.82),
          const TurnEvent(3, -70.75),
        ],
      );
      expect(score.matched, 2);
      expect(score.falseOrSplit, 1);
      expect(score.missed, 1);
      expect(score.maxMatchedError, closeTo(2.82, .01));
    },
  );
  test('an extra split fragment cannot match the same expected turn twice', () {
    final score = scoreTurns(
      [-90],
      [const TurnEvent(1, -90), const TurnEvent(2, -60)],
    );
    expect(score.matched, 1);
    expect(score.falseOrSplit, 1);
    expect(score.missed, 0);
  });
  test('opposite direction never matches and an empty target counts all detections', () {
    expect(scoreTurns([90], [const TurnEvent(1, -90)]).matched, 0);
    expect(scoreTurns([], [const TurnEvent(1, 90)]).falseOrSplit, 1);
  });
  test(
    'parameterized production detector exposes settled discarded candidates',
    () {
      final candidates = <double>[];
      final detector = TurnDetector(
        turnRateMin: 15,
        turnSettleMs: 700,
        onSettled: (_, angle) => candidates.add(angle),
      );
      detector.onMotion(0, 0);
      final emitted = <TurnEvent>[];
      for (var t = 20; t <= 1000; t += 20) {
        detector.onMotion(t, 90);
      }
      for (var t = 1020; t <= 1720; t += 20) {
        final event = detector.onMotion(t, 0);
        if (event != null) emitted.add(event);
      }
      expect(emitted.single.angle, closeTo(90, .01));
      expect(emitted.single.t, 1720);
      expect(candidates, [closeTo(90, .01)]);
      detector.onMotion(1740, 50);
      detector.onMotion(1760, 0);
      for (var t = 1780; t <= 2460; t += 20) {
        expect(detector.onMotion(t, 0), isNull);
      }
      expect(candidates.last, closeTo(1, .01));
    },
  );
  test('invalid replay parameters are rejected', () {
    expect(() => TurnDetector(turnRateMin: -1), throwsArgumentError);
    expect(() => TurnDetector(turnRateMin: double.nan), throwsArgumentError);
    expect(() => TurnDetector(turnSettleMs: -1), throwsArgumentError);
  });
  test(
    'real trace labels are independently supplied and match mark order',
    () async {
      final labels = await loadExpectedTurns('traces/expected_turns.json');
      final trace = await loadTrace('traces/spike_walk_talha.jsonl');
      expect(labels[trace.name], [-90, 90, -90]);
      expect(labels['turns_walk1_talha.jsonl'], [90, -90, -90]);
      expect(labels['turns_walk2_talha.jsonl'], [90, -90, -90]);
      expect(trace.marks.map((m) => m['note']), [
        'right turn',
        'left turn',
        'right turn',
      ]);
      expect(trace.motion, hasLength(2232));
    },
  );
  test(
    'straight fixture has independent empty labels and 40 hardware steps',
    () async {
      final labels = await loadExpectedTurns('traces/expected_turns.json');
      expect(labels['straight_walk_talha.jsonl'], isEmpty);
      final rows =
          (await File('traces/straight_walk_talha.jsonl').readAsLines())
              .map((line) => jsonDecode(line) as Map<String, dynamic>)
              .toList();
      expect(rows.first['type'], 'meta');
      expect(rows.where((row) => row['type'] == 'step'), hasLength(40));
      final times =
          rows
              .where((row) => row['t'] is num)
              .map((row) => (row['t'] as num).toDouble())
              .toList()
            ..sort();
      expect((times.last - times.first) / 1000, inInclusiveRange(30, 45));
      final trace = await loadTrace('traces/straight_walk_talha.jsonl');
      expect(trace.motion, isNotEmpty);
      for (final pair in [(15.0, 300), (20.0, 500), (25.0, 500)]) {
        expect(
          replay(trace, turnRateMin: pair.$1, turnSettleMs: pair.$2).turns,
          isEmpty,
          reason: 'Straight walk at ${pair.$1}/${pair.$2}',
        );
      }
    },
  );
  test('unlabelled traces are not assigned guessed ground truth', () async {
    expect(
      await loadExpectedTurns('traces/nonexistent_expected_turns.json'),
      isEmpty,
    );
  });
  test('invalid JSON reports the file and line', () async {
    final directory = await Directory.systemTemp.createTemp(
      'breadcrumb-turn-replay-',
    );
    try {
      final file = File('${directory.path}${Platform.pathSeparator}bad.jsonl');
      await file.writeAsString('{"type":"meta"}\nnot json\n');
      await expectLater(
        loadTrace(file.path),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('line 2'),
          ),
        ),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });
}

Future<void> runSweepForTest() => cli.main([
  '--sweep',
  if (Platform.environment['TURN_REPLAY_FILE'] case final file?) '--file=$file',
]);
