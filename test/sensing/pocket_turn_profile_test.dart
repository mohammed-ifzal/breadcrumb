import 'dart:convert';
import 'dart:io';

import 'package:breadcrumb/core/contracts.dart' as core;
import 'package:breadcrumb/core/turn_confirmer.dart';
import 'package:breadcrumb/core/tuning.dart' as tuning;
import 'package:breadcrumb/sensing/raw_events.dart';
import 'package:breadcrumb/sensing/sensing_source.dart';
import 'package:breadcrumb/sensing/turn_detector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'turn_replay.dart' as harness;

String serialize(Iterable<core.TurnEvent> turns) => jsonEncode([
  for (final turn in turns) {'type': 'turn', 't': turn.t, 'angle': turn.angle},
]);

harness.ReplayResult run(harness.TraceData trace, bool enabled) =>
    harness.replay(
      trace,
      turnRateMin: tuning.turnRateMin,
      turnSettleMs: tuning.turnSettleMs,
      usePocketTurnProfile: enabled,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('breadcrumb/sensing');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  Future<void> send(Map<String, Object?> row) async {
    await messenger.handlePlatformMessage(
      'breadcrumb/sensing',
      codec.encodeSuccessEnvelope(row),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
  }

  Future<List<core.TurnEvent>> live(String path, bool enabled) async {
    final source = SensingSource(usePocketTurnProfile: enabled);
    final turns = <core.TurnEvent>[], errors = <Object>[];
    final subscription = source.events().listen((event) {
      if (event is core.TurnEvent) turns.add(event);
    }, onError: errors.add);
    try {
      await Future<void>.delayed(Duration.zero);
      for (final line in await File(path).readAsLines()) {
        final row = Map<String, Object?>.from(jsonDecode(line) as Map);
        if (const {
          'motion',
          'step',
          'gravity',
          'proximity',
          'light',
          'info',
        }.contains(row['type'])) {
          await send(row);
        }
      }
      expect(errors, isEmpty, reason: path);
      return turns;
    } finally {
      await subscription.cancel();
      await source.dispose();
    }
  }

  test('default is OFF and disabled live/replay bytes match frozen baseline on all 11 traces', () async {
    expect(tuning.usePocketTurnProfile, isFalse);
    final golden = jsonDecode(
      await File('traces/turn_profile_off_baseline.json').readAsString(),
    ) as Map<String, dynamic>;
    final names =
        Directory('traces')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.jsonl'))
            .map((f) => f.uri.pathSegments.last)
            .toList()
          ..sort();
    expect(names, hasLength(11));
    expect(golden.keys.toList()..sort(), names);
    for (final name in names) {
      final trace = await harness.loadTrace('traces/$name');
      final off = run(trace, false);
      expect(
        utf8.encode(serialize(off.turns)),
        utf8.encode(golden[name] as String),
        reason: 'replay $name',
      );
      expect(
        serialize(
          harness
              .replay(
                trace,
                turnRateMin: tuning.turnRateMin,
                turnSettleMs: tuning.turnSettleMs,
              )
              .turns,
        ),
        golden[name],
        reason: 'default replay $name',
      );
      expect(
        utf8.encode(serialize(await live('traces/$name', false))),
        utf8.encode(golden[name] as String),
        reason: 'LIVE $name',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  for (final entry in {
    'pocket_left_loop.jsonl': [-93.04, -74.42, -83.52, -91.74],
    'pocket_right_loop.jsonl': [-101.17, -71.98, -64.99],
  }.entries) {
    test(
      'enabled live and replay reproduce scenario B: ${entry.key}',
      () async {
        final trace = await harness.loadTrace('traces/${entry.key}');
        final on = run(trace, true).turns;
        expect(on, hasLength(entry.value.length));
        for (var i = 0; i < on.length; i++) {
          expect(on[i].angle, closeTo(entry.value[i], .01));
        }
        expect(
          serialize(await live('traces/${entry.key}', true)),
          serialize(on),
        );
      },
    );
  }
  test('enabled profile leaves all four hand walks byte-identical', () async {
    for (final name in [
      'spike_walk_talha.jsonl',
      'turns_walk1_talha.jsonl',
      'turns_walk2_talha.jsonl',
      'straight_walk_talha.jsonl',
    ]) {
      final trace = await harness.loadTrace('traces/$name');
      expect(
        serialize(run(trace, true).turns),
        serialize(run(trace, false).turns),
        reason: name,
      );
      expect(
        serialize(await live('traces/$name', true)),
        serialize(run(trace, false).turns),
        reason: 'LIVE $name',
      );
    }
  });
  test(
    'switching near and far mid-turn preserves angle and emits exactly once',
    () {
      final detector = TurnDetector(usePocketTurnProfile: true);
      final turns = <core.TurnEvent>[];
      detector.onMotion(0, 0);
      for (var t = 20; t <= 1000; t += 20) {
        if (t == 500) detector.onRaw(const ProximitySample(500, true, 0));
        if (t == 800) detector.onRaw(const ProximitySample(800, false, 5));
        final turn = detector.onMotion(t, 90);
        if (turn != null) turns.add(turn);
      }
      for (var t = 1020; t <= 1700; t += 20) {
        final turn = detector.onMotion(t, 0);
        if (turn != null) turns.add(turn);
      }
      expect(turns, hasLength(1));
      expect(turns.single.angle, closeTo(90, .0001));
    },
  );
  test('unknown and unavailable proximity select normal profile', () {
    for (final unavailable in [false, true]) {
      final detector = TurnDetector(usePocketTurnProfile: true);
      if (unavailable) {
        detector.onRaw(const ProximitySample(0, true, 0));
        detector.onRaw(const DeviceInfo(proximityAvailable: false));
      }
      detector.onMotion(0, 0);
      for (var t = 20; t <= 4000; t += 20) {
        detector.onMotion(t, 20);
      }
      core.TurnEvent? turn;
      for (var t = 4020; t <= 4400; t += 20) {
        turn = detector.onMotion(t, 0) ?? turn;
      }
      expect(turn?.angle, closeTo(80, .0001));
    }
  });
  test(
    'active pocket settling parameter is used without clearing settle state',
    () {
      final detector = TurnDetector(
        usePocketTurnProfile: true,
        turnSettleMs: 900,
        pocketTurnSettleMs: 300,
      );
      detector.onMotion(0, 0);
      for (var t = 20; t <= 1000; t += 20) {
        detector.onMotion(t, 90);
      }
      for (var t = 1020; t <= 1300; t += 20) {
        expect(detector.onMotion(t, 0), isNull);
      }
      detector.onRaw(const ProximitySample(1310, true, 0));
      final turn = detector.onMotion(1320, 0);
      expect(turn?.angle, closeTo(90, .0001));
      expect(turn?.t, 1320);
    },
  );
  test(
    'enabled profile plus confirmer keeps at least three left-pocket turns',
    () async {
      final trace = await harness.loadTrace('traces/pocket_left_loop.jsonl');
      final turns = run(trace, true).turns;
      final events = <Object>[
        ...turns,
        for (final row
            in (await File('traces/pocket_left_loop.jsonl').readAsLines()).map(
              (line) => jsonDecode(line) as Map<String, dynamic>,
            ))
          if (row['type'] == 'step') core.StepEvent((row['t'] as num).toInt()),
      ];
      int timestamp(Object e) =>
          e is core.StepEvent ? e.t : (e as core.TurnEvent).t;
      events.sort((a, b) => timestamp(a).compareTo(timestamp(b)));
      final pipe = ConfirmedEvents(
        StepTurnConfirmer(
          confirmSteps: tuning.turnConfirmSteps,
          windowMs: tuning.turnConfirmWindowMs,
        ),
      );
      final confirmed = [
        for (final e in events) ...pipe.add(e),
        ...pipe.close(),
      ].whereType<core.TurnEvent>().toList();
      expect(confirmed.length, greaterThanOrEqualTo(3));
      expect(confirmed.map((t) => t.angle), [
        closeTo(-93.04, .01),
        closeTo(-74.42, .01),
        closeTo(-83.52, .01),
      ]);
    },
  );
  test('invalid pocket parameters are rejected', () {
    expect(() => TurnDetector(pocketTurnRateMin: -1), throwsArgumentError);
    expect(
      () => TurnDetector(pocketTurnRateMin: double.nan),
      throwsArgumentError,
    );
    expect(() => TurnDetector(pocketTurnSettleMs: -1), throwsArgumentError);
  });
}
