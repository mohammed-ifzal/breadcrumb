import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/start_places.dart';
import 'package:flutter_test/flutter_test.dart';

/// D33: "Where are you?" lists places nearest first.
void main() {
  // Desk -10- Cafe -4- J -3- Stage, J -20- Exit; Island has no corridor.
  const map = MapGraph(
    name: 'Loop',
    start: 'desk',
    places: [
      Place(id: 'desk', name: 'Desk', kind: PlaceKind.start),
      Place(id: 'cafe', name: 'Cafe', kind: PlaceKind.place),
      Place(id: 'j', name: 'Junction 1', kind: PlaceKind.junction),
      Place(id: 'stage', name: 'Stage', kind: PlaceKind.place),
      Place(id: 'island', name: 'Island', kind: PlaceKind.place),
      Place(id: 'exit', name: 'Exit', kind: PlaceKind.place),
    ],
    corridors: [
      Corridor(id: 'c1', from: 'desk', to: 'cafe', steps: 10, heading: 0),
      Corridor(id: 'c2', from: 'cafe', to: 'j', steps: 4, heading: 0),
      Corridor(id: 'c3', from: 'j', to: 'stage', steps: 3, heading: 90),
      Corridor(id: 'c4', from: 'j', to: 'exit', steps: 20, heading: 0),
    ],
  );

  List<String> ids(List<Place> places) => [for (final p in places) p.id];

  test('the given place first, then by route steps, unreachable last', () {
    expect(ids(placesNearestFirst(map, 'exit')), [
      'exit', // 0
      'stage', // 23
      'cafe', // 24
      'desk', // 34
      'island', // no route
    ]);
    expect(ids(placesNearestFirst(map, 'cafe')), [
      'cafe',
      'stage', // 7
      'desk', // 10
      'exit', // 24
      'island',
    ]);
  });

  test('never lists junctions', () {
    expect(ids(placesNearestFirst(map, 'j')), isNot(contains('j')));
    expect(ids(placesNearestFirst(map, 'j')).first, 'stage');
  });

  test('ties keep newest-first walk order', () {
    const tie = MapGraph(
      name: 'Tie',
      start: 'a',
      places: [
        Place(id: 'a', name: 'A', kind: PlaceKind.start),
        Place(id: 'b', name: 'B', kind: PlaceKind.place),
        Place(id: 'c', name: 'C', kind: PlaceKind.place),
      ],
      corridors: [
        Corridor(id: 'c1', from: 'a', to: 'b', steps: 5, heading: 0),
        Corridor(id: 'c2', from: 'a', to: 'c', steps: 5, heading: 90),
      ],
    );
    expect(ids(placesNearestFirst(tie, 'a')), ['a', 'c', 'b']);
  });

  test('unknown start lists every place newest first', () {
    expect(ids(placesNearestFirst(map, 'nowhere')), [
      'exit',
      'island',
      'stage',
      'cafe',
      'desk',
    ]);
  });
}
