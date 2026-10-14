import 'package:breadcrumb/app/screens/record_screen.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('timeline reads start, steps, snapped turns and marked places in walk order', () {
    const map = MapGraph(
      name: 'Walk',
      start: 's',
      places: [
        Place(id: 's', name: 'Entrance', kind: PlaceKind.start),
        Place(id: 'j1', name: 'j1', kind: PlaceKind.junction),
        Place(id: 'p1', name: 'Cafe', kind: PlaceKind.place),
        Place(id: hereId, name: 'You are here', kind: PlaceKind.junction),
      ],
      corridors: [
        Corridor(id: 'c1', from: 's', to: 'j1', steps: 45, heading: 0),
        Corridor(id: 'c2', from: 'j1', to: 'p1', steps: 18, heading: 90),
        Corridor(id: 'c3', from: 'p1', to: hereId, steps: 1, heading: 0),
      ],
    );

    expect(trailTimeline(map), ['Entrance', '45 steps', 'Left', '18 steps', 'Cafe', 'Right', '1 step']);
  });

  test('timeline shows a U-turn, a floor change and no zero-step segment', () {
    const map = MapGraph(
      name: 'Floors',
      start: 's',
      places: [
        Place(id: 's', name: 'Gate', kind: PlaceKind.start),
        Place(id: 'j1', name: 'j1', kind: PlaceKind.junction),
        Place(id: 'j2', name: 'j2', kind: PlaceKind.junction, floor: 1),
        Place(id: hereId, name: 'You are here', kind: PlaceKind.junction, floor: 1),
      ],
      corridors: [
        Corridor(id: 'c1', from: 's', to: 'j1', steps: 10, heading: 0),
        Corridor(id: 'c2', from: 'j1', to: 'j2', steps: 0, heading: 0, kind: CorridorKind.stairs, floorDelta: 1),
        Corridor(id: 'c3', from: 'j2', to: hereId, steps: 0, heading: 180),
      ],
    );

    expect(trailTimeline(map), ['Gate', '10 steps', 'Stairs up']);
  });

  test('a turn right after a corridor shows before any new steps', () {
    const map = MapGraph(
      name: 'Turn',
      start: 's',
      places: [
        Place(id: 's', name: 'Desk', kind: PlaceKind.start),
        Place(id: 'j1', name: 'j1', kind: PlaceKind.junction),
        Place(id: hereId, name: 'You are here', kind: PlaceKind.junction),
      ],
      corridors: [
        Corridor(id: 'c1', from: 's', to: 'j1', steps: 6, heading: 0),
        Corridor(id: 'c2', from: 'j1', to: hereId, steps: 0, heading: 180),
      ],
    );

    expect(trailTimeline(map), ['Desk', '6 steps', 'U-turn']);
  });
}
