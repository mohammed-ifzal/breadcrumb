import 'package:breadcrumb/sensing/debug_screen.dart';
import 'package:breadcrumb/sensing/sensing_source.dart';
import 'package:breadcrumb/sensing/trace_recorder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('debug screen shows live metrics and Mark writes tester note', (
    tester,
  ) async {
    // Disk behavior is exercised separately by recorder/source integration tests.
    // The widget harness uses memory to avoid filesystem I/O in its fake clock.
    final recorder = MemoryRecorder();
    final source = SensingSource(recorder: recorder);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('breadcrumb/sensing');
    var listens = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'listen') listens++;
      return null;
    });
    Future<void> send(Map<String, Object?> event) async {
      await messenger.handlePlatformMessage(
        'breadcrumb/sensing',
        const StandardMethodCodec().encodeSuccessEnvelope(event),
        (_) {},
      );
      await tester.pump();
      await tester.pump();
    }

    try {
      await tester.pumpWidget(
        MaterialApp(home: SensingDebugScreen(source: source)),
      );
      expect(find.text('Hardware step detector: waiting'), findsOneWidget);
      await send({'type': 'motion', 't': 0, 'yawRate': 0, 'accel': 9});
      await tester.pump();
      expect(find.text('Hardware step detector: yes'), findsOneWidget);
      await send({'type': 'step', 't': 20});
      expect(find.text('Steps: 1'), findsOneWidget);
      await tester.tap(find.text('Start trace'));
      await tester.pump();
      expect(find.text(MemoryRecorder.path), findsOneWidget);
      for (var t = 20; t <= 1000; t += 20) {
        await send({'type': 'motion', 't': t, 'yawRate': 90, 'accel': 9});
      }
      await send({'type': 'motion', 't': 1020, 'yawRate': 0, 'accel': 9});
      for (var t = 1040; t <= 1520; t += 20) {
        await send({'type': 'motion', 't': t, 'yawRate': 0, 'accel': 9});
      }
      expect(find.text('Last turn: +90.0°'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'corner');
      await tester.tap(find.text('Mark'));
      await tester.pump();
      expect(find.text('Marked: corner'), findsOneWidget);
      expect(recorder.rows.first['type'], 'meta');
      expect(recorder.rows.last['note'], 'corner');
      await tester.tap(find.text('Reset'));
      await tester.pump();
      expect(find.text('Steps: 0'), findsOneWidget);
      expect(find.text('Last turn: +0.0°'), findsOneWidget);
      expect(listens, 1);
      await tester.tap(find.text('Stop trace'));
      await tester.pump();
      expect(find.text('Start trace'), findsOneWidget);
      expect(find.text(MemoryRecorder.path), findsOneWidget);
      expect(recorder.active, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(source.dispose);
    } finally {
      await tester.runAsync(source.dispose);
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
}

class MemoryRecorder extends TraceRecorder {
  static const path =
      '/data/user/0/com.teamgroza.breadcrumb/app_flutter/traces/test.jsonl';
  final rows = <Map<String, Object?>>[];
  bool active = false;
  @override
  Future<void> start(Map<String, Object?> meta) async {
    rows.add({...meta, 'type': 'meta'});
    active = true;
    state.value = const TraceState(recording: true, path: path);
  }

  @override
  void record(Map<String, Object?> event) {
    if (active) rows.add(Map.of(event));
  }

  @override
  Future<void> stop() async {
    active = false;
    state.value = const TraceState(recording: false, path: path);
  }
}
