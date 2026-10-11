import 'dart:io';

import 'package:breadcrumb/app/map_library.dart';
import 'package:breadcrumb/app/screens/destination_list_screen.dart';
import 'package:breadcrumb/app/screens/saved_maps_screen.dart';
import 'package:breadcrumb/app/screens/scan_screen.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/perception/mlkit_sign_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// D33: Saved maps screen and the "Where are you?" start list.
MapGraph loop(String name, List<String> marks) {
  final places = [Place(id: 'p0', name: name, kind: PlaceKind.start)];
  final corridors = <Corridor>[];
  for (var i = 0; i < marks.length; i++) {
    places.add(Place(id: 'p${i + 1}', name: marks[i], kind: PlaceKind.place));
    corridors.add(
      Corridor(
        id: 'c${i + 1}',
        from: 'p$i',
        to: 'p${i + 1}',
        steps: 10,
        heading: 90.0 * i,
      ),
    );
  }
  return MapGraph(
    name: name,
    start: 'p0',
    places: places,
    corridors: corridors,
  );
}

void main() {
  final wiring = Wiring.instance;
  late Directory docs;
  late MapLibrary library;
  late Future<Directory> Function() originalDocs;

  setUp(() async {
    docs = Directory.systemTemp.createTempSync('breadcrumb-saved-');
    library = MapLibrary(documentsDirectory: () async => docs);
    originalDocs = wiring.documentsDirectory;
    wiring.documentsDirectory = () async => docs;
  });

  tearDown(() {
    wiring.documentsDirectory = originalDocs;
    wiring.map = Wiring.defaultDemoMap;
    wiring.currentPlaceId = null;
    docs.deleteSync(recursive: true);
  });

  /// Real file I/O needs real time; pump until [done] holds (default: no
  /// spinner), then settle.
  Future<void> settleIo(WidgetTester tester, {bool Function()? done}) async {
    final ready =
        done ?? () => find.byType(CircularProgressIndicator).evaluate().isEmpty;
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (i >= 3 && ready()) break;
    }
    await tester.pumpAndSettle();
  }

  group('Saved maps', () {
    testWidgets('lists maps newest first and switches the active map', (
      tester,
    ) async {
      late SavedMap demo;
      await tester.runAsync(() async {
        demo = await library.save(
          loop('Demo loop', ['Food counter']),
          now: DateTime(2026, 10, 11, 9),
        );
        await library.save(
          loop('Test walk', ['Washroom']),
          now: DateTime(2026, 10, 11, 10),
        );
      });
      await tester.pumpWidget(
        MaterialApp(home: SavedMapsScreen(library: library)),
      );
      await settleIo(tester);
      final titles = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((t) => (t.title as Text).data)
          .toList();
      expect(titles, ['Test walk', 'Demo loop']);
      expect(find.textContaining('In use'), findsOneWidget);

      await tester.tap(find.text('Demo loop'));
      await settleIo(tester, done: () => wiring.map.name == 'Demo loop');
      expect(await tester.runAsync(library.activeId), demo.id);
      expect(wiring.map.name, 'Demo loop');
    });

    testWidgets('rename and delete from the menu', (tester) async {
      late SavedMap a;
      await tester.runAsync(() async {
        a = await library.save(
          loop('Old', ['A']),
          now: DateTime(2026, 10, 11, 9),
        );
        await library.save(loop('New', ['B']), now: DateTime(2026, 10, 11, 10));
      });
      await tester.pumpWidget(
        MaterialApp(home: SavedMapsScreen(library: library)),
      );
      await settleIo(tester);

      await tester.tap(find.byKey(ValueKey('saved-map-menu-${a.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('rename-field')),
        'Stage demo',
      );
      await tester.tap(find.byKey(const ValueKey('rename-save')));
      await settleIo(
        tester,
        done: () => find
            .descendant(
              of: find.byType(ListTile),
              matching: find.text('Stage demo'),
            )
            .evaluate()
            .isNotEmpty,
      );
      expect(find.text('Stage demo'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('saved-map-menu-${a.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete "Stage demo"?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('delete-no')));
      await settleIo(tester);
      expect(find.text('Stage demo'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('saved-map-menu-${a.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-yes')));
      await settleIo(
        tester,
        done: () => find.text('Stage demo').evaluate().isEmpty,
      );
      expect(find.text('Stage demo'), findsNothing);
      expect(find.text('New'), findsOneWidget);
      expect((await tester.runAsync(library.list))!.map((m) => m.name), [
        'New',
      ]);
    });

    testWidgets('empty library says the demo map is used', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: SavedMapsScreen(library: library)),
      );
      await settleIo(tester);
      expect(
        find.text('No recorded maps yet. Navigate uses the demo map.'),
        findsOneWidget,
      );
    });
  });

  group('Where are you?', () {
    testWidgets('Navigate opens it, nearest first from the last place, '
        'with Scan a sign', (tester) async {
      // A straight line: Desk - A - B - C, so from C the order is C, B, A, Desk.
      await tester.runAsync(() => library.save(loop('Desk', ['A', 'B', 'C'])));
      await tester.pumpWidget(
        const MaterialApp(home: DestinationListScreen(askStart: true)),
      );
      await settleIo(
        tester,
        done: () => find.text('Where are you?').evaluate().isNotEmpty,
      );
      expect(find.text('Where are you?'), findsOneWidget);
      expect(find.byKey(const ValueKey('start-scan')), findsOneWidget);
      final order = tester
          .widgetList<ListTile>(
            find.byWidgetPredicate(
              (w) =>
                  w is ListTile &&
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith('start-place-'),
            ),
          )
          .map((t) => (t.title as Text).data)
          .toList();
      expect(order, ['C', 'B', 'A', 'Desk']);

      await tester.tap(find.byKey(const ValueKey('start-place-p1')));
      await tester.pumpAndSettle();
      expect(wiring.currentPlaceId, 'p1');
      expect(find.text('Where are you?'), findsNothing);
      expect(find.text('You are at: A', findRichText: true), findsOneWidget);
    });

    testWidgets('without askStart the list does not open by itself', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: DestinationListScreen()));
      await settleIo(tester);
      expect(find.text('Where are you?'), findsNothing);
    });

    testWidgets('Scan a sign in start mode returns the matched place', (
      tester,
    ) async {
      wiring.map = loop('Desk', ['Food counter', 'Washroom']);
      wiring.signReader = MlKitSignReader(
        extractOverride: (path, script) async => 'FOOD COUNTER',
      );
      Place? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.push<Place>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ScanScreen.forStart(
                      mockCapture: () async => '/mock/sign.jpg',
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Capture & Read Sign'));
      await tester.pumpAndSettle();
      expect(result?.id, 'p1');
      expect(find.byType(ScanScreen), findsNothing);
    });

    testWidgets('Scan a sign that matches nothing stays open', (tester) async {
      wiring.map = loop('Desk', ['Food counter']);
      wiring.signReader = MlKitSignReader(
        extractOverride: (path, script) async => 'EXIT 7',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ScanScreen.forStart(mockCapture: () async => '/mock/sign.jpg'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Capture & Read Sign'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't read that, try again"), findsOneWidget);
      expect(find.byType(ScanScreen), findsOneWidget);
    });
  });
}
