import 'package:breadcrumb/app/widgets/trail_view.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/route_planner.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The "Final demo v2" layout: food court sits 4 steps from gaming room, so
/// their labels collide at phone size.
MapGraph demoLoop() {
  Place n(String id, String name, PlaceKind kind) =>
      Place(id: id, name: name, kind: kind);
  Corridor c(String id, String a, String b, double h, int s) =>
      Corridor(id: id, from: a, to: b, steps: s, heading: h);
  return MapGraph(
    name: 'Final demo v2',
    start: 'p0',
    places: [
      n('p0', 'team groza table', PlaceKind.start),
      n('j1', 'Junction 1', PlaceKind.junction),
      n('p1', 'gaming room', PlaceKind.place),
      n('p2', 'food court', PlaceKind.place),
      n('j5', 'Junction 5', PlaceKind.junction),
      n('p3', 'exit', PlaceKind.place),
      n('j6', 'Junction 6', PlaceKind.junction),
      n('j7', 'Junction 7', PlaceKind.junction),
      n('j8', 'Junction 8', PlaceKind.junction),
      n('p4', 'washroom', PlaceKind.place),
      n('p5', 'entrance', PlaceKind.place),
      n('j13', 'Junction 13', PlaceKind.junction),
      n('p6', 'main stage', PlaceKind.place),
      n('jA', 'Junction 15', PlaceKind.junction),
      n('jB', 'Junction 16', PlaceKind.junction),
    ],
    corridors: [
      c('c1', 'p0', 'jB', 0, 2),
      c('c15', 'jB', 'j1', 0, 6),
      c('c2', 'j1', 'p1', 90, 20),
      c('c3', 'p1', 'p2', 180, 4),
      c('c4', 'p1', 'j5', 90, 9),
      c('c5', 'j5', 'p3', 0, 12),
      c('c6', 'p3', 'j6', 0, 5),
      c('c7', 'j6', 'j7', 270, 11),
      c('c8', 'j7', 'j8', 0, 15),
      c('c9', 'j8', 'p4', 90, 4),
      c('c10', 'j7', 'j13', 270, 22),
      c('c11', 'j13', 'p5', 270, 9),
      c('c12', 'j13', 'p6', 180, 9),
      c('c13', 'p6', 'jA', 180, 14),
      c('c14', 'jA', 'jB', 90, 4),
    ],
  );
}

void main() {
  final map = demoLoop();
  final names = [
    for (final p in map.places)
      if (p.kind != PlaceKind.junction) p.name,
  ];

  for (final size in [
    const Size(320, 375),
    const Size(360, 420),
    const Size(400, 460),
  ]) {
    test('every place keeps a label, none overlap, at $size', () {
      final labels = TrailPainter(map, null, null).labelsFor(size);
      expect(labels.map((l) => l.$1), unorderedEquals(names));
      for (var i = 0; i < labels.length; i++) {
        for (var j = i + 1; j < labels.length; j++) {
          expect(
            labels[i].$2.overlaps(labels[j].$2),
            isFalse,
            reason: '${labels[i].$1} overlaps ${labels[j].$1}',
          );
        }
      }
    });
  }

  test("a label does not cover another place's dot", () {
    const size = Size(360, 420);
    final painter = TrailPainter(map, null, null);
    final labels = painter.labelsFor(size);
    final foodDot = painter.toOffset(-20, 4, size);
    final gaming = labels.firstWhere((l) => l.$1 == 'gaming room').$2;
    expect(
      gaming.overlaps(Rect.fromCircle(center: foodDot, radius: 7)),
      isFalse,
    );
  });

  test('junctions stay unlabelled', () {
    final labels = TrailPainter(
      map,
      null,
      null,
    ).labelsFor(const Size(360, 420));
    expect(labels.map((l) => l.$1), isNot(contains(startsWith('Junction'))));
  });

  test('food court is labelled next to gaming room with a route shown', () {
    final route = DijkstraRoutePlanner().plan(map, 'p6', 'p2');
    final labels = TrailPainter(
      map,
      route,
      null,
    ).labelsFor(const Size(360, 420));
    expect(labels.map((l) => l.$1), containsAll(['food court', 'gaming room']));
  });

  test(
    'a crowded spot still shows every label (may overlap, never hidden)',
    () {
      // Five places within a few steps: more than four free sides can hold.
      final crowd = MapGraph(
        name: 'Crowd',
        start: 'a',
        places: [
          for (final id in ['a', 'b', 'c', 'd', 'e'])
            Place(
              id: id,
              name: 'Place $id',
              kind: id == 'a' ? PlaceKind.start : PlaceKind.place,
            ),
        ],
        corridors: const [
          Corridor(id: 'c1', from: 'a', to: 'b', steps: 1, heading: 0),
          Corridor(id: 'c2', from: 'b', to: 'c', steps: 1, heading: 90),
          Corridor(id: 'c3', from: 'c', to: 'd', steps: 1, heading: 180),
          Corridor(id: 'c4', from: 'd', to: 'e', steps: 1, heading: 270),
        ],
      );
      final labels = TrailPainter(
        crowd,
        null,
        null,
      ).labelsFor(const Size(200, 200));
      expect(labels, hasLength(5));
    },
  );
}
