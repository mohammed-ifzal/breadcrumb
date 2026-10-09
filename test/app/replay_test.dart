import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:breadcrumb/app/screens/replay_screen.dart';

const String sampleGoodTrace = '''
{"type": "meta", "map": "demo_map", "from": "entrance", "to": "cafe", "walker": "T2", "stepSource": "hardware"}
{"type": "motion", "t": 20, "yawRate": 0.0, "accel": 9.8}
{"type": "step", "t": 50}
{"type": "motion", "t": 80, "yawRate": 90.0, "accel": 9.8}
{"type": "mark", "t": 100, "note": "turned left"}
''';

const String sampleMalformedLineTrace = '''
{"type": "meta", "map": "demo_map", "from": "entrance", "to": "cafe", "walker": "T2"}
NOT_VALID_JSON_LINE
''';

const String sampleMissingMetaTrace = '''
{"type": "step", "t": 50}
''';

void main() {
  testWidgets('ReplayScreen displays the word REPLAY at all times', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ReplayScreen(),
    ));

    expect(find.text('REPLAY'), findsWidgets);
    expect(find.text('Replay Mode'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Pick .jsonl trace to Replay'), findsOneWidget);
  });

  testWidgets('ReplayScreen handles empty trace without crashing and shows message', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ReplayScreen(initialTraceContent: ''),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Trace file is empty.'), findsOneWidget);
    expect(find.text('REPLAY'), findsWidgets);
  });

  testWidgets('ReplayScreen handles missing meta line without crashing and shows message', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ReplayScreen(initialTraceContent: sampleMissingMetaTrace),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('first line must be type "meta"'), findsOneWidget);
    expect(find.text('REPLAY'), findsWidgets);
  });

  testWidgets('ReplayScreen handles malformed line gracefully without crashing', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ReplayScreen(initialTraceContent: sampleMalformedLineTrace),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Malformed trace line'), findsOneWidget);
    expect(find.text('REPLAY'), findsWidgets);
  });

  testWidgets('ReplayScreen replays a valid trace successfully', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ReplayScreen(initialTraceContent: sampleGoodTrace),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Replay finished.'), findsOneWidget);
    expect(find.text('REPLAY'), findsWidgets);
  });
}
