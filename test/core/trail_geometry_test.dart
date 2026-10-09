import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/trail_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // entrance --10 steps, heading 0--> j1 --5 steps, left turn--> cafe
  // c2 is stored from cafe to j1 (heading 270), so layout must reverse it.
  const lMap = MapGraph(
    name: 'L',
    start: 'entrance',
    places: [
      Place(id: 'entrance', name: 'Entrance', kind: PlaceKind.start),
      Place(id: 'j1', name: 'Junction 1', kind: PlaceKind.junction),
      Place(id: 'cafe', name: 'Cafe', kind: PlaceKind.place),
      Place(id: 'island', name: 'Island', kind: PlaceKind.place),
    ],
    corridors: [
      Corridor(id: 'c1', from: 'entrance', to: 'j1', steps: 10, heading: 0),
      Corridor(id: 'c2', from: 'cafe', to: 'j1', steps: 5, heading: 270),
    ],
  );

  test('layoutMap walks an L: forward is +y, a left turn is -x', () {
    final points = {for (final p in layoutMap(lMap)) p.placeId: p};

    expect(points.keys, unorderedEquals(['entrance', 'j1', 'cafe']));
    expect(points['entrance']!.x, 0);
    expect(points['entrance']!.y, 0);
    expect(points['j1']!.x, closeTo(0, 1e-9));
    expect(points['j1']!.y, closeTo(10, 1e-9));
    expect(points['cafe']!.x, closeTo(-5, 1e-9));
    expect(points['cafe']!.y, closeTo(10, 1e-9));
  });

  test('layoutMap leaves out nodes not reachable from start', () {
    expect(layoutMap(lMap).map((p) => p.placeId), isNot(contains('island')));
  });
}
