import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/guide.dart';
import 'package:breadcrumb/core/route_planner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_maps.dart';

void main() {
  final planner = DijkstraRoutePlanner();
  final guide = RouteGuide(demoMap);

  Position at(int leg, int steps, {bool offRoute = false}) => Position(
    legIndex: leg,
    stepsAlong: steps,
    anchoredBy: AnchorSource.start,
    offRoute: offRoute,
  );

  test('far from a left turn: "In about N steps, turn left."', () {
    final r = planner.plan(demoMap, 'start', 'stage_side');
    final i = guide.next(r, at(0, 2));
    expect(i.kind, InstructionKind.turnLeft);
    expect(i.steps, 10);
    expect(i.text, 'In about 10 steps, turn left.');
  });

  test('within turnNowSteps: "Get ready to turn left." (D27)', () {
    final r = planner.plan(demoMap, 'start', 'stage_side');
    final i = guide.next(r, at(0, 9));
    expect(i.kind, InstructionKind.turnLeft);
    expect(i.text, 'Get ready to turn left.');
  });

  test('distance to a turn spans straight-on joins', () {
    final r = planner.plan(demoMap, 'start', 'stage_side');
    final i = guide.next(r, at(1, 4)); // 6 left on c2 + 8 on c3
    expect(i.kind, InstructionKind.turnRight);
    expect(i.text, 'In about 14 steps, turn right.');
  });

  test('a straight walk to the destination: "Walk straight, about N steps."', () {
    final r = planner.plan(demoMap, 'j1', 'j2'); // c2 then c3, both heading 90
    final i = guide.next(r, at(0, 3));
    expect(i.kind, InstructionKind.straight);
    expect(i.steps, 15);
    expect(i.text, 'Walk straight, about 15 steps.');
  });

  test('arrive at the end of the last leg', () {
    final r = planner.plan(demoMap, 'start', 'food_counter');
    final i = guide.next(r, at(1, 10));
    expect(i.kind, InstructionKind.arrive);
    expect(i.placeName, 'Food counter');
    expect(i.text, 'Food counter is here.');
  });

  test('a route to where you already are arrives at once', () {
    final r = planner.plan(demoMap, 'stage_side', 'stage_side');
    expect(guide.next(r, at(0, 0)).text, 'Stage side is here.');
  });

  test('navigating back, the turns swap', () {
    final r = planner.plan(demoMap, 'stage_side', 'start');
    expect(guide.next(r, at(0, 0)).text, 'In about 6 steps, turn left.');
    expect(guide.next(r, at(2, 2)).text, 'In about 8 steps, turn right.');
    expect(guide.next(r, at(2, 8)).text, 'Get ready to turn right.');
    expect(guide.next(r, at(3, 12)).text, 'Start is here.');
  });

  test('offRoute position gives the offRoute instruction', () {
    final r = planner.plan(demoMap, 'start', 'stage_side');
    final i = guide.next(r, at(0, 10, offRoute: true));
    expect(i.kind, InstructionKind.offRoute);
    expect(i.text, "Looks like you went off the path. Go back to the last corner or tap I'm here.");
  });

  test('past the counted corner it keeps saying "at the corner", never rescan (D27)', () {
    final r = planner.plan(demoMap, 'start', 'stage_side');
    for (final along in [12, 15, 16, 30]) {
      final i = guide.next(r, at(0, along));
      expect(i.kind, InstructionKind.turnLeft);
      expect(i.text, 'Turn left at the corner.');
    }
  });

  test('a U-turn between legs says "Turn around."', () {
    const map = MapGraph(
      name: 'U',
      start: 'a',
      places: [
        Place(id: 'a', name: 'A', kind: PlaceKind.start),
        Place(id: 'j1', name: 'J1', kind: PlaceKind.junction),
        Place(id: 'b', name: 'B', kind: PlaceKind.place),
      ],
      corridors: [
        Corridor(id: 'c1', from: 'a', to: 'j1', steps: 10, heading: 0),
        Corridor(id: 'c2', from: 'j1', to: 'b', steps: 5, heading: 180),
      ],
    );
    final r = planner.plan(map, 'a', 'b');
    final g = RouteGuide(map);
    expect(g.next(r, at(0, 2)).kind, InstructionKind.straight);
    final i = g.next(r, at(0, 8));
    expect(i.kind, InstructionKind.turnAround);
    expect(i.text, 'Turn around.');
  });
}
