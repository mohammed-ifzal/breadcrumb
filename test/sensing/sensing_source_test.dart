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
        await send({'type': 'motion', 't': 1520, 'yawRate': 0, 'accel': 9});
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
