import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/guide.dart';
import 'package:breadcrumb/core/route_planner.dart';
import 'package:breadcrumb/core/tracker.dart';
import 'package:breadcrumb/core/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_maps.dart';

/// D29: position confidence and the arrival guard.
///
/// demoMap, start to stage_side: start --12, heading 0--> j1 (left) --10-->
/// food_counter --8--> j2 (right) --6, heading 0--> stage_side.
void main() {
  final planner = DijkstraRoutePlanner();
  var t = 0;

  (RouteTracker, RoutePlan) trackerFor(
    String from,
    String to, {
    MapGraph map = demoMap,
    bool confidence = false,
    bool guard = false,
  }) {
    final route = planner.plan(map, from, to);
    final tracker = RouteTracker(map, confidenceOn: confidence, arrivalGuardOn: guard)
      ..setRoute(route);
    return (tracker, route);
  }

  Position walk(RouteTracker tracker, int steps) {
    var p = tracker.position;
    for (var i = 0; i < steps; i++) {
      p = tracker.onStep(StepEvent(t += 500));
    }
    return p;
  }

  Position turn(RouteTracker tracker, double angle) =>
      tracker.onTurn(TurnEvent(t += 500, angle));

  test('flags default to tuning.dart', () {
    final tracker = RouteTracker(demoMap);
    expect(tracker.confidenceOn, useConfidence);
    expect(tracker.arrivalGuardOn, useArrivalGuard);
  });

  group('confidence', () {
    test('stays 1.0 with the flag off', () {
      final (tracker, _) = trackerFor('start', 'stage_side');
      expect(walk(tracker, 10).confidence, 1.0);
    });

    test('decays by confidenceDecayPerStep on every step', () {
      final (tracker, _) = trackerFor('start', 'stage_side', confidence: true);
      expect(tracker.position.confidence, 1.0);
      expect(walk(tracker, 10).confidence, closeTo(_pow(confidenceDecayPerStep, 10), 1e-9));
    });

    test('a snapped corner brings it back up to confidenceCornerReset', () {
      final (tracker, _) = trackerFor('start', 'stage_side', confidence: true);
      expect(walk(tracker, 12).confidence, lessThan(confidenceCornerReset));
      final p = turn(tracker, 90);
      expect(p.legIndex, 1);
      expect(p.confidence, confidenceCornerReset);
    });

    test('a snapped corner never lowers it', () {
      final (tracker, _) = trackerFor('start', 'stage_side', confidence: true);
      tracker.tapHere('j1');
      walk(tracker, 15);
      tracker.tapHere('food_counter');
      walk(tracker, 2);
      final before = tracker.position.confidence;
      expect(before, greaterThan(confidenceCornerReset));
      expect(turn(tracker, -90).confidence, before);
    });

    test('tapHere resets it to 1.0', () {
      final (tracker, _) = trackerFor('start', 'stage_side', confidence: true);
      walk(tracker, 30);
      expect(tracker.tapHere('food_counter').confidence, 1.0);
    });

    test('arrival resets it to 1.0', () {
      final (tracker, _) = trackerFor('start', 'stage_side', confidence: true);
      walk(tracker, 12);
      turn(tracker, 90);
      walk(tracker, 18);
      turn(tracker, -90);
      expect(walk(tracker, 5).confidence, lessThan(1.0));
      expect(walk(tracker, 1).confidence, 1.0);
    });

    test('a long straight walk drops below confidenceAskBelow and the Guide asks', () {
      const map = MapGraph(
        name: 'Hall',
        start: 'a',
        places: [
          Place(id: 'a', name: 'Door', kind: PlaceKind.start),
          Place(id: 'b', name: 'Desk', kind: PlaceKind.place),
        ],
        corridors: [Corridor(id: 'c1', from: 'a', to: 'b', steps: 60, heading: 0)],
      );
      final (tracker, r) = trackerFor('a', 'b', map: map, confidence: true);
      final guide = RouteGuide(map);
      final asked = <int>[];
      for (var i = 1; i <= 50; i++) {
        final p = walk(tracker, 1);
        if (guide.next(r, p).kind == InstructionKind.confirmPlace) asked.add(i);
      }
      // 0.98^34 = 0.503, 0.98^35 = 0.493: asked once, at step 35.
      expect(asked, [35]);
    });
  });

  group('Guide confirmPlace', () {
    Position at(int leg, double confidence) => Position(
      legIndex: leg,
      stepsAlong: 2,
      anchoredBy: AnchorSource.turn,
      confidence: confidence,
    );

    test('asks about the end of the leg below confidenceAskBelow, once per leg', () {
      final r = planner.plan(demoMap, 'start', 'stage_side');
      final guide = RouteGuide(demoMap);
      // Leg 0 ends at j1, a junction; leg 1 at food_counter. "I'm here" taps
      // the end of the current leg, so it answers this question.
      final first = guide.next(r, at(0, 0.4));
      expect(first.kind, InstructionKind.confirmPlace);
      expect(first.text, 'Are you at the next corner?');
      expect(guide.next(r, at(0, 0.3)).kind, InstructionKind.turnLeft);
      final second = guide.next(r, at(1, 0.3));
      expect(second.kind, InstructionKind.confirmPlace);
      expect(second.placeName, 'Food counter');
      expect(second.text, 'Are you at Food counter?');
      expect(guide.next(r, at(1, 0.2)).kind, isNot(InstructionKind.confirmPlace));
    });

    test('asks again on a new route', () {
      final guide = RouteGuide(demoMap);
      final r1 = planner.plan(demoMap, 'start', 'stage_side');
      final r2 = planner.plan(demoMap, 'start', 'stage_side');
      expect(guide.next(r1, at(0, 0.4)).kind, InstructionKind.confirmPlace);
      expect(guide.next(r2, at(0, 0.4)).kind, InstructionKind.confirmPlace);
    });

    test('does not ask at or above confidenceAskBelow', () {
      final r = planner.plan(demoMap, 'start', 'stage_side');
      expect(
        RouteGuide(demoMap).next(r, at(0, confidenceAskBelow)).kind,
        InstructionKind.turnLeft,
      );
    });

    test('off route still wins', () {
      final r = planner.plan(demoMap, 'start', 'stage_side');
      const p = Position(
        legIndex: 0,
        stepsAlong: 2,
        anchoredBy: AnchorSource.turn,
        offRoute: true,
        confidence: 0.1,
      );
      expect(RouteGuide(demoMap).next(r, p).kind, InstructionKind.offRoute);
    });
  });

  group('arrival guard', () {
    /// Turns left at j1, then misses the right turn at j2: the overwalk moves the
    /// position onto the final leg with no turn seen.
    Position missFinalTurn(RouteTracker tracker) {
      walk(tracker, 12);
      turn(tracker, 90);
      // Past food_counter the run is c3 (8 steps): 8 + 30% overwalk -> step 21.
      return walk(tracker, 21);
    }

    test('off: reaching the final leg by overwalk still arrives', () {
      final (tracker, r) = trackerFor('start', 'stage_side');
      expect(missFinalTurn(tracker).legIndex, 3);
      final p = walk(tracker, 6);
      expect(p.unconfirmedArrival, isFalse);
      expect(RouteGuide(demoMap).next(r, p).kind, InstructionKind.arrive);
    });

    test('on: reaching the final leg by overwalk asks to confirm, then warns', () {
      final (tracker, r) = trackerFor('start', 'stage_side', guard: true);
      final guide = RouteGuide(demoMap);
      expect(missFinalTurn(tracker).legIndex, 3);
      expect(guide.next(r, walk(tracker, 5)).kind, InstructionKind.straight);

      var p = walk(tracker, 1);
      expect(p.unconfirmedArrival, isTrue);
      final ask = guide.next(r, p);
      expect(ask.kind, InstructionKind.arrivingConfirm);
      expect(ask.text, "Stage side should be right here — tap I'm here to confirm.");

      // 0.3 x 6 = 1.8 steps past: still asking at 1, warning at 2.
      expect(guide.next(r, walk(tracker, 1)).kind, InstructionKind.arrivingConfirm);
      p = walk(tracker, 1);
      final warn = guide.next(r, p);
      expect(warn.kind, InstructionKind.maybePassed);
      expect(warn.text, 'You may have passed Stage side.');

      p = tracker.tapHere('stage_side');
      expect(p.unconfirmedArrival, isFalse);
      expect(guide.next(r, p).kind, InstructionKind.arrive);
    });

    test('on: with every turn seen, arrival is normal', () {
      final (tracker, r) = trackerFor('start', 'stage_side', guard: true);
      walk(tracker, 12);
      turn(tracker, 90);
      walk(tracker, 18);
      turn(tracker, -90);
      final p = walk(tracker, 6);
      expect(p.unconfirmedArrival, isFalse);
      expect(RouteGuide(demoMap).next(r, p).kind, InstructionKind.arrive);
    });

    test('on: a single-leg route arrives normally', () {
      final (tracker, r) = trackerFor('start', 'j1', guard: true);
      final p = walk(tracker, 12);
      expect(p.unconfirmedArrival, isFalse);
      expect(RouteGuide(demoMap).next(r, p).kind, InstructionKind.arrive);
    });

    test('on: a late turn snap onto the final leg counts as evidence', () {
      final (tracker, r) = trackerFor('start', 'stage_side', guard: true);
      walk(tracker, 12);
      turn(tracker, 90);
      walk(tracker, 16);
      turn(tracker, -90); // 2 steps early, inside the snap zone
      final p = walk(tracker, 6);
      expect(p.unconfirmedArrival, isFalse);
      expect(RouteGuide(demoMap).next(r, p).kind, InstructionKind.arrive);
    });

    test('on: a floor change that completes the last leg arrives', () {
      final (tracker, r) = trackerFor(
        'entrance',
        'stairs_top',
        map: twoFloorMap,
        guard: true,
      );
      walk(tracker, 10);
      final p = tracker.onFloorChange(1);
      expect(p.unconfirmedArrival, isFalse);
      expect(RouteGuide(twoFloorMap).next(r, p).kind, InstructionKind.arrive);
    });

    test('on: an anchor on the destination arrives', () {
      final (tracker, r) = trackerFor('start', 'stage_side', guard: true);
      missFinalTurn(tracker);
      walk(tracker, 6);
      final p = tracker.anchor('stage_side');
      expect(p.unconfirmedArrival, isFalse);
      expect(RouteGuide(demoMap).next(r, p).kind, InstructionKind.arrive);
    });
  });
}

double _pow(double x, int n) {
  var v = 1.0;
  for (var i = 0; i < n; i++) {
    v *= x;
  }
  return v;
}
