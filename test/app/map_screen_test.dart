import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:breadcrumb/app/screens/home_screen.dart';
import 'package:breadcrumb/app/screens/destination_list_screen.dart';
import 'package:breadcrumb/app/screens/map_screen.dart';
import 'package:breadcrumb/app/screens/navigate_screen.dart';
import 'package:breadcrumb/app/widgets/trail_view.dart';
import 'package:breadcrumb/app/theme.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/core/contracts.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync();
    Wiring.instance.documentsDirectory = () async => tempDir;
    Wiring.instance.map = Wiring.defaultDemoMap;
    Wiring.instance.currentPlaceId = 'entrance';
    Wiring.instance.resetAiForTesting();
    Wiring.instance.aiStatus.value = const AiStatus.ready();
    Wiring.instance.isAiReady.value = true;
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
    Wiring.instance.documentsDirectory = getApplicationDocumentsDirectory;
    Wiring.instance.map = Wiring.defaultDemoMap;
    Wiring.instance.currentPlaceId = null;
    Wiring.instance.resetAiForTesting();
  });

  Future<void> pumpScreen(WidgetTester tester, Widget child, {TextScaler? textScaler, Size? size}) async {
    tester.view.physicalSize = size ?? const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: BreadcrumbTheme.themeData,
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: textScaler ?? TextScaler.noScaling,
          ),
          child: c!,
        ),
        home: child,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('map screen renders place labels and the summary line for demo map', (tester) async {
    await pumpScreen(tester, const MapScreen());

    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.byType(TrailView), findsOneWidget);
    expect(find.text('Floor map'), findsOneWidget);
    // Demo map: entrance, cafe, stage, restroom = 4 places; corridors = 10+15+20+12+8 = 65 steps
    expect(find.text('4 places · 65 steps · Demo map'), findsOneWidget);
  });

  testWidgets('map screen renders summary line for recorded walk', (tester) async {
    const recordedMap = MapGraph(
      name: 'office walk',
      start: 'desk',
      places: [
        Place(id: 'desk', name: 'Office Desk', kind: PlaceKind.start),
        Place(id: 'j1', name: 'Corner', kind: PlaceKind.junction),
        Place(id: 'water', name: 'Water Point', kind: PlaceKind.place),
        Place(id: 'end', name: 'End of walk', kind: PlaceKind.place),
      ],
      corridors: [
        Corridor(id: 'c1', from: 'desk', to: 'j1', steps: 15, heading: 0),
        Corridor(id: 'c2', from: 'j1', to: 'water', steps: 25, heading: 90),
        Corridor(id: 'c3', from: 'water', to: 'end', steps: 20, heading: 90),
      ],
    );

    Wiring.instance.map = recordedMap;
    Wiring.instance.currentPlaceId = 'desk';

    await pumpScreen(tester, const MapScreen());

    // 3 non-junction places, 60 total steps
    expect(find.text('3 places · 60 steps · recorded in one walk'), findsOneWidget);
  });

  testWidgets('route preview highlights and shows steps and turn counts', (tester) async {
    await pumpScreen(tester, const MapScreen());

    // Start defaults to Entrance (set in setUp)
    // Tap destination selector card
    await tester.tap(find.text('Choose destination'));
    await tester.pumpAndSettle();

    // Select Cafe
    await tester.tap(find.text('Cafe'));
    await tester.pumpAndSettle();

    // Route from entrance to cafe in defaultDemoMap:
    // c1 (entrance -> j1, 10 steps, heading 0)
    // c2 (j1 -> cafe, 15 steps, heading 90)
    // Turn between 0 and 90 is 90 degrees >= straightTolerance (30 deg) -> 1 turn
    // Total steps = 25 steps
    expect(find.text('Cafe · 25 steps · 1 turn'), findsOneWidget);

    // Now change destination to Restroom:
    // c1 (15 steps, heading 0), c3 (20 steps, heading 0), c5 (8 steps, heading 0)
    // All heading 0 -> 0 turns! Total steps = 43 steps
    await tester.tap(find.text('Change').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Restroom'));
    await tester.pumpAndSettle();

    expect(find.text('Restroom · 43 steps · 0 turns'), findsOneWidget);
  });

  testWidgets('same place shows already at and disables Start', (tester) async {
    await pumpScreen(tester, const MapScreen());

    // Start is Entrance. Choose Entrance as destination.
    await tester.tap(find.text('Choose destination'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Entrance'));
    await tester.pumpAndSettle();

    expect(find.text("You're already at Entrance"), findsOneWidget);

    // Start button is disabled
    final startButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Start'),
    );
    expect(startButton.onPressed, isNull);
  });

  testWidgets('disconnected place throws ArgumentError and shows message', (tester) async {
    const disconnectedMap = MapGraph(
      name: 'broken map',
      start: 'p1',
      places: [
        Place(id: 'p1', name: 'Island A', kind: PlaceKind.start),
        Place(id: 'p2', name: 'Island B', kind: PlaceKind.place),
      ],
      corridors: [],
    );

    Wiring.instance.map = disconnectedMap;
    Wiring.instance.currentPlaceId = 'p1';

    await pumpScreen(tester, const MapScreen());

    // Set start to Island A
    await tester.tap(find.text('Change').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Island A'));
    await tester.pumpAndSettle();

    // Set destination to Island B
    await tester.tap(find.text('Choose destination'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Island B'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No route'), findsOneWidget);
  });

  testWidgets('Start opens Navigate with chosen start place and destination', (tester) async {
    await pumpScreen(tester, const MapScreen());

    // Start is Entrance. Set destination to Cafe.
    await tester.tap(find.text('Choose destination'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cafe'));
    await tester.pumpAndSettle();

    // Tap Start
    await tester.tap(find.widgetWithText(ElevatedButton, 'Start'));
    await tester.pumpAndSettle();

    expect(find.byType(NavigateScreen), findsOneWidget);
    expect(Wiring.instance.effectiveCurrentPlaceId, 'entrance');
  });

  testWidgets('Home screen shows View floor map button and navigates to MapScreen', (tester) async {
    await pumpScreen(tester, const HomeScreen());

    await tester.scrollUntilVisible(find.text('View floor map'), 200);
    expect(find.text('View floor map'), findsOneWidget);

    await tester.tap(find.text('View floor map'));
    await tester.pumpAndSettle();

    expect(find.byType(MapScreen), findsOneWidget);
  });

  testWidgets('Destination screen shows View floor map button and navigates to MapScreen', (tester) async {
    await pumpScreen(tester, const DestinationListScreen());

    expect(find.text('View floor map'), findsOneWidget);

    await tester.tap(find.text('View floor map'));
    await tester.pumpAndSettle();

    expect(find.byType(MapScreen), findsOneWidget);
  });

  testWidgets('MapScreen fits at 411x891 with text scale 1.3 with no overflow', (tester) async {
    await pumpScreen(
      tester,
      const MapScreen(),
      textScaler: const TextScaler.linear(1.3),
      size: const Size(411 * 3, 891 * 3),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.text('Floor map'), findsOneWidget);
    expect(find.byType(TrailView), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('MapScreen fits at 360x640 with text scale 1.3 with no overflow', (tester) async {
    await pumpScreen(
      tester,
      const MapScreen(),
      textScaler: const TextScaler.linear(1.3),
      size: const Size(360 * 2, 640 * 2),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(MapScreen), findsOneWidget);

    // Scroll down to verify bottom contents render without clipping
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Start'), findsOneWidget);
  });
}
