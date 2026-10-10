import 'package:breadcrumb/app/widgets/trail_view.dart';
import 'dart:async';
import 'dart:io';

import 'package:breadcrumb/app/screens/destination_list_screen.dart';
import 'package:breadcrumb/app/screens/record_screen.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';

/// The iQOO loop bug: Home read maps/latest.json once at app start, before
/// anything was recorded, so Navigate kept the demo map after a save.
void main() {
  late Directory documents;
  final wiring = Wiring.instance;

  setUp(() async {
    TrailView.defaultAnimate = false;
    documents = await Directory.systemTemp.createTemp('breadcrumb-reload-');
    wiring.documentsDirectory = () async => documents;
    wiring.map = Wiring.defaultDemoMap;
    wiring.currentPlaceId = null;
  });

  tearDown(() async {
    TrailView.defaultAnimate = true;
    wiring.documentsDirectory = getApplicationDocumentsDirectory;
    wiring.map = Wiring.defaultDemoMap;
    wiring.currentPlaceId = null;
    await documents.delete(recursive: true);
  });

  Future<void> tapKey(WidgetTester tester, String key) async {
    final button = find.byKey(ValueKey(key));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  /// Records the loop from the iQOO test on the real RecordScreen and saves it
  /// to latest.json with the real save function.
  Future<MapGraph> recordLoop(WidgetTester tester, String start, List<String> marks) async {
    final events = StreamController<Object>.broadcast(sync: true);
    addTearDown(events.close);
    MapGraph? saved;
    var t = 0;
    await tester.pumpWidget(MaterialApp(
      home: RecordScreen(
        events: events.stream,
        save: (map) async {
          saved = map;
          return 'latest.json';
        },
      ),
    ));
    await tester.enterText(find.byKey(const ValueKey('start-name')), start);
    await tester.pump();
    await tapKey(tester, 'record-start');
    for (final mark in [...marks, null]) {
      for (var i = 0; i < 6; i++) {
        events.add(StepEvent(t += 500));
      }
      events.add(TurnEvent(t += 500, 90));
      for (var i = 0; i < 4; i++) {
        events.add(StepEvent(t += 500));
      }
      await tester.pump();
      if (mark == null) break; // walk on, then Stop adds "End of walk"
      await tester.enterText(find.byKey(const ValueKey('place-name')), mark);
      await tester.pump();
      await tapKey(tester, 'record-mark');
    }
    await tapKey(tester, 'record-stop');
    await tester.runAsync(
      () => saveLatestMap(saved!, documentsDirectory: () async => documents),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    return saved!;
  }

  Future<void> openNavigate(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: DestinationListScreen()));
      // Let the real file read in initState finish.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
  }

  testWidgets(
    'a map saved after app start shows every place in "You are at" and as destinations',
    (tester) async {
      // App start: nothing recorded yet, so the demo map stays.
      expect(await tester.runAsync(wiring.reloadActiveMap), isFalse);
      expect(wiring.map.name, 'Demo Map');

      final map = await recordLoop(
        tester,
        'team groza table',
        ['food counter', 'washroom'],
      );
      final names = ['team groza table', 'food counter', 'washroom', 'End of walk'];
      expect(
        map.places.where((p) => p.kind != PlaceKind.junction).map((p) => p.name),
        names,
      );

      await openNavigate(tester);

      // D23: "You are at" defaults to the last place; the rest are destinations.
      expect(find.text('You are at: End of walk'), findsOneWidget);
      for (final name in names.take(3)) {
        expect(find.text(name), findsOneWidget, reason: '$name as a destination');
      }
      expect(find.text('Cafe'), findsNothing, reason: 'demo map must be gone');

      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      for (final name in names) {
        expect(
          find.descendant(of: find.byType(ListTile), matching: find.text(name)),
          findsOneWidget,
          reason: '$name in "You are at"',
        );
      }
    },
  );

  testWidgets(
    'reopening Navigate keeps the "You are at" choice until a newer map is saved',
    (tester) async {
      await recordLoop(tester, 'team groza table', ['food counter']);
      await openNavigate(tester);
      final table = wiring.map.places.firstWhere((p) => p.name == 'team groza table');
      wiring.currentPlaceId = table.id;

      await tester.pumpWidget(const SizedBox.shrink());
      await openNavigate(tester);
      expect(find.text('You are at: team groza table'), findsOneWidget);

      await recordLoop(tester, 'gate', ['stage']);
      await openNavigate(tester);
      expect(find.text('You are at: End of walk'), findsOneWidget);
      expect(find.text('gate'), findsOneWidget);
      expect(find.text('stage'), findsOneWidget);
      expect(find.text('food counter'), findsNothing);
    },
  );
}
