import 'package:breadcrumb/core/contracts.dart' hide MapBuilder;
import 'package:breadcrumb/core/map_builder.dart';
import 'package:breadcrumb/core/map_json.dart';
import 'package:flutter_test/flutter_test.dart';

/// D33: "Undo last mark" takes back a place but never the walk.
void main() {
  void walk(MapBuilder b, int steps) {
    for (var i = 0; i < steps; i++) {
      b.onStep(StepEvent(i));
    }
  }

  List<String> names(MapGraph m) => [
    for (final p in m.places)
      if (p.kind != PlaceKind.junction) p.name,
  ];

  int totalSteps(MapGraph m) => m.corridors.fold(0, (s, c) => s + c.steps);

  test('nothing to undo before a mark or before start', () {
    final b = MapBuilder();
    expect(b.undoLastMark(), isNull);
    b.start('Desk');
    walk(b, 4);
    expect(b.undoableMarks, 0);
    expect(b.undoLastMark(), isNull);
  });

  test('undo right after a mark folds its steps back into the open walk', () {
    final b = MapBuilder()..start('Desk');
    walk(b, 5);
    b.addPlace('Cafe', const []);
    expect(b.undoableMarks, 1);
    walk(b, 3);
    expect(b.undoLastMark(), 'Cafe');
    expect(b.undoableMarks, 0);
    final map = b.finish();
    expect(names(map), ['Desk']);
    // One straight corridor of all 8 steps to the end junction.
    expect(map.corridors, hasLength(1));
    expect(map.corridors.single.steps, 8);
    decodeMap(encodeMap(map));
  });

  test('a new mark after undo reuses the freed place ID', () {
    final b = MapBuilder()..start('Desk');
    walk(b, 5);
    b.addPlace('Cafe', const []);
    b.undoLastMark();
    walk(b, 2);
    b.addPlace('Coffee bar', const []);
    final map = b.finish();
    expect(names(map), ['Desk', 'Coffee bar']);
    expect(map.places.last.id, 'p1');
    expect(map.corridors.single.steps, 7);
  });

  test(
    'undo after a turn keeps the geometry and turns the place into a junction',
    () {
      final b = MapBuilder()..start('Desk');
      walk(b, 5);
      b.addPlace('Cafe', const []);
      walk(b, 2);
      b.onTurn(const TurnEvent(0, 90));
      walk(b, 4);
      final before = b.snapshot();
      expect(b.undoLastMark(), 'Cafe');
      final after = b.snapshot();
      expect(names(after), ['Desk']);
      expect(
        after.corridors.map((c) => c.toJson()).toList(),
        before.corridors.map((c) => c.toJson()).toList(),
      );
      expect(totalSteps(b.finish()), 11);
      decodeMap(encodeMap(b.finish()));
    },
  );

  test('undoing a loop join right away reopens the loop', () {
    final b = MapBuilder()..start('Desk');
    walk(b, 5);
    b.addPlace('Cafe', const []);
    walk(b, 5);
    b.addPlace('Desk', const []); // join
    expect(b.snapshot().corridors[1].to, 'p0');
    expect(b.undoLastMark(), 'Desk');
    walk(b, 2);
    final map = b.finish();
    expect(names(map), ['Desk', 'Cafe']);
    expect(map.corridors.where((c) => c.to == 'p0'), isEmpty);
    expect(map.corridors.last.steps, 7);
  });

  test(
    'undoing a join after more walking gives that visit its own junction',
    () {
      final b = MapBuilder()..start('Desk');
      walk(b, 5);
      b.addPlace('Cafe', const []);
      walk(b, 5);
      b.addPlace('Desk', const []); // join
      walk(b, 3);
      b.onTurn(const TurnEvent(0, -90));
      walk(b, 2);
      expect(b.undoLastMark(), 'Desk');
      final map = b.finish();
      expect(
        map.corridors.where((c) => c.to == 'p0' || c.from == 'p0'),
        hasLength(1),
        reason: 'only the first corridor touches Desk',
      );
      expect(totalSteps(map), 15);
      decodeMap(encodeMap(map));
    },
  );

  test('marks undo newest first, then stop', () {
    final b = MapBuilder()..start('Desk');
    walk(b, 3);
    b.addPlace('A', const []);
    walk(b, 3);
    b.addPlace('B', const []);
    expect(b.undoLastMark(), 'B');
    expect(b.undoLastMark(), 'A');
    expect(b.undoLastMark(), isNull);
    expect(b.finish().corridors.single.steps, 6);
  });

  test('a repeated mark with no steps adds nothing, so there is nothing extra to undo', () {
    final b = MapBuilder()..start('Desk');
    walk(b, 3);
    b.addPlace('A', const []);
    b.addPlace('A', const []);
    expect(b.undoableMarks, 1);
  });

  test('nothing to undo once finished', () {
    final b = MapBuilder()..start('Desk');
    walk(b, 3);
    b.addPlace('A', const []);
    b.finish();
    expect(b.undoableMarks, 0);
    expect(b.undoLastMark(), isNull);
  });
}
