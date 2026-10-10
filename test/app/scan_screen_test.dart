import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:breadcrumb/app/screens/scan_screen.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/perception/mlkit_sign_reader.dart';

void main() {
  setUp(() {
    Wiring.instance = Wiring.instance;
  });

  group('ScanScreen (Prompt 2)', () {
    testWidgets('calls tracker.pauseTurns(true) on open and false on dispose', (tester) async {
      bool pausedState = false;
      final fakeTracker = FakeTracker(onPauseTurns: (val) {
        pausedState = val;
      });
      Wiring.instance.tracker = fakeTracker;

      await tester.pumpWidget(
        const MaterialApp(
          home: ScanScreen(destinationId: 'cafe'),
        ),
      );
      await tester.pump();

      expect(pausedState, isTrue, reason: 'Must pause turns when opened');

      // Pop screen
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Done'))));
      await tester.pump();

      expect(pausedState, isFalse, reason: 'Must resume turns when closed');
    });

    testWidgets("matches sign on route: anchors tracker and shows You are at place", (tester) async {
      final map = Wiring.defaultDemoMap;
      final route = Wiring.instance.planner.plan(map, 'entrance', 'cafe');

      String? anchoredPlace;
      final fakeTracker = FakeTracker(
        onAnchor: (placeId) {
          anchoredPlace = placeId;
        },
      );
      Wiring.instance.tracker = fakeTracker;

      // Inject signReader returning "Cafe"
      Wiring.instance.signReader = MlKitSignReader(
        extractOverride: (path, script) async => 'Cafe',
      );

      RoutePlan? replannedRoute;
      Position? replannedPosition;

      await tester.pumpWidget(
        MaterialApp(
          home: ScanScreen(
            destinationId: 'cafe',
            currentRoute: route,
            mockCapture: () async => '/mock/sign.jpg',
            onReplan: (newRoute, pos) {
              replannedRoute = newRoute;
              replannedPosition = pos;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Capture & Read Sign
      await tester.tap(find.text('Capture & Read Sign'));
      await tester.pumpAndSettle();

      expect(find.text("You're at Cafe"), findsOneWidget);
      expect(anchoredPlace, 'cafe');
      expect(replannedPosition, isNotNull);
      expect(replannedRoute, isNotNull);
      expect(find.text('Continue Navigation'), findsOneWidget);
    });

    testWidgets('matches sign NOT on route: plans again from it and anchors tracker', (tester) async {
      final map = Wiring.defaultDemoMap;
      // Current route is entrance to cafe (doesn't include restroom)
      final route = Wiring.instance.planner.plan(map, 'entrance', 'cafe');

      String? anchoredPlace;
      RoutePlan? setRoutePlan;
      final fakeTracker = FakeTracker(
        onAnchor: (placeId) {
          anchoredPlace = placeId;
        },
        onSetRoute: (r) {
          setRoutePlan = r;
        },
      );
      Wiring.instance.tracker = fakeTracker;

      // Inject signReader returning "Restroom"
      Wiring.instance.signReader = MlKitSignReader(
        extractOverride: (path, script) async => 'Restroom',
      );

      RoutePlan? replannedRoute;
      Position? replannedPosition;

      await tester.pumpWidget(
        MaterialApp(
          home: ScanScreen(
            destinationId: 'cafe',
            currentRoute: route,
            mockCapture: () async => '/mock/restroom.jpg',
            onReplan: (newRoute, pos) {
              replannedRoute = newRoute;
              replannedPosition = pos;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Capture & Read Sign
      await tester.tap(find.text('Capture & Read Sign'));
      await tester.pumpAndSettle();

      expect(find.text("You're at Restroom"), findsOneWidget);
      expect(anchoredPlace, 'restroom');
      expect(setRoutePlan, isNotNull);
      expect(replannedPosition, isNotNull);
      expect(replannedRoute, isNotNull);
      // New route starts from restroom to cafe
      expect(replannedRoute!.legs.first.corridorId, anyOf('c5', isNotNull));
    });

    testWidgets("unmatched OCR text shows Could not read that, try again", (tester) async {
      Wiring.instance.signReader = MlKitSignReader(
        extractOverride: (path, script) async => 'Unrelated gibberish 12345',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ScanScreen(
            destinationId: 'cafe',
            mockCapture: () async => '/mock/unrelated.jpg',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Capture & Read Sign'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't read that, try again"), findsOneWidget);
      expect(find.text('Capture & Read Sign'), findsOneWidget);
    });

    testWidgets("blank OCR text shows Could not read that, try again", (tester) async {
      Wiring.instance.signReader = MlKitSignReader(
        extractOverride: (path, script) async => null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ScanScreen(
            destinationId: 'cafe',
            mockCapture: () async => '/mock/blank.jpg',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Capture & Read Sign'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't read that, try again"), findsOneWidget);
    });
  });
}

class FakeTracker implements Tracker {
  FakeTracker({
    this.onPauseTurns,
    this.onAnchor,
    this.onSetRoute,
  });

  final void Function(bool on)? onPauseTurns;
  final void Function(String placeId)? onAnchor;
  final void Function(RoutePlan route)? onSetRoute;

  @override
  void pauseTurns(bool on) {
    onPauseTurns?.call(on);
  }

  @override
  Position anchor(String placeId) {
    onAnchor?.call(placeId);
    return const Position(
      legIndex: 0,
      stepsAlong: 0,
      anchoredBy: AnchorSource.sign,
      offRoute: false,
      needsReplan: false,
    );
  }

  @override
  void setRoute(RoutePlan r) {
    onSetRoute?.call(r);
  }

  @override
  Position onStep(StepEvent e) => const Position(
        legIndex: 0,
        stepsAlong: 0,
        anchoredBy: AnchorSource.start,
        offRoute: false,
        needsReplan: false,
      );

  @override
  Position onTurn(TurnEvent e) => const Position(
        legIndex: 0,
        stepsAlong: 0,
        anchoredBy: AnchorSource.turn,
        offRoute: false,
        needsReplan: false,
      );

  @override
  Position tapHere(String placeId) => const Position(
        legIndex: 0,
        stepsAlong: 0,
        anchoredBy: AnchorSource.tap,
        offRoute: false,
        needsReplan: false,
      );
}
