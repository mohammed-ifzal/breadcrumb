import 'dart:convert';
import 'dart:io';

import 'package:breadcrumb/core/contracts.dart' as contracts;
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
  setUp(() {
    listens = 0;
    cancels = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'listen') listens++;
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
}
