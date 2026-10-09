import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/route_planner.dart';
import 'package:breadcrumb/core/tracker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_maps.dart';

void main() {
  final planner = DijkstraRoutePlanner();
  var t = 0;

  RouteTracker trackerFor(String from, String to) =>
      RouteTracker(demoMap)..setRoute(planner.plan(demoMap, from, to));

  Position walk(RouteTracker tracker, int steps) {
    late Position p;
    for (var i = 0; i < steps; i++) {
      p = tracker.onStep(StepEvent(t += 500));
    }
    return p;
  }

  Position turn(RouteTracker tracker, double angle) =>
      tracker.onTurn(TurnEvent(t += 500, angle));

  test('starts at the first leg, anchored by start', () {
    final tracker = trackerFor('start', 'stage_side');
    final p = tracker.position;
    expect(p.legIndex, 0);
    expect(p.stepsAlong, 0);
    expect(p.anchoredBy, AnchorSource.start);
    expect(p.offRoute, isFalse);
  });

  test('a straight walk counts steps and rolls over straight-on joins', () {
    // start -> food_counter -> j2: c2 (10) and c3 (8) are both heading 90.
    final tracker = trackerFor('j1', 'stage_side');

    var p = walk(tracker, 7);
    expect((p.legIndex, p.stepsAlong), (0, 7));

    p = walk(tracker, 3); // reaches food_counter
    expect((p.legIndex, p.stepsAlong), (1, 0));

    p = walk(tracker, 5);
    expect((p.legIndex, p.stepsAlong), (1, 5));
    expect(p.offRoute, isFalse);
  });

  test('without a turn, steps keep counting past the end of a turning leg', () {
    final tracker = trackerFor('start', 'stage_side');
    final p = walk(tracker, 16);
    expect((p.legIndex, p.stepsAlong), (0, 16));
  });

  test('a correct turn near the end of a leg snaps to the next leg', () {
    final tracker = trackerFor('start', 'stage_side');
    walk(tracker, 10); // 2 short of j1: inside snapSteps

    final p = turn(tracker, 85); // left, as c1 -> c2 needs
    expect((p.legIndex, p.stepsAlong), (1, 0));
    expect(p.anchoredBy, AnchorSource.turn);
    expect(p.offRoute, isFalse);
  });

  test('a correct turn a little after the end still snaps', () {
    final tracker = trackerFor('start', 'stage_side');
    walk(tracker, 14);
    final p = turn(tracker, 92);
    expect((p.legIndex, p.stepsAlong), (1, 0));
  });

  test('the snap looks past straight-on joins to the next real turn', () {
    // j1 -> j2 is c2 (10) + c3 (8), then a right turn onto c4.
    final tracker = trackerFor('j1', 'stage_side');
    walk(tracker, 2); // 16 steps from j2: too early
    expect(turn(tracker, -90).offRoute, isTrue);

    final again = trackerFor('j1', 'stage_side');
    walk(again, 11); // past food_counter, 7 steps from j2
    final p = turn(again, -90);
    expect((p.legIndex, p.stepsAlong), (2, 0));
    expect(p.offRoute, isFalse);
  });

  test('a wrong turn gives offRoute', () {
    final tracker = trackerFor('start', 'stage_side');
    walk(tracker, 10);
    final p = turn(tracker, -90); // right instead of left
    expect(p.offRoute, isTrue);
    expect(p.legIndex, 0);
  });

  test('a turn far from the end of a leg gives offRoute', () {
    final tracker = trackerFor('start', 'stage_side');
    walk(tracker, 2); // 10 steps before j1: outside both snap rules
    expect(turn(tracker, 90).offRoute, isTrue);
  });

  test('any turn on the last straight run gives offRoute', () {
    final tracker = trackerFor('j2', 'stage_side');
    walk(tracker, 4);
    expect(turn(tracker, 90).offRoute, isTrue);
  });

  test('turns are ignored while paused', () {
    final tracker = trackerFor('start', 'stage_side');
    walk(tracker, 10);
    tracker.pauseTurns(true);
    var p = turn(tracker, -90);
    expect(p.offRoute, isFalse);
    expect(p.legIndex, 0);

    tracker.pauseTurns(false);
    p = turn(tracker, 90);
    expect(p.legIndex, 1);
  });

  test('navigating back: the turns needed are mirrored', () {
    // stage_side -> start: c4 rev (6), left, c3 rev (8), c2 rev (10), right, c1 rev (12)
    final tracker = trackerFor('stage_side', 'start');

    walk(tracker, 6);
    expect(turn(tracker, -90).offRoute, isTrue, reason: 'right is wrong walking back');

    final again = trackerFor('stage_side', 'start');
    walk(again, 6);
    var p = turn(again, 90); // left at j2 walking back
    expect((p.legIndex, p.stepsAlong), (1, 0));

    p = walk(again, 8); // food_counter: straight on
    expect((p.legIndex, p.stepsAlong), (2, 0));

    walk(again, 9);
    p = turn(again, -88); // right at j1 walking back
    expect((p.legIndex, p.stepsAlong), (3, 0));

    p = walk(again, 12);
    expect((p.legIndex, p.stepsAlong), (3, 12));
    expect(p.offRoute, isFalse);
  });

  test('tap "I\'m here" mid-leg snaps to the tapped place', () {
    final tracker = trackerFor('start', 'stage_side');
    walk(tracker, 12);
    turn(tracker, 90);
    walk(tracker, 6); // counts say 6 along c2; the person is actually at the counter

    var p = tracker.tapHere('food_counter');
    expect((p.legIndex, p.stepsAlong), (2, 0));
    expect(p.anchoredBy, AnchorSource.tap);
    expect(p.needsReplan, isFalse);

    p = tracker.tapHere('stage_side'); // the destination itself
    expect((p.legIndex, p.stepsAlong), (3, 6));
  });

  test('an anchor clears offRoute', () {
    final tracker = trackerFor('start', 'stage_side');
    walk(tracker, 10);
    turn(tracker, -90);
    final p = tracker.anchor('j1');
    expect(p.offRoute, isFalse);
    expect((p.legIndex, p.stepsAlong), (1, 0));
    expect(p.anchoredBy, AnchorSource.sign);
  });

  test('an anchor off the route sets needsReplan and keeps the position', () {
    final tracker = trackerFor('j2', 'stage_side');
    walk(tracker, 3);
    final p = tracker.anchor('food_counter');
    expect(p.needsReplan, isTrue);
    expect((p.legIndex, p.stepsAlong), (0, 3));
    expect(p.anchoredBy, AnchorSource.sign);
  });

  test('setRoute clears needsReplan and offRoute', () {
    final tracker = trackerFor('j2', 'stage_side');
    tracker.anchor('food_counter');
    tracker.setRoute(planner.plan(demoMap, 'food_counter', 'stage_side'));
    final p = tracker.position;
    expect(p.needsReplan, isFalse);
    expect(p.offRoute, isFalse);
    expect((p.legIndex, p.stepsAlong), (0, 0));
  });

  test('an unknown place ID throws', () {
    final tracker = trackerFor('start', 'stage_side');
    expect(() => tracker.anchor('moon'), throwsArgumentError);
  });

  test('before setRoute, events do not throw', () {
    final tracker = RouteTracker(demoMap);
    tracker.onStep(const StepEvent(1));
    tracker.onTurn(const TurnEvent(2, 90));
    expect(tracker.anchor('food_counter').needsReplan, isTrue);
  });
}
