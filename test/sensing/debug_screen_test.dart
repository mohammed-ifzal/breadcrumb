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
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    Future<void> send(Map<String, Object?> event) async {
      await messenger.handlePlatformMessage(
        'breadcrumb/sensing',
        const StandardMethodCodec().encodeSuccessEnvelope(event),
        (_) {},
      );
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
      await send({'type': 'motion', 't': 1000, 'yawRate': 90, 'accel': 9});
      await send({'type': 'motion', 't': 1020, 'yawRate': 0, 'accel': 9});
      await send({'type': 'motion', 't': 1520, 'yawRate': 0, 'accel': 9});
      expect(find.text('Last turn: +90.0°'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'corner');
      await tester.tap(find.text('Mark'));
      await tester.pump();
      expect(find.text('Marked: corner'), findsOneWidget);
      expect(recorder.rows.first['type'], 'meta');
      expect(recorder.rows.last['note'], 'corner');
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
  final rows = <Map<String, Object?>>[];
  bool active = false;
  @override
  Future<void> start(Map<String, Object?> meta) async {
    rows.add({...meta, 'type': 'meta'});
    active = true;
  }

  @override
  void record(Map<String, Object?> event) {
    if (active) rows.add(Map.of(event));
  }

  @override
  Future<void> stop() async {
    active = false;
  }
}
