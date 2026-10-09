import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/tuning.dart' as tuning;
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/app/screens/destination_list_screen.dart';
import 'package:breadcrumb/app/screens/navigate_screen.dart';

void main() {
  testWidgets('the start place is not in the destination list and junctions never show', (tester) async {
    final wiring = Wiring.instance;
    final startPlaceId = wiring.effectiveCurrentPlaceId;

    await tester.pumpWidget(const MaterialApp(
      home: DestinationListScreen(),
    ));
    await tester.pumpAndSettle();

    // Start place must not appear
    final startPlace = wiring.map.places.firstWhere((p) => p.id == startPlaceId);
    expect(find.text(startPlace.name), findsNothing);

    // Junctions must never appear
    for (final j in wiring.map.places.where((p) => p.kind == PlaceKind.junction)) {
      expect(find.text(j.name), findsNothing);
    }

    // Other destination places should appear
    expect(find.text('Cafe'), findsOneWidget);
    expect(find.text('Stage Side'), findsOneWidget);
  });

  testWidgets('a zero-leg route shows "You\'re already at X" and does not throw', (tester) async {
    final wiring = Wiring.instance;
    final startId = wiring.effectiveCurrentPlaceId;
    final startPlace = wiring.map.places.firstWhere((p) => p.id == startId);

    await tester.pumpWidget(MaterialApp(
      home: NavigateScreen(destinationId: startId),
    ));
    await tester.pumpAndSettle();

    expect(find.text("You're already at ${startPlace.name}"), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Go Back'), findsOneWidget);
  });

  testWidgets('planning an unreachable or unknown destination shows error message with back button', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: NavigateScreen(destinationId: 'unknown_place_xyz'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Navigation Error'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsOneWidget);
    expect(find.text('Go Back'), findsOneWidget);
  });

  testWidgets('the SIMULATED label is present while the simulation runs', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: NavigateScreen(destinationId: 'cafe'),
    ));
    await tester.pump();

    // While simulating, SIMULATED label is visible
    expect(find.text('SIMULATED'), findsWidgets);
  });

  test('turn calculations: right turn gives negative angle, left gives positive, straight produces no turn', () {
    // Current leg heading 0
    const currentHeading = 0.0;

    // Right turn: 0 to 270 (-90)
    final rightTurn = turnBetween(currentHeading, 270.0);
    expect(rightTurn, isNegative);
    expect(rightTurn, closeTo(-90.0, 0.001));

    // Left turn: 0 to 90 (+90)
    final leftTurn = turnBetween(currentHeading, 90.0);
    expect(leftTurn, isPositive);
    expect(leftTurn, closeTo(90.0, 0.001));

    // Straight join: 0 to 10 (diff < straightTolerance)
    final straightDiff = turnBetween(currentHeading, 10.0);
    expect(straightDiff.abs(), lessThan(tuning.straightTolerance));
  });

  test('a left turn event near the end of a leg advances to the next leg in real tracker', () {
    final wiring = Wiring.instance;
    // Route from entrance to cafe: c1 (15 steps, heading 0), c2 (10 steps, heading 90)
    final route = wiring.planner.plan(wiring.map, 'entrance', 'cafe');
    wiring.tracker.setRoute(route);
    wiring.tracker.anchor('entrance');

    // Walk 14 steps along c1 (1 step before junction j1, inside snapZone / snapSteps)
    for (int i = 0; i < 14; i++) {
      wiring.tracker.onStep(StepEvent(100 * (i + 1)));
    }

    // Turn left (+90)
    final pos = wiring.tracker.onTurn(const TurnEvent(2000, 90.0));
    expect(pos.legIndex, 1);
    expect(pos.stepsAlong, 0);
    expect(pos.offRoute, isFalse);
    expect(pos.anchoredBy, AnchorSource.turn);
  });
}
