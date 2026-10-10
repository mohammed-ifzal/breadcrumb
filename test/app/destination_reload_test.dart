import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:breadcrumb/app/screens/destination_list_screen.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/map_json.dart';

void main() {
  group('DestinationListScreen map reload (D22)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('breadcrumb-reload-test-');
      Wiring.instance.documentsDirectoryProvider = () async => tempDir;
      Wiring.instance.isAiReady.value = true;
      Wiring.instance.map = Wiring.defaultDemoMap;
      Wiring.instance.currentPlaceId = null;
    });

    tearDown(() {
      Wiring.instance.documentsDirectoryProvider = null;
      Wiring.instance.isAiReady.value = false;
      Wiring.instance.map = Wiring.defaultDemoMap;
      Wiring.instance.currentPlaceId = null;
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets('with no maps/latest.json file, expects bundled demo map', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DestinationListScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cafe'), findsOneWidget);
      expect(find.text('Stage Side'), findsOneWidget);
      expect(find.text('Observatory Deck'), findsNothing);
    });

    testWidgets('loads maps/latest.json with distinctive place name on open without restarting', (tester) async {
      // 1. Initially with no file, open screen -> demo map
      await tester.pumpWidget(
        const MaterialApp(
          home: DestinationListScreen(key: ValueKey('first')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Observatory Deck'), findsNothing);
      expect(find.text('Cafe'), findsOneWidget);

      // 2. Write a new map to maps/latest.json (simulating RecordScreen finishing walk)
      final mapsDir = Directory('${tempDir.path}/maps');
      mapsDir.createSync(recursive: true);
      final latestJson = File('${mapsDir.path}/latest.json');

      const distinctiveMap = MapGraph(
        name: 'Space Station',
        start: 'airlock',
        places: [
          Place(id: 'airlock', name: 'Airlock Alpha', kind: PlaceKind.start),
          Place(id: 'deck', name: 'Observatory Deck', kind: PlaceKind.place),
          Place(id: 'lab', name: 'Quantum Physics Lab', kind: PlaceKind.place),
        ],
        corridors: [
          Corridor(id: 'c1', from: 'airlock', to: 'deck', steps: 14, heading: 0),
          Corridor(id: 'c2', from: 'deck', to: 'lab', steps: 22, heading: 90),
        ],
      );
      latestJson.writeAsStringSync(encodeMap(distinctiveMap));

      // 3. Open DestinationListScreen again without restarting the app
      await tester.pumpWidget(
        const MaterialApp(
          home: DestinationListScreen(key: ValueKey('second')),
        ),
      );
      await tester.pumpAndSettle();

      // 4. Expect distinctive place name in the list without restarting
      expect(find.text('Observatory Deck'), findsOneWidget);
      expect(find.text('Cafe'), findsNothing);
    });
  });
}
