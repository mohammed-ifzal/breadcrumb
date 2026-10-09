import 'package:breadcrumb/app/widgets/trail_view.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/trail_geometry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('left turn (heading 90) draws toward the LEFT on screen', () {
    const map = MapGraph(
      name: 'L-Turn Map',
      start: 'start',
      places: [
        Place(id: 'start', name: 'Start', kind: PlaceKind.start),
        Place(id: 'j1', name: 'Junction 1', kind: PlaceKind.junction),
        Place(id: 'left_room', name: 'Left Room', kind: PlaceKind.place),
      ],
      corridors: [
        Corridor(id: 'c1', from: 'start', to: 'j1', steps: 10, heading: 0),
        Corridor(id: 'c2', from: 'j1', to: 'left_room', steps: 10, heading: 90),
      ],
    );

    final points = layoutMap(map);
    final pStart = points.firstWhere((p) => p.placeId == 'start');
    final pJ1 = points.firstWhere((p) => p.placeId == 'j1');
    final pLeft = points.firstWhere((p) => p.placeId == 'left_room');

    // In trail geometry, heading 90 faces -x, so pLeft.x < pJ1.x
    expect(pLeft.x, lessThan(pJ1.x));

    final painter = TrailPainter(map, null, null);
    const size = Size(400, 400);

    final startOffset = painter.toOffset(pStart.x, pStart.y, size);
    final j1Offset = painter.toOffset(pJ1.x, pJ1.y, size);
    final leftOffset = painter.toOffset(pLeft.x, pLeft.y, size);

    // Forward walk (heading 0) goes UP on screen (smaller y)
    expect(j1Offset.dy, lessThan(startOffset.dy));

    // Left turn (heading 90) bends toward the LEFT on screen (smaller x / dx)
    expect(leftOffset.dx, lessThan(j1Offset.dx));
  });

  testWidgets('TrailView widget paints map and moving dot without errors', (tester) async {
    const map = MapGraph(
      name: 'Test Map',
      start: 'start',
      places: [
        Place(id: 'start', name: 'Start', kind: PlaceKind.start),
        Place(id: 'dest', name: 'Dest', kind: PlaceKind.place),
      ],
      corridors: [
        Corridor(id: 'c1', from: 'start', to: 'dest', steps: 10, heading: 0),
      ],
    );

    const route = RoutePlan(
      legs: [Leg(corridorId: 'c1', reversed: false, heading: 0, steps: 10)],
      totalSteps: 10,
      toId: 'dest',
    );

    const position = Position(
      legIndex: 0,
      stepsAlong: 5,
      anchoredBy: AnchorSource.start,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 300,
            child: TrailView(
              map: map,
              route: route,
              position: position,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(TrailView), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
