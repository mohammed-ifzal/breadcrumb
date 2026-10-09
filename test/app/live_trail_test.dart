import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/trail_geometry.dart';
import 'package:breadcrumb/app/widgets/trail_view.dart';
import 'package:breadcrumb/app/wiring.dart';

/// Test helper to grow a map step by step until Teammate 2's MapBuilder lands.
class StepByStepMapBuilder {
  final List<Place> _places = [];
  final List<Corridor> _corridors = [];
  String _start = 'start';

  StepByStepMapBuilder(String startName) {
    _start = 'start';
    _places.add(Place(id: 'start', name: startName, kind: PlaceKind.start));
  }

  void addCorridorAndPlace({
    required String corridorId,
    required String from,
    required String to,
    required String placeName,
    required int steps,
    required double heading,
    PlaceKind kind = PlaceKind.place,
  }) {
    _corridors.add(Corridor(
      id: corridorId,
      from: from,
      to: to,
      steps: steps,
      heading: heading,
    ));
    _places.add(Place(id: to, name: placeName, kind: kind));
  }

  void setHere(String fromNode, int steps, double heading) {
    // Remove previous temporary _here node and open corridor if present
    _places.removeWhere((p) => p.id == hereId);
    _corridors.removeWhere((c) => c.to == hereId);

    _places.add(const Place(id: hereId, name: 'Current', kind: PlaceKind.junction));
    _corridors.add(Corridor(
      id: 'c_here',
      from: fromNode,
      to: hereId,
      steps: steps,
      heading: heading,
    ));
  }

  MapGraph build() {
    return MapGraph(
      name: 'Dynamic Map',
      start: _start,
      places: List.unmodifiable(_places),
      corridors: List.unmodifiable(_corridors),
    );
  }
}

void main() {
  testWidgets('TrailView with a zero-leg RoutePlan does not throw', (tester) async {
    const map = MapGraph(
      name: 'Test',
      start: 'start',
      places: [Place(id: 'start', name: 'Start', kind: PlaceKind.start)],
      corridors: [],
    );

    const zeroLegRoute = RoutePlan(
      legs: [],
      totalSteps: 0,
      toId: 'start',
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 300,
          child: TrailView(
            map: map,
            route: zeroLegRoute,
            position: Position(
              legIndex: 0,
              stepsAlong: 0,
              anchoredBy: AnchorSource.start,
            ),
          ),
        ),
      ),
    ));

    expect(find.byType(TrailView), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('TrailView repaints live as map grows via ValueNotifier and draws _here', (tester) async {
    final builder = StepByStepMapBuilder('Start');
    final mapNotifier = ValueNotifier<MapGraph>(builder.build());

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 400,
          child: TrailView(
            mapNotifier: mapNotifier,
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.byType(TrailView), findsOneWidget);

    // Step 1: Add corridor and junction
    builder.addCorridorAndPlace(
      corridorId: 'c1',
      from: 'start',
      to: 'j1',
      placeName: 'Junction 1',
      steps: 10,
      heading: 0,
      kind: PlaceKind.junction,
    );
    mapNotifier.value = builder.build();
    await tester.pump();

    // Step 2: Add left turn (heading 90) and destination place
    builder.addCorridorAndPlace(
      corridorId: 'c2',
      from: 'j1',
      to: 'room_a',
      placeName: 'Room A',
      steps: 15,
      heading: 90,
      kind: PlaceKind.place,
    );
    mapNotifier.value = builder.build();
    await tester.pump();

    // Step 3: Add temporary moving walker node _here (D19)
    builder.setHere('room_a', 5, 90);
    mapNotifier.value = builder.build();
    await tester.pump();

    // Verify all nodes are present in the final layout
    final finalPoints = layoutMap(mapNotifier.value);
    expect(finalPoints.any((p) => p.placeId == hereId), isTrue);

    // Heading 90 still draws to the LEFT on screen
    final painter = TrailPainter(mapNotifier.value, null, null);
    const size = Size(400, 400);
    final pJ1 = finalPoints.firstWhere((p) => p.placeId == 'j1');
    final pRoomA = finalPoints.firstWhere((p) => p.placeId == 'room_a');

    final offsetJ1 = painter.toOffset(pJ1.x, pJ1.y, size);
    final offsetRoomA = painter.toOffset(pRoomA.x, pRoomA.y, size);

    expect(offsetRoomA.dx, lessThan(offsetJ1.dx));
  });

  test('Wiring sensorEvents emits StepEvent and TurnEvent matching SensingSource.events() signature', () async {
    final wiring = Wiring.instance;
    final events = <Object>[];
    final sub = wiring.sensorEvents().listen(events.add);

    wiring.emitSimulatedEvent(const StepEvent(100));
    wiring.emitSimulatedEvent(const TurnEvent(200, 90.0));
    await Future.delayed(const Duration(milliseconds: 50));

    expect(events.length, 2);
    expect(events[0], isA<StepEvent>());
    expect(events[1], isA<TurnEvent>());
    await sub.cancel();
  });
}
