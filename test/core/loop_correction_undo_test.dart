import 'package:breadcrumb/core/contracts.dart' hide MapBuilder;
import 'package:breadcrumb/core/map_builder.dart';
import 'package:breadcrumb/core/map_json.dart';
import 'package:flutter_test/flutter_test.dart';

void walk(MapBuilder b, int count) {
  for (var i = 0; i < count; i++) {
    b.onStep(StepEvent(i));
  }
}

MapBuilder openLoop({bool correction = true}) {
  final b = MapBuilder(useLoopCorrection: correction)..start('Lead-in');
  walk(b, 5);
  b.addPlace('Loop base', []);
  for (var leg = 0; leg < 3; leg++) {
    walk(b, 10);
    b.onTurn(const TurnEvent(0, 90));
  }
  walk(b, 7);
  return b;
}

void main() {
  test(
    'Undo loop closure restores coordinates, visits and correction distances',
    () {
      final b = openLoop();
      final before = encodeMap(b.snapshot());
      final marks = b.undoableMarks;
      b.addPlace('Loop base', []);
      expect(
        b.snapshot().places.singleWhere((p) => p.id == 'j1').x,
        closeTo(30 / 37, 1e-9),
      );
      expect(b.undoLastMark(), 'Loop base');
      expect(encodeMap(b.snapshot()), before);
      expect(b.undoableMarks, marks);
      expect(b.previewLoopClosure('Loop base')!.errorSteps, 3);
      expect(b.previewLoopClosure('Loop base')!.loopSteps, 37);
      b.addPlace('Loop base', []);
      expect(
        b.snapshot().places.singleWhere((p) => p.id == 'j1').x,
        closeTo(30 / 37, 1e-9),
      );
      expect(b.undoLastMark(), 'Loop base');
      expect(encodeMap(b.snapshot()), before);
    },
  );

  test('Undo closure after open steps preserves those steps without corrected positions', () {
    final b = openLoop();
    final reference = openLoop();
    b.addPlace('Loop base', []);
    walk(b, 2);
    walk(reference, 2);
    b.undoLastMark();
    expect(encodeMap(b.snapshot()), encodeMap(reference.snapshot()));
  });

  test('Undo closure after a turn restores loop nodes and reprojects later junctions', () {
    final b = openLoop();
    final before = b.snapshot();
    b.addPlace('Loop base', []);
    walk(b, 3);
    b.onTurn(const TurnEvent(0, -90));
    walk(b, 2);
    final measured = b
        .snapshot()
        .corridors
        .map((c) => [c.id, c.steps, c.heading, c.kind, c.floorDelta])
        .toList();
    expect(b.undoLastMark(), 'Loop base');
    final after = b.snapshot();
    for (final p in before.places.where((p) => p.id != hereId)) {
      expect(
        after.places.singleWhere((a) => a.id == p.id).toJson(),
        p.toJson(),
      );
    }
    final closure = after.corridors[4];
    final detached = after.places.singleWhere((p) => p.id == closure.to);
    expect(detached.kind, PlaceKind.junction);
    expect(detached.id, isNot('p1'));
    expect(detached.x, -3);
    expect(detached.y, 5);
    final later = after.places.singleWhere(
      (p) => p.id == after.corridors[5].to,
    );
    expect(later.x, 0);
    expect(later.y, 5);
    expect(after.places.last.x, 0);
    expect(after.places.last.y, 3);
    expect(
      after.corridors
          .map((c) => [c.id, c.steps, c.heading, c.kind, c.floorDelta])
          .toList(),
      measured,
    );
    expect(after.corridors[5].from, detached.id);
    expect(decodeMap(encodeMap(b.finish())).toJson(), b.finish().toJson());
    expect(b.previewLoopClosure('Loop base'), isNull);
  });

  test('Undo a new mark after a turn retains its display coordinates', () {
    final b = MapBuilder()..start('Start');
    walk(b, 5);
    b.addPlace('Cafe', []);
    walk(b, 2);
    b.onTurn(const TurnEvent(0, 90));
    walk(b, 4);
    final before = b.snapshot();
    b.undoLastMark();
    final after = b.snapshot();
    expect(
      after.places.singleWhere((p) => p.id == 'p1').kind,
      PlaceKind.junction,
    );
    expect(after.places.singleWhere((p) => p.id == 'p1').x, 0);
    expect(after.places.singleWhere((p) => p.id == 'p1').y, 5);
    expect(after.places.last.x, before.places.last.x);
    expect(after.places.last.y, before.places.last.y);
  });

  test('flag-off closure Undo has no coordinates and keeps main geometry', () {
    final b = openLoop(correction: false);
    final before = encodeMap(b.snapshot());
    b.addPlace('Loop base', []);
    b.undoLastMark();
    expect(encodeMap(b.snapshot()), before);
    b.addPlace('Loop base', []);
    walk(b, 3);
    b.onTurn(const TurnEvent(0, 90));
    b.undoLastMark();
    final map = b.finish();
    expect(map.places.every((p) => p.x == null && p.y == null), isTrue);
    expect(map.corridors.fold<int>(0, (sum, c) => sum + c.steps), 45);
    expect(decodeMap(encodeMap(map)).toJson(), map.toJson());
  });
}
