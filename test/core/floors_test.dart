import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/guide.dart';
import 'package:breadcrumb/core/map_json.dart';
import 'package:breadcrumb/core/route_planner.dart';
import 'package:breadcrumb/core/route_runs.dart';
import 'package:breadcrumb/core/tracker.dart';
import 'package:breadcrumb/core/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_maps.dart';

/// D24: several floors joined by stairs, escalators and lifts.
void main() {
  final planner = DijkstraRoutePlanner();
  final guide = RouteGuide(twoFloorMap);
  var t = 0;

  (RouteTracker, RoutePlan) trackerFor(String from, String to, [MapGraph? map]) {
    final m = map ?? twoFloorMap;
    final route = planner.plan(m, from, to);
    return (RouteTracker(m)..setRoute(route), route);
  }

  Position walk(RouteTracker tracker, int steps) {
    var p = tracker.position;
    for (var i = 0; i < steps; i++) {
      p = tracker.onStep(StepEvent(t += 500));
    }
    return p;
  }

  group('map JSON', () {
    test('an old map with no floor fields loads with the defaults', () {
      final map = decodeMap('''
{"version": 1, "name": "M", "start": "a",
 "places": [{"id": "a", "name": "A", "aliases": [], "kind": "start"},
            {"id": "b", "name": "B", "aliases": [], "kind": "place"}],
 "corridors": [{"id": "c1", "from": "a", "to": "b", "steps": 7, "heading": 0}]}
''');
      expect(map.places.map((p) => p.floor), [0, 0]);
      final c = map.corridors.single;
      expect(c.kind, CorridorKind.walk);
      expect(c.floorDelta, 0);
      expect(c.isTransition, isFalse);
    });

    test('a one-floor map is written without the new keys', () {
      final json = demoMap.toJson();
      for (final p in json['places'] as List) {
        expect((p as Map).containsKey('floor'), isFalse);
      }
      for (final c in json['corridors'] as List) {
        expect((c as Map).containsKey('kind'), isFalse);
        expect(c.containsKey('floorDelta'), isFalse);
      }
    });

    test('a two-floor map round-trips floor, kind and floorDelta', () {
      final back = decodeMap(encodeMap(twoFloorMap));
      expect(back.toJson(), twoFloorMap.toJson());
      expect(back.placeById('cafe')!.floor, 1);
      expect(back.corridorById('c2')!.kind, CorridorKind.stairs);
      expect(back.corridorById('c2')!.floorDelta, 1);
      expect(back.corridorById('c5')!.kind, CorridorKind.lift);
    });

    test('decodeMap rejects a floorDelta that does not fit the floors', () {
      String map(String corridor) =>
          '''
{"version": 1, "name": "M", "start": "a",
 "places": [{"id": "a", "name": "A", "aliases": [], "kind": "start"},
            {"id": "b", "name": "B", "aliases": [], "kind": "place", "floor": 1}],
 "corridors": [$corridor]}
''';
      expect(
        decodeMap(
          map(
            '{"id": "c1", "from": "a", "to": "b", "steps": 9, "heading": 0, '
            '"kind": "escalator", "floorDelta": 1}',
          ),
        ).corridors.single.kind,
        CorridorKind.escalator,
      );
      // Wrong sign.
      expect(
        () => decodeMap(
          map(
            '{"id": "c1", "from": "a", "to": "b", "steps": 9, "heading": 0, '
            '"kind": "stairs", "floorDelta": -1}',
          ),
        ),
        throwsFormatException,
      );
      // A plain walk can't change floor.
      expect(
        () => decodeMap(
          map(
            '{"id": "c1", "from": "a", "to": "b", "steps": 9, "heading": 0, '
            '"floorDelta": 1}',
          ),
        ),
        throwsFormatException,
      );
    });
  });

  group('RoutePlanner', () {
    test('up the stairs: the legs carry kind and floorDelta', () {
      final r = planner.plan(twoFloorMap, 'entrance', 'cafe');
      expect([for (final l in r.legs) l.corridorId], ['c1', 'c2', 'c3']);
      expect(
        [for (final l in r.legs) l.kind],
        [CorridorKind.walk, CorridorKind.stairs, CorridorKind.walk],
      );
      expect([for (final l in r.legs) l.floorDelta], [0, 1, 0]);
      expect(r.totalSteps, 10 + 12 + 8);
    });

    test('down the stairs: reversed legs negate floorDelta', () {
      final r = planner.plan(twoFloorMap, 'cafe', 'entrance');
      expect([for (final l in r.legs) l.corridorId], ['c3', 'c2', 'c1']);
      expect(r.legs[1].reversed, isTrue);
      expect(r.legs[1].kind, CorridorKind.stairs);
      expect(r.legs[1].floorDelta, -1);
      expect(r.legs[1].heading, 180.0);
    });

    test('each transition costs floorChangeCostSteps more than its steps', () {
      // a -> b on Floor 0: a 30-step walk, or 5 stairs up and a 0-step lift down.
      // Without the cost the stairs + lift (5) would win; with it they cost 45.
      const map = MapGraph(
        name: 'Detour',
        start: 'a',
        places: [
          Place(id: 'a', name: 'A', kind: PlaceKind.start),
          Place(id: 'b', name: 'B', kind: PlaceKind.place),
          Place(id: 'x', name: 'X', kind: PlaceKind.place, floor: 1),
        ],
        corridors: [
          Corridor(id: 'walk', from: 'a', to: 'b', steps: 30, heading: 0),
          Corridor(
            id: 'up',
            from: 'a',
            to: 'x',
            steps: 5,
            heading: 0,
            kind: CorridorKind.stairs,
            floorDelta: 1,
          ),
          Corridor(
            id: 'down',
            from: 'x',
            to: 'b',
            steps: 0,
            heading: 0,
            kind: CorridorKind.lift,
            floorDelta: -1,
          ),
        ],
      );
      expect(floorChangeCostSteps, 20);
      final r = planner.plan(map, 'a', 'b');
      expect([for (final l in r.legs) l.corridorId], ['walk']);

      // From X the lift is the only way down, and totalSteps leaves out the cost.
      final down = planner.plan(map, 'x', 'b');
      expect([for (final l in down.legs) l.corridorId], ['down']);
      expect(down.totalSteps, 0);
    });
  });

  group('Guide', () {
    Instruction at(RoutePlan r, int leg, int along) =>
        guide.next(r, Position(legIndex: leg, stepsAlong: along, anchoredBy: AnchorSource.start));

    test('before the stairs up: "In about N steps, take the stairs up to Floor 1."', () {
      final r = planner.plan(twoFloorMap, 'entrance', 'cafe');
      final i = at(r, 0, 0);
      expect(i.kind, InstructionKind.changeFloor);
      expect(i.steps, 10);
      expect(i.text, 'In about 10 steps, take the stairs up to Floor 1.');
    });

    test('within turnNowSteps and on the stairs: "Take the stairs up to Floor 1."', () {
      final r = planner.plan(twoFloorMap, 'entrance', 'cafe');
      final near = at(r, 0, 10 - turnNowSteps);
      expect(near.kind, InstructionKind.changeFloor);
      expect(near.steps, turnNowSteps);
      expect(near.text, 'Take the stairs up to Floor 1.');

      final on = at(r, 1, 0);
      expect(on.kind, InstructionKind.changeFloor);
      expect(on.steps, isNull);
      expect(on.text, 'Take the stairs up to Floor 1.');
    });

    test('coming back: "take the stairs down to Floor 0"', () {
      final r = planner.plan(twoFloorMap, 'cafe', 'entrance');
      expect(at(r, 0, 0).text, 'In about 8 steps, take the stairs down to Floor 0.');
      expect(at(r, 1, 0).text, 'Take the stairs down to Floor 0.');
      expect(at(r, 2, 0).text, 'Walk straight, about 10 steps.');
    });

    test('a 0-step lift as the last leg: its foot is not arrival', () {
      final r = planner.plan(twoFloorMap, 'entrance', 'lift_1');
      expect([for (final l in r.legs) l.corridorId], ['c4', 'c5']);
      expect(at(r, 1, 0).text, 'Take the lift up to Floor 1.');
      expect(at(r, 1, 1).kind, InstructionKind.arrive);
    });
  });

  group('Tracker', () {
    test('walking up to the stairs moves onto them; steps and turns are ignored there', () {
      final (tracker, r) = trackerFor('entrance', 'cafe');
      var p = walk(tracker, 9);
      expect((p.legIndex, p.stepsAlong), (0, 9));

      p = walk(tracker, 1);
      expect((p.legIndex, p.stepsAlong), (1, 0));
      expect(guide.next(r, p).text, 'Take the stairs up to Floor 1.');

      p = walk(tracker, 30);
      expect((p.legIndex, p.stepsAlong), (1, 0));
      p = tracker.onTurn(TurnEvent(t += 500, 180));
      expect((p.legIndex, p.stepsAlong, p.offRoute), (1, 0, false));
    });

    test('onFloorChange up completes the stairs; then walk to arrival', () {
      final (tracker, r) = trackerFor('entrance', 'cafe');
      walk(tracker, 10);
      var p = tracker.onFloorChange(1);
      expect((p.legIndex, p.stepsAlong), (2, 0));
      expect(p.anchoredBy, AnchorSource.floor);

      // The left turn off the landing comes just after: it's the landing's turn.
      p = tracker.onTurn(TurnEvent(t += 500, 90));
      expect((p.legIndex, p.offRoute), (2, false));

      p = walk(tracker, 8);
      expect(guide.next(r, p).kind, InstructionKind.arrive);
    });

    test('onFloorChange completes the stairs even before the walk reaches them', () {
      final (tracker, _) = trackerFor('entrance', 'cafe');
      walk(tracker, 7);
      final p = tracker.onFloorChange(1);
      expect((p.legIndex, p.stepsAlong), (2, 0));
    });

    test('a floor change the wrong way, or with no transition ahead, is ignored', () {
      final (tracker, _) = trackerFor('entrance', 'cafe');
      walk(tracker, 10);
      var p = tracker.onFloorChange(-1);
      expect((p.legIndex, p.stepsAlong), (1, 0));
      expect(tracker.onFloorChange(0).legIndex, 1);

      p = tracker.onFloorChange(1);
      expect(p.legIndex, 2);
      p = tracker.onFloorChange(1);
      expect((p.legIndex, p.stepsAlong, p.anchoredBy), (2, 0, AnchorSource.floor));
    });

    test('"I am here" at the top of the stairs completes them too', () {
      final (tracker, _) = trackerFor('entrance', 'cafe');
      walk(tracker, 10);
      final p = tracker.tapHere('stairs_top');
      expect((p.legIndex, p.stepsAlong, p.anchoredBy), (2, 0, AnchorSource.tap));
    });

    test('down: a right turn near the stairs moves onto them, -1 completes them', () {
      final (tracker, r) = trackerFor('cafe', 'entrance');
      walk(tracker, 6);
      // c3 reversed heads 270, the stairs down head 180: a right turn.
      var p = tracker.onTurn(TurnEvent(t += 500, -90));
      expect((p.legIndex, p.stepsAlong, p.anchoredBy), (1, 0, AnchorSource.turn));
      expect(guide.next(r, p).text, 'Take the stairs down to Floor 0.');

      p = tracker.onFloorChange(-1);
      expect((p.legIndex, p.stepsAlong), (2, 0));
      p = walk(tracker, 10);
      expect(guide.next(r, p).kind, InstructionKind.arrive);
    });

    test('a 0-step lift as the last leg: onFloorChange arrives', () {
      final (tracker, r) = trackerFor('entrance', 'lift_1');
      var p = walk(tracker, 4);
      expect((p.legIndex, p.stepsAlong), (1, 0));
      expect(guide.next(r, p).kind, InstructionKind.changeFloor);

      p = tracker.onFloorChange(1);
      expect((p.legIndex, p.stepsAlong), (1, 1));
      expect(guide.next(r, p).kind, InstructionKind.arrive);
    });

    test('a lift over two floors needs two floors of change', () {
      const map = MapGraph(
        name: 'Tall',
        start: 'g',
        places: [
          Place(id: 'g', name: 'Ground', kind: PlaceKind.start),
          Place(id: 'top', name: 'Roof', kind: PlaceKind.place, floor: 2),
          Place(id: 'deck', name: 'Deck', kind: PlaceKind.place, floor: 2),
        ],
        corridors: [
          Corridor(
            id: 'lift',
            from: 'g',
            to: 'top',
            steps: 0,
            heading: 0,
            kind: CorridorKind.lift,
            floorDelta: 2,
          ),
          Corridor(id: 'c1', from: 'top', to: 'deck', steps: 5, heading: 0),
        ],
      );
      final (tracker, _) = trackerFor('g', 'deck', map);
      expect(tracker.onFloorChange(1).legIndex, 0);
      expect(tracker.onFloorChange(-1).legIndex, 0);
      expect(tracker.onFloorChange(1).legIndex, 1);

      // The app's one tap passes the whole floorDelta.
      tracker.setRoute(planner.plan(map, 'g', 'deck'));
      expect(tracker.onFloorChange(2).legIndex, 1);
    });
  });

  test('legLength counts a 0-step transition as one', () {
    const walkLeg = Leg(corridorId: 'a', reversed: false, heading: 0, steps: 0);
    const lift = Leg(
      corridorId: 'b',
      reversed: false,
      heading: 0,
      steps: 0,
      kind: CorridorKind.lift,
      floorDelta: 1,
    );
    const stairs = Leg(
      corridorId: 'c',
      reversed: false,
      heading: 0,
      steps: 12,
      kind: CorridorKind.stairs,
      floorDelta: 1,
    );
    expect(legLength(walkLeg), 0);
    expect(legLength(lift), 1);
    expect(legLength(stairs), 12);
  });
}
