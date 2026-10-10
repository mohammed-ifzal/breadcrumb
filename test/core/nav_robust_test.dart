import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/guide.dart';
import 'package:breadcrumb/core/route_planner.dart';
import 'package:breadcrumb/core/tracker.dart';
import 'package:breadcrumb/core/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_maps.dart';

/// D27, from the iQOO loop test: orientation before the first step, corner
/// wording, the off-route message and auto-recovery.
///
/// demoMap: start --12, heading 0--> j1 --10, heading 90--> food_counter
/// --8, heading 90--> j2 --6, heading 0--> stage_side (where the recording ended).
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

  group('1. orientation phase', () {
    test('starting where the recording ended, facing is the corridor arrived on', () {
      // Arrived at stage_side heading 0; walking back starts heading 180.
      final (tracker, r) = trackerFor('stage_side', 'start');
      final p = tracker.position;
      expect(p.orienting, isTrue);
      expect(p.facing, 0);
      final i = say(r, p);
      expect(i.kind, InstructionKind.turnAround);
      expect(i.steps, isNull);
      expect(i.text, 'Turn around, then walk straight.');
    });

    test('turns before the first step only update the facing', () {
      final (tracker, r) = trackerFor('stage_side', 'start');
      var p = turn(tracker, 90);
      expect((p.legIndex, p.stepsAlong, p.offRoute), (0, 0, false));
      expect(p.facing, 90);
      expect(say(r, p).text, 'Turn left, then walk straight.');

      p = turn(tracker, -180);
      expect(p.facing, 270);
      expect(say(r, p).text, 'Turn right, then walk straight.');

      p = turn(tracker, 90); // facing 0
      p = turn(tracker, 180); // facing 180, along the first leg
      expect(p.facing, 180);
      expect((p.legIndex, p.offRoute), (0, false));
      expect(say(r, p).text, 'In about 6 steps, turn left.');
    });

    test('a turned-around walker is never flagged off route before walking', () {
      // The loop test: after Stop the walker turned around, then started.
      final (tracker, r) = trackerFor('stage_side', 'start');
      var p = turn(tracker, 180);
      expect(p.offRoute, isFalse);
      p = walk(tracker, 4);
      expect((p.legIndex, p.stepsAlong, p.offRoute), (0, 4, false));
      expect(say(r, p).text, 'Get ready to turn left.');
    });

    test('the first step ends the phase; later turns are route turns again', () {
      final (tracker, _) = trackerFor('stage_side', 'start');
      var p = walk(tracker, 1);
      expect(p.orienting, isFalse);
      expect(p.facing, isNull);
      p = turn(tracker, -90); // c4 back to j2 needs a left
      expect(p.offRoute, isTrue);
    });

    test('anchoring at the start (as Navigate does) keeps the phase', () {
      final (tracker, r) = trackerFor('stage_side', 'start');
      final p = tracker.anchor('stage_side');
      expect(p.orienting, isTrue);
      expect(say(r, p).text, 'Turn around, then walk straight.');
    });

    test('starting anywhere else, facing is unknown: "Face <next place>"', () {
      final (tracker, r) = trackerFor('start', 'stage_side');
      var p = tracker.position;
      expect(p.orienting, isTrue);
      expect(p.facing, isNull);
      // j1 is a junction, so the next place is the food counter.
      final i = say(r, p);
      expect(i.kind, InstructionKind.straight);
      expect(i.steps, isNull);
      expect(i.text, 'Face Food counter and start walking.');

      p = turn(tracker, 90);
      expect((p.facing, p.offRoute), (null, false));
      p = walk(tracker, 1);
      expect(say(r, p).text, 'In about 11 steps, turn left.');
    });

    test('already facing the first leg: the normal instruction', () {
      // The recording ended at "end" heading 0, and a corridor leaves it heading 0.
      const map = MapGraph(
        name: 'Ahead',
        start: 'x',
        places: [
          Place(id: 'x', name: 'X', kind: PlaceKind.start),
          Place(id: 'end', name: 'End of walk', kind: PlaceKind.place),
          Place(id: 'y', name: 'Y', kind: PlaceKind.place),
        ],
        corridors: [
          Corridor(id: 'c0', from: 'end', to: 'y', steps: 9, heading: 10),
          Corridor(id: 'c1', from: 'x', to: 'end', steps: 5, heading: 0),
        ],
      );
      final (tracker, r) = trackerFor('end', 'y', map);
      expect(tracker.position.facing, 0);
      expect(say(r, tracker.position, map).text, 'Walk straight, about 9 steps.');
    });
  });

  group('2. corners', () {
    test('wider snapping: snapZone 0.5, snapSteps 10', () {
      expect(snapZone, 0.5);
      expect(snapSteps, 10);
      final (tracker, _) = trackerFor('start', 'stage_side');
      walk(tracker, 2); // 10 steps before j1
      final p = turn(tracker, 90);
      expect((p.legIndex, p.stepsAlong, p.offRoute), (1, 0, false));
    });

    test('snapZone: half of a long run', () {
      final (near, _) = trackerFor('a', 'c', _longMap);
      walk(near, 12); // 12 of 24 left: inside half
      expect(turn(near, 90).legIndex, 1);

      final (far, _) = trackerFor('a', 'c', _longMap);
      walk(far, 11); // 13 left: outside half and outside snapSteps
      expect(turn(far, 90).offRoute, isTrue);
    });

    test('"Get ready to turn left." within 3 steps, "Turn left at the corner." at 0', () {
      final r = planner.plan(demoMap, 'start', 'stage_side');
      Position at(int along) => Position(legIndex: 0, stepsAlong: along, anchoredBy: AnchorSource.start);
      expect(say(r, at(8)).text, 'In about 4 steps, turn left.');
      for (final along in [9, 10, 11]) {
        final i = say(r, at(along));
        expect(i.kind, InstructionKind.turnLeft);
        expect(i.text, 'Get ready to turn left.');
      }
      final corner = say(r, at(12));
      expect((corner.kind, corner.steps), (InstructionKind.turnLeft, 0));
      expect(corner.text, 'Turn left at the corner.');
    });

    test('the leg advances only on a correct turn or an overwalk', () {
      // Step counts run 2 over: the walker is still 2 steps from the corner.
      final (tracker, r) = trackerFor('start', 'stage_side');
      var p = walk(tracker, 14);
      expect((p.legIndex, p.stepsAlong), (0, 14));
      expect(say(r, p).text, 'Turn left at the corner.');
      p = turn(tracker, 90);
      expect((p.legIndex, p.stepsAlong, p.offRoute), (1, 0, false));
    });

    test('after an overwalk, the real turn coming late is absorbed', () {
      final (tracker, _) = trackerFor('start', 'stage_side');
      var p = walk(tracker, 16); // 4 past a 12-step leg: over 30%
      expect((p.legIndex, p.stepsAlong), (1, 0));
      p = turn(tracker, 90);
      expect((p.legIndex, p.offRoute), (1, false));
    });
  });

  test('3. off route: back to the last corner or "I\'m here", not Scan sign', () {
    final r = planner.plan(demoMap, 'start', 'stage_side');
    final i = say(
      r,
      const Position(legIndex: 0, stepsAlong: 5, anchoredBy: AnchorSource.start, offRoute: true),
    );
    expect(i.kind, InstructionKind.offRoute);
    expect(i.text, "Looks like you went off the path. Go back to the last corner or tap I'm here.");
    expect(i.text.toLowerCase(), isNot(contains('scan')));
    expect(i.text.toLowerCase(), isNot(contains('sign')));
  });

  group('4. auto-recover', () {
    test('off route, a turn matching the next corner snaps back on', () {
      final (tracker, r) = trackerFor('start', 'stage_side');
      walk(tracker, 1);
      var p = turn(tracker, -90); // j1 needs a left
      expect(p.offRoute, isTrue);
      p = walk(tracker, 9);
      expect((p.legIndex, p.stepsAlong, p.offRoute), (0, 10, true));
      p = turn(tracker, 90);
      expect((p.legIndex, p.stepsAlong, p.offRoute), (1, 0, false));
      expect(p.anchoredBy, AnchorSource.turn);
      expect(say(r, p).kind, isNot(InstructionKind.offRoute));
    });

    test('off route, a wrong-way turn keeps it off route', () {
      final (tracker, _) = trackerFor('start', 'stage_side');
      walk(tracker, 1);
      turn(tracker, -90);
      walk(tracker, 9);
      expect(turn(tracker, -90).offRoute, isTrue);
    });

    test('only within 2 x snapSteps of the corner, either side', () {
      final (early, _) = trackerFor('a', 'c', _longMap);
      walk(early, 1);
      turn(early, -90);
      walk(early, 2); // at 3: 21 before the corner
      expect(turn(early, 90).offRoute, isTrue);
      walk(early, 1); // at 4: 20 before
      expect(turn(early, 90).offRoute, isFalse);

      final (late, _) = trackerFor('a', 'c', _longMap);
      walk(late, 1);
      turn(late, -90);
      walk(late, 44); // at 45: 21 past, no overwalk while off route
      expect(late.position.legIndex, 0);
      expect(turn(late, 90).offRoute, isTrue);

      final (justPast, _) = trackerFor('a', 'c', _longMap);
      walk(justPast, 1);
      turn(justPast, -90);
      walk(justPast, 43); // at 44: 20 past
      expect(turn(justPast, 90).legIndex, 1);
    });
  });
}

/// a --24, heading 0--> b --left, 6, heading 90--> c
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
