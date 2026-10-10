import 'dart:convert';
import 'dart:io';

import 'package:breadcrumb/core/contracts.dart' as contracts;
import 'package:breadcrumb/core/tuning.dart' as tuning;
import 'package:breadcrumb/sensing/raw_events.dart';
import 'package:breadcrumb/sensing/turn_detector.dart';
import 'package:breadcrumb/sensing/sensing_source.dart';
import 'package:breadcrumb/sensing/trace_recorder.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('breadcrumb/sensing');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var listens = 0;
  var cancels = 0;
  Object? listenArguments;
  setUp(() {
    listens = 0;
    cancels = 0;
    listenArguments = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'listen') {
        listens++;
        listenArguments = call.arguments;
      }
      if (call.method == 'cancel') cancels++;
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  Future<void> send(Map<String, Object?> event) async {
    await messenger.handlePlatformMessage(
      'breadcrumb/sensing',
      codec.encodeSuccessEnvelope(event),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'two Dart listeners share one native subscription and hardware steps',
    () async {
      final source = SensingSource();
      final first = <Object>[];
      final second = <Object>[];
      final a = source.events().listen(first.add);
      final b = source.events().listen(second.add);
      await Future<void>.delayed(Duration.zero);
      await send({'type': 'motion', 't': 0.0, 'yawRate': 0, 'accel': 9});
      await send({'type': 'motion', 't': 20, 'yawRate': 0, 'accel': 13});
      await send({'type': 'motion', 't': 40, 'yawRate': 0, 'accel': 9});
      expect(first, isEmpty, reason: 'fallback must not double-count hardware');
      await send({'type': 'step', 't': 50.0});
      expect((first.single as contracts.StepEvent).t, 50);
      expect(second, hasLength(1));
      expect(source.hardwareStepDetector.value, isTrue);
      expect(listens, 1);
      await a.cancel();
      expect(cancels, 0);
      await b.cancel();
      await source.dispose();
      expect(cancels, 1);
    },
  );

  test(
    'no hardware enables fallback; turns and trace preserve raw samples',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'breadcrumb-source-',
      );
      final recorder = TraceRecorder(documentsDirectory: () async => directory);
      final source = SensingSource(recorder: recorder);
      final events = <Object>[];
      final subscription = source.events().listen(events.add);
      try {
        await Future<void>.delayed(Duration.zero);
        await send({'type': 'info', 'stepDetector': false});
        expect(source.hardwareStepDetector.value, isFalse);
        await source.startTrace({'map': 'loop', 'walker': 'T2'});
        await send({'type': 'motion', 't': 0, 'yawRate': 0, 'accel': 9});
        await send({'type': 'motion', 't': 20, 'yawRate': 90, 'accel': 13});
        await send({'type': 'motion', 't': 40, 'yawRate': 90, 'accel': 9});
        for (var t = 60; t <= 1000; t += 20) {
          await send({'type': 'motion', 't': t, 'yawRate': 90, 'accel': 9});
        }
        await send({'type': 'motion', 't': 1020, 'yawRate': 0, 'accel': 9});
        for (var t = 1040; t <= 1520; t += 20) {
          await send({'type': 'motion', 't': t, 'yawRate': 0, 'accel': 9});
        }
        expect(events.whereType<contracts.StepEvent>().single.t, 20);
        expect(
          events.whereType<contracts.TurnEvent>().single.angle,
          closeTo(90, .01),
        );
        source.mark('turned left');
        await source.stopTrace();
        final file = directory
            .listSync(recursive: true)
            .whereType<File>()
            .single;
        final rows = (await file.readAsLines())
            .map((line) => jsonDecode(line))
            .toList();
        expect(rows.first['type'], 'meta');
        expect(rows.first['stepSource'], 'accel');
        expect(rows[1]['type'], 'motion');
        expect(rows.last['type'], 'mark');
        expect(rows.last['t'], greaterThanOrEqualTo(1520));
        expect(rows.last['note'], 'turned left');
      } finally {
        await subscription.cancel();
        await source.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'optional step failure keeps motion alive and enables fallback',
    () async {
      final source = SensingSource();
      final events = <Object>[];
      final errors = <Object>[];
      final sub = source.events().listen(events.add, onError: errors.add);
      try {
        await Future<void>.delayed(Duration.zero);
        await send({'type': 'motion', 't': 0, 'yawRate': 0, 'accel': 9});
        await send({'type': 'step', 't': 1});
        await send({'type': 'info', 'stepDetector': false});
        await send({'type': 'motion', 't': 20, 'yawRate': 90, 'accel': 9});
        await send({'type': 'motion', 't': 40, 'yawRate': 90, 'accel': 13});
        await send({'type': 'motion', 't': 60, 'yawRate': 90, 'accel': 9});
        await send({'type': 'step', 't': 61});
        for (var t = 80; t <= 1000; t += 20) {
          await send({'type': 'motion', 't': t, 'yawRate': 90, 'accel': 9});
        }
        for (var t = 1020; t <= 1520; t += 20) {
          await send({'type': 'motion', 't': t, 'yawRate': 0, 'accel': 9});
        }
        expect(source.hardwareStepDetector.value, isFalse);
        expect(events.whereType<contracts.StepEvent>().map((e) => e.t), [
          1,
          40,
        ]);
        expect(
          events.whereType<contracts.TurnEvent>().single.angle,
          closeTo(90, .01),
        );
        expect(errors, isEmpty);
        expect(listens, 1);
        expect(cancels, 0);
      } finally {
        await sub.cancel();
        await source.dispose();
      }
    },
  );
  test(
    'trace write failure does not interrupt sensing or repeat logs',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'breadcrumb-source-failure-',
      );
      final logs = <String>[];
      final recorder = TraceRecorder(
        documentsDirectory: () async => directory,
        logger: logs.add,
      );
      final source = SensingSource(recorder: recorder);
      final events = <Object>[];
      final errors = <Object>[];
      final sub = source.events().listen(events.add, onError: errors.add);
      try {
        await Future<void>.delayed(Duration.zero);
        await send({'type': 'motion', 't': 0, 'yawRate': 0, 'accel': 9});
        await source.startTrace({'map': 'loop', 'walker': 'T2'});
        // Serialization is a synchronous write failure, independent of disk timing.
        recorder.record({'type': 'mark', 'note': Object()});
        await send({'type': 'step', 't': 20});
        await send({'type': 'step', 't': 40});
        source.mark('after failure');
        await source.stopTrace();
        expect(events.whereType<contracts.StepEvent>(), hasLength(2));
        expect(errors, isEmpty);
        expect(logs, hasLength(1));
        expect(source.traceState.value.recording, isFalse);
        expect(source.traceState.value.path, endsWith('.jsonl'));
        expect(cancels, 0);
        // A fresh trace can be started after cleanup of the failed one.
        await source.startTrace({'map': 'retry', 'walker': 'T2'});
        expect(source.traceState.value.recording, isTrue);
        expect(source.traceState.value.error, isNull);
        await source.stopTrace();
        expect(logs, hasLength(1));
      } finally {
        await sub.cancel();
        await source.dispose();
        await directory.delete(recursive: true);
      }
    },
  );
  for (final periodMs in [333, 400, 1000]) {
    test('hardware preserves 20 steps at ${1000 / periodMs} steps/s', () async {
      final source = SensingSource();
      final events = <Object>[];
      final errors = <Object>[];
      final sub = source.events().listen(events.add, onError: errors.add);
      try {
        await Future<void>.delayed(Duration.zero);
        await send({'type': 'motion', 't': 0, 'yawRate': 0, 'accel': 9.8});
        for (var i = 1; i <= 20; i++) {
          final t = i * periodMs;
          // A delayed hardware event can arrive after a newer gyro sample.
          // Accel pulses must not be fused/double-counted in hardware mode.
          await send({
            'type': 'motion',
            't': t + 40,
            'yawRate': 90,
            'accel': 13,
          });
          await send({'type': 'step', 't': t});
          await send({
            'type': 'motion',
            't': t + 60,
            'yawRate': 0,
            'accel': 9.8,
          });
        }
        expect(events.whereType<contracts.StepEvent>().map((e) => e.t), [
          for (var i = 1; i <= 20; i++) i * periodMs,
        ]);
        expect(source.hardwareStepDetector.value, isTrue);
        expect(errors, isEmpty);
        expect(listens, 1);
        expect(cancels, 0);
      } finally {
        await sub.cancel();
        await source.dispose();
      }
    });
  }
  for (final hardware in [true, false]) {
    test('stationary turn adds no steps with hardware=$hardware', () async {
      final source = SensingSource();
      final events = <Object>[];
      final sub = source.events().listen(events.add);
      try {
        await Future<void>.delayed(Duration.zero);
        if (!hardware) await send({'type': 'info', 'stepDetector': false});
        await send({'type': 'motion', 't': 0, 'yawRate': 0, 'accel': 9.8});
        for (var t = 20; t <= 1520; t += 20) {
          await send({
            'type': 'motion',
            't': t,
            'yawRate': t <= 1000 ? 90 : 0,
            'accel': (t ~/ 20).isEven ? 9.6 : 10.0,
          });
        }
        expect(events.whereType<contracts.StepEvent>(), isEmpty);
        expect(
          events.whereType<contracts.TurnEvent>().single.angle,
          closeTo(90, .01),
        );
      } finally {
        await sub.cancel();
        await source.dispose();
      }
    });
  }
  test('native errors reach consumers without enabling fallback', () async {
    final source = SensingSource();
    final errors = <Object>[];
    final sub = source.events().listen((_) {}, onError: errors.add);
    await Future<void>.delayed(Duration.zero);
    await messenger.handlePlatformMessage(
      'breadcrumb/sensing',
      codec.encodeErrorEnvelope(
        code: 'permission_denied',
        message: 'Grant externally',
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
    expect(errors.single, isA<PlatformException>());
    expect(source.hardwareStepDetector.value, isNull);
    await sub.cancel();
    await source.dispose();
  });
  test('disposing twice waits for the same native cleanup', () async {
    final source = SensingSource();
    final sub = source.events().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    final first = source.dispose();
    final second = source.dispose();
    expect(identical(first, second), isTrue);
    await first;
    await sub.cancel();
    expect(cancels, 1);
    expect(() => source.events(), throwsStateError);
  });
  test(
    'native filter defaults and overrides use additive tuning constants',
    () async {
      final source = SensingSource();
      final sub = source.events().listen((_) {});
      await Future<void>.delayed(Duration.zero);
      expect(listenArguments, {
        'gravityFallbackLowPassEnabled': tuning.gravityFallbackLowPassEnabled,
        'gravityFallbackLowPassAlpha': tuning.gravityFallbackLowPassAlpha,
        'lightCoalescingEnabled': tuning.lightCoalescingEnabled,
      });
      await sub.cancel();
      await source.dispose();
      final rawSource = SensingSource(
        gravityFallbackLowPassEnabled: false,
        gravityFallbackLowPassAlpha: 0.5,
        lightCoalescingEnabled: false,
      );
      final rawSub = rawSource.events().listen((_) {});
      await Future<void>.delayed(Duration.zero);
      expect(
        (listenArguments as Map)['gravityFallbackLowPassEnabled'],
        isFalse,
      );
      expect((listenArguments as Map)['lightCoalescingEnabled'], isFalse);
      await rawSub.cancel();
      await rawSource.dispose();
      for (final alpha in [-0.1, 1.0, double.nan]) {
        expect(
          () => SensingSource(gravityFallbackLowPassAlpha: alpha),
          throwsArgumentError,
        );
      }
    },
  );
  test(
    'auxiliary raw samples broadcast once and do not imply hardware steps',
    () async {
      final source = SensingSource();
      final first = <Object>[], second = <Object>[], errors = <Object>[];
      final a = source.events().listen(first.add, onError: errors.add);
      final b = source.events().listen(second.add, onError: errors.add);
      try {
        await Future<void>.delayed(Duration.zero);
        await send({'type': 'info', 't': 0, 'totalRamMb': 8192});
        await send({
          'type': 'gravity',
          't': 20,
          'x': 0,
          'y': 0,
          'z': 9.8,
          'source': 'sensor',
        });
        await send({'type': 'proximity', 't': 30, 'near': true, 'cm': 0});
        await send({'type': 'light', 't': 40, 'lux': 12.5});
        expect(first.map((event) => event.runtimeType), [
          DeviceInfo,
          GravitySample,
          ProximitySample,
          LightSample,
        ]);
        expect(second, first);
        expect(source.hardwareStepDetector.value, isNull);
        expect(errors, isEmpty);
        expect(listens, 1);
        await send({'type': 'step', 't': 50});
        expect(first.whereType<contracts.StepEvent>().single.t, 50);
      } finally {
        await a.cancel();
        await b.cancel();
        await source.dispose();
      }
    },
  );
  test(
    'optional capability failures keep hardware steps and turns alive',
    () async {
      final source = SensingSource();
      final events = <Object>[], errors = <Object>[];
      final sub = source.events().listen(events.add, onError: errors.add);
      try {
        await Future<void>.delayed(Duration.zero);
        await send({
          'type': 'info',
          'gravityAvailable': false,
          'gravitySource': 'accelerometer',
          'gravityLowPassEnabled': true,
        });
        await send({'type': 'info', 'proximityAvailable': false});
        await send({'type': 'info', 'lightAvailable': false});
        expect(source.hardwareStepDetector.value, isNull);
        await send({'type': 'motion', 't': 0, 'yawRate': 0, 'accel': 9.8});
        for (var t = 20; t <= 1520; t += 20) {
          await send({
            'type': 'gravity',
            't': t,
            'x': 0,
            'y': 0,
            'z': 9.8,
            'source': 'accelerometer',
          });
          await send({
            'type': 'motion',
            't': t,
            'yawRate': t <= 1000 ? 90 : 0,
            'accel': 9.8,
          });
        }
        await send({'type': 'step', 't': 1530});
        expect(events.whereType<contracts.StepEvent>().single.t, 1530);
        expect(
          events.whereType<contracts.TurnEvent>().single.angle,
          closeTo(90, .01),
        );
        expect(source.hardwareStepDetector.value, isTrue);
        expect(events.whereType<DeviceInfo>(), hasLength(3));
        expect(errors, isEmpty);
      } finally {
        await sub.cancel();
        await source.dispose();
      }
    },
  );
  test(
    'trace keeps startup device info and every optional raw sample unchanged',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'breadcrumb-raw-source-',
      );
      final recorder = TraceRecorder(documentsDirectory: () async => directory);
      final source = SensingSource(recorder: recorder);
      final errors = <Object>[];
      final sub = source.events().listen((_) {}, onError: errors.add);
      final raw = <Map<String, Object?>>[
        {
          'type': 'gravity',
          't': 20,
          'x': 0,
          'y': 1.5,
          'z': 9.8,
          'source': 'sensor',
        },
        {'type': 'proximity', 't': 21, 'near': false, 'cm': 5.0},
        {'type': 'light', 't': 22, 'lux': 0.0},
        {'type': 'info', 't': 23, 'proximityAvailable': false},
      ];
      try {
        await Future<void>.delayed(Duration.zero);
        await send({
          'type': 'info',
          't': 0,
          'totalRamMb': 8192,
          'gravityAvailable': true,
        });
        await send({'type': 'motion', 't': 0, 'yawRate': 0, 'accel': 9.8});
        await source.startTrace({'map': 'raw', 'walker': 'T2'});
        for (final event in raw) {
          await send(event);
        }
        await source.stopTrace();
        final file = directory
            .listSync(recursive: true)
            .whereType<File>()
            .single;
        final rows = (await file.readAsLines())
            .map((line) => jsonDecode(line) as Map<String, dynamic>)
            .toList();
        expect(rows.first['type'], 'meta');
        expect(rows.first['rawSensorFilters'], {
          'gravityFallbackLowPassEnabled': tuning.gravityFallbackLowPassEnabled,
          'gravityFallbackLowPassAlpha': tuning.gravityFallbackLowPassAlpha,
          'lightCoalescingEnabled': tuning.lightCoalescingEnabled,
        });
        expect(rows[1], {
          'type': 'info',
          't': 0,
          'totalRamMb': 8192,
          'gravityAvailable': true,
        });
        expect(rows.skip(2).toList(), raw);
        expect(errors, isEmpty);
      } finally {
        await sub.cancel();
        await source.dispose();
        await directory.delete(recursive: true);
      }
    },
  );
  test('existing spike produces identical turns with auxiliary samples interleaved', () async {
    final rows = (await File('traces/spike_walk_talha.jsonl').readAsLines())
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
    final baseline = TurnDetector();
    final expected = <contracts.TurnEvent>[];
    for (final row in rows.where((row) => row['type'] == 'motion')) {
      final event = baseline.onMotion(
        (row['t'] as num).toInt(),
        (row['yawRate'] as num).toDouble(),
      );
      if (event != null) expected.add(event);
    }
    final source = SensingSource();
    final actual = <contracts.TurnEvent>[], errors = <Object>[];
    final sub = source.events().listen((event) {
      if (event is contracts.TurnEvent) actual.add(event);
    }, onError: errors.add);
    try {
      await Future<void>.delayed(Duration.zero);
      for (final row in rows) {
        if (row['type'] != 'motion') continue;
        await send({
          'type': 'gravity',
          't': row['t'],
          'x': 0,
          'y': 0,
          'z': 9.8,
        });
        await send(row);
      }
      expect(
        actual.map((e) => (e.t, e.angle)),
        expected.map((e) => (e.t, e.angle)),
      );
      expect(expected, hasLength(3));
      expect(errors, isEmpty);
    } finally {
      await sub.cancel();
      await source.dispose();
    }
  });
  test(
    'malformed optional packets do not fail motion capability or a later trace',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'breadcrumb-optional-error-',
      );
      final source = SensingSource(
        recorder: TraceRecorder(documentsDirectory: () async => directory),
      );
      final events = <Object>[], errors = <Object>[];
      final sub = source.events().listen(events.add, onError: errors.add);
      try {
        await Future<void>.delayed(Duration.zero);
        await send({
          'type': 'gravity',
          't': 20,
          'x': double.nan,
          'y': 0,
          'z': 9.8,
        });
        await send({'type': 'info', 'totalRamMb': -1});
        expect(source.hardwareStepDetector.value, isNull);
        await send({'type': 'motion', 't': 40, 'yawRate': 0, 'accel': 9.8});
        await source.startTrace({'map': 'valid-motion', 'walker': 'T2'});
        await send({'type': 'step', 't': 50});
        await source.stopTrace();
        expect(events.whereType<contracts.StepEvent>().single.t, 50);
        expect(errors, hasLength(2));
        expect(errors, everyElement(isA<FormatException>()));
        expect(source.traceState.value.error, isNull);
      } finally {
        await sub.cancel();
        await source.dispose();
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'every independently labelled walk preserves detector output with auxiliary events',
    () async {
      final labels = jsonDecode(
        await File('traces/expected_turns.json').readAsString(),
      ) as Map<String, dynamic>;
      for (final entry in labels.entries) {
        final rows = (await File('traces/${entry.key}').readAsLines()).map(
          (line) => jsonDecode(line) as Map<String, dynamic>,
        );
        final baseline = TurnDetector();
        final expected = <contracts.TurnEvent>[];
        final source = SensingSource();
        final actual = <contracts.TurnEvent>[];
        final sub = source.events().listen((event) {
          if (event is contracts.TurnEvent) actual.add(event);
        });
        try {
          await Future<void>.delayed(Duration.zero);
          for (final row in rows.where((row) => row['type'] == 'motion')) {
            final t = (row['t'] as num).toInt();
            final event = baseline.onMotion(
              t,
              (row['yawRate'] as num).toDouble(),
            );
            if (event != null) expected.add(event);
            await send({'type': 'gravity', 't': t, 'x': 0, 'y': 0, 'z': 9.8});
            await send(row);
          }
          final signs = (entry.value as List).map(
            (angle) => (angle as num).sign,
          );
          expect(
            expected.map((turn) => turn.angle.sign),
            signs,
            reason: entry.key,
          );
          expect(
            actual.map((turn) => (turn.t, turn.angle)),
            expected.map((turn) => (turn.t, turn.angle)),
            reason: entry.key,
          );
        } finally {
          await sub.cancel();
          await source.dispose();
        }
      }
    },
    skip: File('traces/expected_turns.json').existsSync() ? false : 'expected_turns.json and the labelled walks are missing from this checkout',
  );
}
