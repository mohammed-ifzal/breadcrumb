import 'dart:async';

import 'package:breadcrumb/app/screens/record_screen.dart';
import 'package:breadcrumb/core/contracts.dart' as c;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'record_screen_test.dart' as support;

/// D33: recording safety. Undo last mark, a confirm before Stop and before
/// leaving, and an explicit question before a duplicate name joins the loop.
void main() {
  late StreamController<Object> events;
  late List<c.MapGraph> saved;
  late support.MemoryWalkTrace trace;

  Future<void> open(WidgetTester tester) async {
    events = StreamController<Object>.broadcast(sync: true);
    addTearDown(events.close);
    saved = [];
    trace = support.MemoryWalkTrace();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('open-record'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RecordScreen(
                      events: events.stream,
                      traceRecorder: trace,
                      save: (map) async {
                        saved.add(map);
                        return '/maps/x.json';
                      },
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-record')));
    await tester.pumpAndSettle();
    await support.start(tester);
  }

  Future<void> walk(WidgetTester tester, int steps) async {
    for (var i = 0; i < steps; i++) {
      events.add(c.StepEvent(i));
    }
    await tester.pumpAndSettle();
  }

  Future<void> mark(WidgetTester tester, String name) async {
    await tester.ensureVisible(find.byKey(const ValueKey('place-name')));
    await tester.enterText(find.byKey(const ValueKey('place-name')), name);
    await tester.pump();
    final button = find.byKey(const ValueKey('record-mark'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final f = find.byKey(ValueKey(key));
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  List<String> placeNames(c.MapGraph m) => [
    for (final p in m.places)
      if (p.kind != c.PlaceKind.junction) p.name,
  ];

  testWidgets('Undo last mark removes the place and keeps the steps', (
    tester,
  ) async {
    await open(tester);
    expect(find.byKey(const ValueKey('record-undo')), findsNothing);
    await walk(tester, 5);
    await mark(tester, 'Cafe');
    expect(find.text('Marked place: Cafe'), findsOneWidget);
    await walk(tester, 3);
    await tapKey(tester, 'record-undo');
    expect(find.text('Removed mark: Cafe'), findsOneWidget);
    expect(find.byKey(const ValueKey('record-undo')), findsNothing);
    await tapKey(tester, 'record-stop');
    await tapKey(tester, 'stop-yes');
    final map = saved.single;
    expect(placeNames(map), ['Entrance', 'End of walk']);
    expect(map.corridors.single.steps, 8);
    expect(trace.rows.where((r) => r['type'] == 'mark').map((r) => r['note']), [
      'Cafe',
      'Undo mark: Cafe',
      'End of walk',
    ]);
  });

  testWidgets('undo of a mark with no steps after it still ends at a place', (
    tester,
  ) async {
    await open(tester);
    await walk(tester, 4);
    await mark(tester, 'A');
    await walk(tester, 4);
    await mark(tester, 'B');
    await tapKey(tester, 'record-undo');
    // A is the last mark again and nothing was walked after the undo of B
    // beyond its 4 steps, so Stop adds "End of walk" for those 4 steps.
    await tapKey(tester, 'record-stop');
    await tapKey(tester, 'stop-yes');
    expect(placeNames(saved.single), ['Entrance', 'A', 'End of walk']);
  });

  testWidgets('Stop asks first; Keep recording keeps the walk going', (
    tester,
  ) async {
    await open(tester);
    await walk(tester, 3);
    await tapKey(tester, 'record-stop');
    expect(find.text('Stop and save this map?'), findsOneWidget);
    await tapKey(tester, 'stop-no');
    expect(saved, isEmpty);
    expect(find.text('RECORDING'), findsOneWidget);
    await walk(tester, 2);
    expect(tester.widget<Text>(find.byKey(const ValueKey('record-steps'))).data, '5');
    await tapKey(tester, 'record-stop');
    await tapKey(tester, 'stop-yes');
    expect(saved, hasLength(1));
  });

  testWidgets(
    'Back during a walk asks to discard; No stays, Yes leaves unsaved',
    (tester) async {
      await open(tester);
      await walk(tester, 3);
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Discard this recording?'), findsOneWidget);
      await tapKey(tester, 'discard-no');
      expect(find.byType(RecordScreen), findsOneWidget);
      nav.maybePop();
      await tester.pumpAndSettle();
      await tapKey(tester, 'discard-yes');
      expect(find.byType(RecordScreen), findsNothing);
      expect(saved, isEmpty);
    },
  );

  testWidgets('Back after saving leaves without asking', (tester) async {
    await open(tester);
    await walk(tester, 3);
    await tapKey(tester, 'record-stop');
    await tapKey(tester, 'stop-yes');
    tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Discard this recording?'), findsNothing);
    expect(find.byType(RecordScreen), findsNothing);
  });

  testWidgets('a duplicate name asks; No marks "<name> 2" without joining', (
    tester,
  ) async {
    await open(tester);
    await walk(tester, 5);
    await mark(tester, 'Cafe');
    await walk(tester, 5);
    await mark(tester, ' cafe ');
    expect(find.text('Join the loop?'), findsOneWidget);
    await tapKey(tester, 'join-no');
    expect(find.text('Marked place: Cafe 2'), findsOneWidget);
    await walk(tester, 2);
    await mark(tester, 'Cafe');
    await tapKey(tester, 'join-no');
    expect(find.text('Marked place: Cafe 3'), findsOneWidget);
    await tapKey(tester, 'record-stop');
    await tapKey(tester, 'stop-yes');
    final map = saved.single;
    expect(placeNames(map), ['Entrance', 'Cafe', 'Cafe 2', 'Cafe 3']);
    // No corridor goes back into Cafe: the loop was not closed.
    final cafe = map.places.firstWhere((p) => p.name == 'Cafe').id;
    expect(map.corridors.where((x) => x.to == cafe), hasLength(1));
  });

  testWidgets('a duplicate name with Yes closes the loop', (tester) async {
    await open(tester);
    await walk(tester, 5);
    await mark(tester, 'Cafe');
    await walk(tester, 5);
    await mark(tester, 'Entrance');
    expect(find.text('Join the loop?'), findsOneWidget);
    await tapKey(tester, 'join-yes');
    expect(find.text('Joined to Entrance - loop closed'), findsOneWidget);
    await tapKey(tester, 'record-stop');
    await tapKey(tester, 'stop-yes');
    expect(saved.single.corridors.last.to, saved.single.start);
  });

  testWidgets('Finish at start asks first; No keeps recording', (tester) async {
    await open(tester);
    await walk(tester, 4);
    await tapKey(tester, 'record-finish-start');
    expect(find.text('Finish at Entrance?'), findsOneWidget);
    await tapKey(tester, 'finish-no');
    expect(saved, isEmpty);
    expect(find.text('RECORDING'), findsOneWidget);
    await tapKey(tester, 'record-finish-start');
    await tapKey(tester, 'finish-yes');
    expect(saved.single.corridors.single.to, saved.single.start);
  });
}
