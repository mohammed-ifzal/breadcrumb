import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/route_planner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_maps.dart';

void main() {
  final planner = DijkstraRoutePlanner();

  test('the heading convention: left is positive, right is negative', () {
    expect(turnBetween(0, 90), 90); // c1 -> c2 in the demo: a left turn
    expect(turnBetween(90, 0), -90); // c3 -> c4: a right turn
    expect(turnBetween(350, 10), 20);
    expect(turnBetween(10, 350), -20);
    expect(turnBetween(0, 180), 180); // (-180, 180]
    expect(reversedHeading(0), 180);
    expect(reversedHeading(270), 90);
  });

  group('routes between every pair of places, both directions', () {
    const expectedSteps = {
      ('start', 'food_counter'): 22,
      ('start', 'stage_side'): 36,
      ('food_counter', 'stage_side'): 14,
    };

    for (final MapEntry(key: (a, b), value: steps) in expectedSteps.entries) {
      test('$a <-> $b', () {
        final there = planner.plan(demoMap, a, b);
        final back = planner.plan(demoMap, b, a);

        expect(there.totalSteps, steps);
        expect(back.totalSteps, steps);
        expect(there.toId, b);
        expect(back.toId, a);
        expect(there.legs.every((l) => !l.reversed), isTrue);
        expect(back.legs.every((l) => l.reversed), isTrue);
        expect(
          back.legs.map((l) => l.corridorId).toList(),
          there.legs.reversed.map((l) => l.corridorId).toList(),
        );
        // Each reversed leg's heading is the forward heading + 180.
        for (var i = 0; i < there.legs.length; i++) {
          final forward = there.legs[i];
          final reverse = back.legs[back.legs.length - 1 - i];
          expect(reverse.heading, reversedHeading(forward.heading));
          expect(reverse.steps, forward.steps);
        }
      });
    }
  });

  test('stage_side back to start: reversed legs, so left and right swap', () {
    final r = planner.plan(demoMap, 'stage_side', 'start');

    expect([for (final l in r.legs) l.corridorId], ['c4', 'c3', 'c2', 'c1']);
    expect([for (final l in r.legs) l.heading], [180, 270, 270, 180]);
    // Forward, j2 was a right turn (90 -> 0); walked back it is a left turn.
    expect(turnBetween(r.legs[0].heading, r.legs[1].heading), 90);
    // Forward, j1 was a left turn (0 -> 90); walked back it is a right turn.
    expect(turnBetween(r.legs[2].heading, r.legs[3].heading), -90);
  });

  test('picks the fewest steps, not the fewest corridors', () {
    const map = MapGraph(
      name: 'Two ways',
      start: 'a',
      places: [
        Place(id: 'a', name: 'A', kind: PlaceKind.start),
        Place(id: 'j1', name: 'J1', kind: PlaceKind.junction),
        Place(id: 'b', name: 'B', kind: PlaceKind.place),
      ],
      corridors: [
        Corridor(id: 'long', from: 'a', to: 'b', steps: 50, heading: 0),
        Corridor(id: 'x', from: 'a', to: 'j1', steps: 10, heading: 90),
        Corridor(id: 'y', from: 'b', to: 'j1', steps: 10, heading: 0),
      ],
    );

    final r = planner.plan(map, 'a', 'b');

    expect(r.totalSteps, 20);
    expect([for (final l in r.legs) l.corridorId], ['x', 'y']);
    expect(r.legs[1].reversed, isTrue);
    expect(r.legs[1].heading, 180);
  });

  test('from a place to itself is an empty route', () {
    final r = planner.plan(demoMap, 'food_counter', 'food_counter');
    expect(r.legs, isEmpty);
    expect(r.totalSteps, 0);
  });

  test('unknown or unreachable places throw ArgumentError', () {
    const island = MapGraph(
      name: 'Island',
      start: 'a',
      places: [
        Place(id: 'a', name: 'A', kind: PlaceKind.start),
        Place(id: 'b', name: 'B', kind: PlaceKind.place),
      ],
      corridors: [],
    );
    expect(() => planner.plan(island, 'a', 'b'), throwsArgumentError);
    expect(() => planner.plan(demoMap, 'start', 'moon'), throwsArgumentError);
  });
}
