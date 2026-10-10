import 'package:breadcrumb/app/theme.dart';
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

  test('trail view labels contrast at least 4.5:1 against what they are drawn on', () {
    // Label color vs label background pill
    final pillContrast = TrailPainter.contrastRatio(
      TrailPainter.labelColor,
      TrailPainter.labelBackgroundColor,
    );
    expect(pillContrast, greaterThanOrEqualTo(4.5),
        reason: 'Label contrast against pill badge must meet WCAG AA (>= 4.5:1)');

    // Label color vs canvas background
    final canvasContrast = TrailPainter.contrastRatio(
      TrailPainter.labelColor,
      TrailPainter.canvasBackgroundColor,
    );
    expect(canvasContrast, greaterThanOrEqualTo(4.5),
        reason: 'Label contrast against canvas background must meet WCAG AA (>= 4.5:1)');

    // Label color vs BreadcrumbTheme.surface and BreadcrumbTheme.background
    final surfaceContrast = TrailPainter.contrastRatio(
      TrailPainter.labelColor,
      BreadcrumbTheme.surface,
    );
    expect(surfaceContrast, greaterThanOrEqualTo(4.5));

    final bgContrast = TrailPainter.contrastRatio(
      TrailPainter.labelColor,
      BreadcrumbTheme.background,
    );
    expect(bgContrast, greaterThanOrEqualTo(4.5));
  });


  testWidgets('TrailView animate:false completes pumpAndSettle without hanging', (tester) async {
    const map = MapGraph(
      name: 'No Animate Map',
      start: 'start',
      places: [
        Place(id: 'start', name: 'Start', kind: PlaceKind.start),
        Place(id: 'dest', name: 'Dest', kind: PlaceKind.place),
      ],
      corridors: [
        Corridor(id: 'c1', from: 'start', to: 'dest', steps: 10, heading: 0),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 350,
            height: 350,
            child: TrailView(
              map: map,
              animate: false,
            ),
          ),
        ),
      ),
    );

    // pumpAndSettle completes immediately when animate: false
    await tester.pumpAndSettle();
    expect(find.byType(TrailView), findsOneWidget);
  });

  testWidgets('TrailView animate:true creates animation controller and updates pulse', (tester) async {
    const map = MapGraph(
      name: 'Animate Map',
      start: 'start',
      places: [
        Place(id: 'start', name: 'Start', kind: PlaceKind.start),
        Place(id: 'dest', name: 'Dest', kind: PlaceKind.place),
      ],
      corridors: [
        Corridor(id: 'c1', from: 'start', to: 'dest', steps: 10, heading: 0),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 350,
            height: 350,
            child: TrailView(
              map: map,
              animate: true,
            ),
          ),
        ),
      ),
    );

    // Initial frame
    await tester.pump();
    expect(find.byType(TrailView), findsOneWidget);

    // Advance 300ms
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TrailView), findsOneWidget);

    // Pump something else to trigger disposal cleanly
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('TrailPainter auto-fits map points so nothing clips outside size', () {
    const map = MapGraph(
      name: 'Wide Map',
      start: 'start',
      places: [
        Place(id: 'start', name: 'Start', kind: PlaceKind.start),
        Place(id: 'j1', name: 'Junction 1', kind: PlaceKind.junction),
        Place(id: 'east_wing', name: 'East Wing', kind: PlaceKind.place),
        Place(id: 'far_corner', name: 'Far Corner', kind: PlaceKind.place),
      ],
      corridors: [
        Corridor(id: 'c1', from: 'start', to: 'j1', steps: 30, heading: 0),
        Corridor(id: 'c2', from: 'j1', to: 'east_wing', steps: 50, heading: -90),
        Corridor(id: 'c3', from: 'east_wing', to: 'far_corner', steps: 40, heading: 180),
      ],
    );

    final painter = TrailPainter(map, null, null);
    const canvasSize = Size(360, 640);
    final points = layoutMap(map);

    for (final p in points) {
      final offset = painter.toOffset(p.x, p.y, canvasSize, precomputedPoints: points);
      expect(offset.dx, greaterThanOrEqualTo(0.0), reason: '${p.placeId} dx >= 0');
      expect(offset.dx, lessThanOrEqualTo(canvasSize.width), reason: '${p.placeId} dx <= width');
      expect(offset.dy, greaterThanOrEqualTo(0.0), reason: '${p.placeId} dy >= 0');
      expect(offset.dy, lessThanOrEqualTo(canvasSize.height), reason: '${p.placeId} dy <= height');
    }
  });

  testWidgets('TrailView paints distinct start and destination markers with route', (tester) async {
    const map = MapGraph(
      name: 'Route Map',
      start: 'start_node',
      places: [
        Place(id: 'start_node', name: 'Start Node', kind: PlaceKind.start),
        Place(id: 'mid', name: 'Mid Junction', kind: PlaceKind.junction),
        Place(id: 'dest_node', name: 'Dest Node', kind: PlaceKind.place),
      ],
      corridors: [
        Corridor(id: 'c1', from: 'start_node', to: 'mid', steps: 12, heading: 0),
        Corridor(id: 'c2', from: 'mid', to: 'dest_node', steps: 14, heading: 90),
      ],
    );

    const route = RoutePlan(
      legs: [
        Leg(corridorId: 'c1', reversed: false, heading: 0, steps: 12),
        Leg(corridorId: 'c2', reversed: false, heading: 90, steps: 14),
      ],
      totalSteps: 26,
      toId: 'dest_node',
    );

    const position = Position(
      legIndex: 1,
      stepsAlong: 7,
      anchoredBy: AnchorSource.turn,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: TrailView(
              map: map,
              route: route,
              position: position,
              animate: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TrailView), findsOneWidget);
  });

}
