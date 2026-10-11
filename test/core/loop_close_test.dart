import 'dart:convert';

import 'package:breadcrumb/core/contracts.dart' as c;
import 'package:breadcrumb/core/map_builder.dart';
import 'package:breadcrumb/core/route_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void walk(MapBuilder b, int n) {
  for (var i = 0; i < n; i++) {
    b.onStep(c.StepEvent(i * 400));
  }
}

void main() {
  test(
    'square loop reuses trimmed case-insensitive start and JSON round-trips',
    () {
      final b = MapBuilder()..start('Entrance');
      for (var i = 0; i < 3; i++) {
        walk(b, 5);
        b.onTurn(const c.TurnEvent(0, 90));
      }
      walk(b, 5);
      b.addPlace('  eNtRaNcE  ', ['ignored']);
      final map = b.finish();
      expect(map.places, hasLength(4));
      expect(
        map.places.where(
          (p) => p.kind == c.PlaceKind.start || p.kind == c.PlaceKind.place,
        ),
        hasLength(1),
      );
      expect(map.corridors.map((e) => e.steps), [5, 5, 5, 5]);
      expect(map.corridors.map((e) => e.heading), [0, 90, 180, 270]);
      expect(map.corridors.last.to, map.start);
      expect(map.corridors.last.from, 'j3');
      expect(map.places.map((p) => p.id).toSet().length, map.places.length);
      expect(
        c.MapGraph.fromJson(
          jsonDecode(jsonEncode(map.toJson())) as Map<String, dynamic>,
        ).toJson(),
        map.toJson(),
      );
      expect(b.finish().toJson(), map.toJson());
    },
  );
  test(
    'Dijkstra chooses shorter side in both directions around closed loop',
    () {
      final b = MapBuilder()..start('Entrance');
      walk(b, 10);
      b.onTurn(const c.TurnEvent(0, 90));
      walk(b, 10);
      b.addPlace('Far', []);
      b.onTurn(const c.TurnEvent(0, 90));
      walk(b, 3);
      b.onTurn(const c.TurnEvent(0, 90));
      walk(b, 4);
      b.addPlace('entrance', []);
      final map = b.finish();
      final far = map.places.singleWhere((p) => p.name == 'Far').id;
      final planner = DijkstraRoutePlanner();
      final forward = planner.plan(map, map.start, far);
      final reverse = planner.plan(map, far, map.start);
      expect(forward.totalSteps, 7);
      expect(reverse.totalSteps, 7);
      expect(forward.legs.every((l) => l.reversed), isTrue);
      expect(reverse.legs.every((l) => !l.reversed), isTrue);
      expect(forward.legs.first.corridorId, map.corridors.last.id);
      expect(planner.plan(map, map.start, map.start).legs, isEmpty);
    },
  );
  test('duplicate named place preserves node and aliases, then recording continues', () {
    final b = MapBuilder()..start('Start');
    walk(b, 2);
    b.addPlace('Desk', ['reception']);
    final desk = b.snapshot().places.singleWhere((p) => p.name == 'Desk');
    walk(b, 3);
    b.onTurn(const c.TurnEvent(0, 90));
    walk(b, 4);
    b.addPlace(' DESK ', ['overwrite']);
    final closed = b.snapshot();
    expect(closed.places.where((p) => p.name == 'Desk'), hasLength(1));
    expect(closed.corridors[closed.corridors.length - 2].to, desk.id);
    expect(closed.corridors[closed.corridors.length - 2].steps, 4);
    expect(closed.corridors[closed.corridors.length - 2].heading, 90);
    expect(closed.places.singleWhere((p) => p.id == desk.id).aliases, [
      'reception',
    ]);
    expect(b.snapshot().toJson(), closed.toJson());
    walk(b, 1);
    b.addPlace('Exit', []);
    expect(b.finish().corridors.last.from, desk.id);
    expect(b.finish().places.last.id, 'p2');
  });
  test('same current name without steps adds no self corridor or node', () {
    final b = MapBuilder()..start('Start');
    b.addPlace(' START ', []);
    expect(b.finish().corridors, isEmpty);
    b.start('Start');
    walk(b, 2);
    b.addPlace('Desk', []);
    b.addPlace('desk', []);
    final map = b.finish();
    expect(map.places, hasLength(2));
    expect(map.corridors, hasLength(1));
    expect(map.corridors.any((e) => e.from == e.to && e.steps == 0), isFalse);
  });
  test('junction names never match and closing to another named place at zero steps is safe', () {
    final b = MapBuilder()..start('Start');
    walk(b, 2);
    b.onTurn(const c.TurnEvent(0, 90));
    b.addPlace('Junction 1', []);
    final map = b.finish();
    expect(map.places.where((p) => p.name == 'Junction 1'), hasLength(2));
    expect(map.places.last.kind, c.PlaceKind.place);
    expect(map.places.last.id, 'p1');
    b.start('Start');
    b.addPlace('Desk', []);
    b.addPlace('start', []);
    final zero = b.finish();
    expect(zero.places, hasLength(2));
    expect(zero.corridors.every((e) => e.from != e.to), isTrue);
    expect(DijkstraRoutePlanner().plan(zero, zero.start, 'p1').totalSteps, 0);
  });
}
