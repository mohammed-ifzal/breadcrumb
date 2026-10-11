import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/guide.dart';
import 'package:breadcrumb/core/route_planner.dart';
import 'package:breadcrumb/core/tracker.dart';
import 'package:breadcrumb/core/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_maps.dart';

/// D31, from the iQOO debug buttons: off route, a running facing; facing the leg
/// again rejoins it ("Back on route"), and the Guide turns or walks the walker
/// back to the path.
///
/// demoMap: start --12, heading 0--> j1 --10, heading 90--> food_counter ...
/// _longMap: a --24, heading 0--> b --left, 6, heading 90--> c
void main() {
  final planner = DijkstraRoutePlanner();
  var t = 0;

  (RouteTracker, RoutePlan) trackerFor(String from, String to, [MapGraph map = demoMap]) {
    final route = planner.plan(map, from, to);
    return (RouteTracker(map)..setRoute(route), route);
  }

  Position walk(RouteTracker tracker, int steps) {
    var p = tracker.position;
    for (var i = 0; i < steps; i++) {
      p = tracker.onStep(StepEvent(t += 500));
    }
    return p;
  }

  Position turn(RouteTracker tracker, double angle) => tracker.onTurn(TurnEvent(t += 500, angle));

  Instruction say(RoutePlan r, Position p, [MapGraph map = demoMap]) => RouteGuide(map).next(r, p);

  test('walkBackMinSteps is 2', () => expect(walkBackMinSteps, 2));

  group('right then left', () {
    test('mid-leg: rejoins the same leg at the same step count', () {
      final (tracker, r) = trackerFor('a', 'c', _longMap);
      walk(tracker, 5);
      var p = turn(tracker, -90);
      expect(p.offRoute, isTrue);
      expect(p.facing, 270);
      var i = say(r, p, _longMap);
      expect((i.kind, i.text), (InstructionKind.turnLeft, 'Turn left to face the path.'));

      p = turn(tracker, 90);
      expect((p.legIndex, p.stepsAlong, p.offRoute, p.backOnRoute), (0, 5, false, true));
      expect((p.facing, p.stepsOffRoute, p.awayHeading), (null, 0, null));
      i = say(r, p, _longMap);
      expect(i.text, 'Back on route. In about 19 steps, turn left.');
      expect((i.kind, i.steps), (InstructionKind.turnLeft, null));

      p = walk(tracker, 1);
      expect((p.stepsAlong, p.backOnRoute), (6, false));
      expect(say(r, p, _longMap).text, 'In about 18 steps, turn left.');
    });

    test('near a left corner: the same leg, not a D27 corner snap', () {
      final (tracker, r) = trackerFor('start', 'stage_side');
      walk(tracker, 3);
      expect(turn(tracker, -90).offRoute, isTrue);
      final p = turn(tracker, 90);
      expect((p.legIndex, p.stepsAlong, p.offRoute), (0, 3, false));
      final i = say(r, p);
      expect(i.text, 'Back on route. In about 9 steps, turn left.');
      expect((i.kind, i.steps), (InstructionKind.turnLeft, null));
    });

    test('two steps away still rejoins', () {
      final (tracker, _) = trackerFor('a', 'c', _longMap);
      walk(tracker, 5);
      turn(tracker, -90);
      walk(tracker, 2);
      final p = turn(tracker, 90);
      expect((p.legIndex, p.stepsAlong, p.offRoute), (0, 5, false));
    });
  });

  test('right then right: "Turn around to get back on the path"', () {
    final (tracker, r) = trackerFor('a', 'c', _longMap);
    walk(tracker, 5);
    turn(tracker, -90);
    final p = turn(tracker, -90);
    expect((p.offRoute, p.facing), (true, 180));
    final i = say(r, p, _longMap);
    expect((i.kind, i.text), (InstructionKind.turnAround, 'Turn around to get back on the path.'));
  });

  group('walk back', () {
    test('off route + 3 steps: "Walk back about 3 steps, then turn right", then rejoins', () {
      final (tracker, r) = trackerFor('a', 'c', _longMap);
      walk(tracker, 3);
      turn(tracker, -90);
      var p = walk(tracker, 3);
      expect((p.offRoute, p.stepsOffRoute, p.awayHeading), (true, 3, 270));
      var i = say(r, p, _longMap);
      expect(
        (i.kind, i.text),
        (InstructionKind.turnAround, 'Walk back about 3 steps, then turn right.'),
      );
      expect(i.steps, isNull);

      // Turned around: walking back counts down. A turn-around is not the left corner.
      p = turn(tracker, 180);
      expect((p.offRoute, p.legIndex), (true, 0));
      i = say(r, p, _longMap);
      expect(
        (i.kind, i.text),
        (InstructionKind.straight, 'Walk back about 3 steps, then turn right.'),
      );
      p = walk(tracker, 1);
      expect(p.stepsOffRoute, 2);
      expect(say(r, p, _longMap).text, 'Turn right to face the path.');
      p = walk(tracker, 2);
      expect(p.stepsOffRoute, 0);

      p = turn(tracker, -90);
      expect((p.legIndex, p.stepsAlong, p.offRoute, p.backOnRoute), (0, 3, false, true));
    });

    test('sideways steps do not count', () {
      final (tracker, _) = trackerFor('a', 'c', _longMap);
      walk(tracker, 3);
      turn(tracker, -90);
      walk(tracker, 3);
      turn(tracker, -90); // facing 180: sideways to the way walked off
      expect(walk(tracker, 4).stepsOffRoute, 3);
    });

    test('walking back along the path: no turn after', () {
      final (tracker, r) = trackerFor('a', 'c', _longMap);
      walk(tracker, 5);
      turn(tracker, 180);
      final p = walk(tracker, 4);
      expect(say(r, p, _longMap).text, 'Walk back about 4 steps.');
    });
  });

  group('D27 still works', () {
    test('far off route, a turn matching the next corner snaps on', () {
      final (tracker, r) = trackerFor('start', 'stage_side');
      walk(tracker, 1);
      turn(tracker, -90);
      walk(tracker, 9);
      final p = turn(tracker, 90);
      expect((p.legIndex, p.stepsAlong, p.offRoute, p.backOnRoute), (1, 0, false, false));
      expect(say(r, p).text, isNot(startsWith('Back on route')));
    });

    test('an off-route position without a facing gives the D27 message', () {
      final r = planner.plan(demoMap, 'start', 'stage_side');
      final i = say(
        r,
        const Position(legIndex: 0, stepsAlong: 5, anchoredBy: AnchorSource.start, offRoute: true),
      );
      expect(i.kind, InstructionKind.offRoute);
    });
  });

  test('on route: no off-route fields, instructions unchanged', () {
    final (tracker, r) = trackerFor('start', 'stage_side');
    var p = walk(tracker, 4);
    expect((p.facing, p.stepsOffRoute, p.awayHeading, p.backOnRoute), (null, 0, null, false));
    expect(say(r, p).text, 'In about 8 steps, turn left.');
    p = turn(tracker, 90);
    expect((p.legIndex, p.offRoute, p.backOnRoute), (1, false, false));
    expect(say(r, p).text, 'In about 18 steps, turn right.');
  });
}

const _longMap = MapGraph(
  name: 'Long',
  start: 'a',
  places: [
    Place(id: 'a', name: 'A', kind: PlaceKind.start),
    Place(id: 'b', name: 'B', kind: PlaceKind.junction),
    Place(id: 'c', name: 'C', kind: PlaceKind.place),
  ],
  corridors: [
    Corridor(id: 'c1', from: 'a', to: 'b', steps: 24, heading: 0),
    Corridor(id: 'c2', from: 'b', to: 'c', steps: 6, heading: 90),
  ],
);
