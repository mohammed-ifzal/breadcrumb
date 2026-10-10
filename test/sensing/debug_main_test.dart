import 'package:breadcrumb/sensing/debug_main.dart';
import 'package:breadcrumb/sensing/debug_screen.dart';
import 'package:breadcrumb/sensing/sensing_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('standalone sensing app builds the debug screen without errors', (
    tester,
  ) async {
    final source = _TestSensingSource();
    await tester.pumpWidget(SensingDebugApp(source: source));
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(SensingDebugScreen), findsOneWidget);
    expect(find.text('Sensing spike'), findsOneWidget);
    expect(find.text('Steps: 0'), findsOneWidget);
    expect(find.text('Mark'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(source.dispose);
    expect(tester.takeException(), isNull);
  });
}

// Keep the app smoke test independent of hardware and document-directory plugins.
class _TestSensingSource extends SensingSource {
  @override
  Stream<Object> events() => const Stream<Object>.empty();

  @override
  Future<void> startTrace(Map<String, Object?> meta) async {}
}
