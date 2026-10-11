import 'dart:convert';
import 'dart:io';

import 'package:breadcrumb/ai/alias_suggester.dart';
import 'package:breadcrumb/core/map_json.dart';
import 'package:breadcrumb/core/route_planner.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/map_builder.dart' as recording;
import 'package:breadcrumb/core/trail_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

MapGraph driftedLoop() {
  final b = recording.MapBuilder()..start('Start');
  for (var leg = 0; leg < 4; leg++) {
    final steps = leg == 3 ? 7 : 10;
    for (var i = 0; i < steps; i++) {
      b.onStep(StepEvent(leg * 10000 + i * 400));
    }
    if (leg < 3) b.onTurn(TurnEvent(leg * 10000 + 5000, 90));
  }
  b.addPlace('Start', const []);
  return b.finish();
}

void main() {
  test(
    'legacy demo and sample JSON, layout and all routes are unchanged',
    () async {
      final baseline = jsonDecode(
        await File('test/core/fixtures/loop_correction_baseline.json')
            .readAsString(),
      ) as Map;
      for (final path in [
        'assets/maps/demo_route.json',
        'tools/sample_map.json',
      ]) {
        final map = decodeMap(await File(path).readAsString());
        final old = baseline[path] as Map;
        expect(map.toJson(), old['map'], reason: path);
        expect(
          [
            for (final p in layoutMap(map))
              {'id': p.placeId, 'x': p.x, 'y': p.y},
          ],
          old['layout'],
          reason: path,
        );
        expect(allRoutes(map), old['routes'], reason: path);
        expect(decodeMap(encodeMap(map)).toJson(), map.toJson());
        expect(map.places.every((p) => p.x == null && p.y == null), isTrue);
      }
    },
  );
  test('optional x/y accept integer and double JSON and stay absent on legacy places', () {
    final placed = Place.fromJson({
      'id': 'a',
      'name': 'A',
      'aliases': [],
      'kind': 'start',
      'x': 3,
      'y': -2.5,
    });
    expect(placed.x, 3.0);
    expect(placed.y, -2.5);
    expect(Place.fromJson(placed.toJson()).toJson(), placed.toJson());
    final legacy = Place(id: 'a', name: 'A', kind: PlaceKind.start);
    expect(legacy.toJson().containsKey('x'), isFalse);
    expect(legacy.toJson().containsKey('y'), isFalse);
    expect(Place.fromJson(legacy.toJson()).toJson(), legacy.toJson());
    final partial = Place.fromJson({...legacy.toJson(), 'x': 3});
    expect(partial.x, 3);
    expect(partial.y, isNull);
    final map = MapGraph(
      name: 'Partial',
      start: 'a',
      places: [partial],
      corridors: [],
    );
    expect(layoutMap(map).single.x, 0);
    expect(decodeMap(encodeMap(map)).toJson(), map.toJson());
  });
  test('alias application preserves corrected x/y', () {
    final map = MapGraph(
      name: 'M',
      start: 's',
      places: const [
        Place(id: 's', name: 'Entrance', kind: PlaceKind.start, x: 0, y: 0),
        Place(id: 'p', name: 'Desk', kind: PlaceKind.place, x: 2.5, y: -7),
      ],
      corridors: const [
        Corridor(id: 'c', from: 's', to: 'p', steps: 8, heading: 90),
      ],
    );
    final aliased = applyAliases(map, {
      'p': ['coffee'],
    });
    expect(aliased.places.last.aliases, contains('coffee'));
    expect(aliased.places.last.x, 2.5);
    expect(aliased.places.last.y, -7);
    expect(decodeMap(encodeMap(aliased)).toJson(), aliased.toJson());
  });
  test(
    'drift correction preserves every stored corridor and all-pairs routes',
    () async {
      final baseline = jsonDecode(
        await File('test/core/fixtures/loop_correction_baseline.json')
            .readAsString(),
      ) as Map;
      final old = baseline['drifted_loop'] as Map;
      final corrected = driftedLoop();
      expect([
        for (final c in corrected.corridors) c.toJson(),
      ], old['corridors']);
      expect(allRoutes(corrected), old['routes']);
      expect(decodeMap(encodeMap(corrected)).toJson(), corrected.toJson());
    },
  );
  test('length-weighted correction pins lead-in and the target', () {
    final b = recording.MapBuilder()..start('Lead-in');
    walk(b, 5);
    b.addPlace('Loop base', []);
    final lead = b.snapshot().places.first.toJson();
    final anchor = b
        .snapshot()
        .places
        .singleWhere((p) => p.name == 'Loop base')
        .toJson();
    for (var leg = 0; leg < 3; leg++) {
      walk(b, 10);
      b.onTurn(const TurnEvent(0, 90));
    }
    walk(b, 7);
    final preview = b.previewLoopClosure('loop BASE')!;
    expect(preview.errorSteps, 3);
    expect(preview.loopSteps, 37);
    expect(preview.requiresConfirmation, isFalse);
    b.addPlace('Loop base', []);
    final map = b.finish();
    expect(map.places.first.toJson(), lead);
    expect(
      map.places.singleWhere((p) => p.name == 'Loop base').toJson(),
      anchor,
    );
    expect(
      map.places.singleWhere((p) => p.id == 'j1').x,
      closeTo(30 / 37, 1e-9),
    );
    expect(
      map.places.singleWhere((p) => p.id == 'j2').x,
      closeTo(-10 + 60 / 37, 1e-9),
    );
    expect(
      map.places.singleWhere((p) => p.id == 'j3').x,
      closeTo(-10 + 90 / 37, 1e-9),
    );
    expect(map.corridors.map((c) => c.steps), [5, 10, 10, 10, 7]);
    expect(map.corridors.map((c) => c.heading), [0, 0, 90, 180, 270]);
  });
  test('zero-error closure changes no node positions', () {
    final b = recording.MapBuilder()..start('Start');
    for (var leg = 0; leg < 3; leg++) {
      walk(b, 10);
      b.onTurn(const TurnEvent(0, 90));
    }
    walk(b, 10);
    final before = b
        .snapshot()
        .places
        .where((p) => p.id != hereId)
        .map((p) => p.toJson())
        .toList();
    expect(b.previewLoopClosure('Start')!.errorSteps, 0);
    b.addPlace('Start', []);
    expect(b.finish().places.map((p) => p.toJson()).toList(), before);
  });
  test('single corridor and current-place closures avoid division and invalid edges', () {
    final b = recording.MapBuilder()..start('Start');
    final before = b.snapshot().toJson();
    expect(b.previewLoopClosure('Start')!.requiresConfirmation, isFalse);
    b.addPlace('Start', []);
    expect(b.snapshot().toJson(), before);
    walk(b, 4);
    expect(b.previewLoopClosure('Start')!.requiresConfirmation, isTrue);
    b.addPlace('Start', []);
    final map = b.finish();
    expect(map.places, hasLength(1));
    expect(map.places.single.x, 0);
    expect(map.places.single.y, 0);
    expect(map.corridors.single.steps, 4);
    expect(decodeMap(encodeMap(map)).toJson(), map.toJson());
  });
  test(
    '35 percent is inclusive safe; strictly greater requests confirmation',
    () {
      expect(
        const recording.LoopClosurePreview(
          placeName: 'P',
          errorSteps: 7,
          loopSteps: 20,
        ).requiresConfirmation,
        isFalse,
      );
      expect(
        const recording.LoopClosurePreview(
          placeName: 'P',
          errorSteps: 7.01,
          loopSteps: 20,
        ).requiresConfirmation,
        isTrue,
      );
    },
  );
  test(
    'a later loop pins every node recorded before its latest target visit',
    () {
      final b = recording.MapBuilder()..start('Start');
      for (var leg = 0; leg < 3; leg++) {
        walk(b, 10);
        b.onTurn(const TurnEvent(0, 90));
      }
      walk(b, 7);
      b.addPlace('Start', []);
      final before = b
          .snapshot()
          .places
          .where((p) => p.id != hereId)
          .map((p) => p.toJson())
          .toList();
      for (var leg = 0; leg < 3; leg++) {
        walk(b, 6);
        b.onTurn(const TurnEvent(0, 90));
      }
      walk(b, 4);
      b.addPlace('Start', []);
      final map = b.finish();
      expect(
        map.places.take(before.length).map((p) => p.toJson()).toList(),
        before,
      );
    },
  );
  test(
    'drifted loop positions supplied by JSON must survive load and layout',
    () {
      final raw = driftedLoop().toJson();
      // Illustrative corrected positions. This checks authoritative coordinate
      // preservation, not a particular correction-distribution algorithm.
      const positions = {
        'p0': [0, 0],
        'j1': [0.8, 10],
        'j2': [-8.4, 10],
        'j3': [-7.6, 0],
      };
      for (final row in raw['places'] as List<Map<String, dynamic>>) {
        final xy = positions[row['id']]!;
        row['x'] = xy[0];
        row['y'] = xy[1];
      }
      final decoded = MapGraph.fromJson(raw);
      final points = {for (final p in layoutMap(decoded)) p.placeId: p};
      expect(
        points['j1']!.x,
        closeTo(0.8, 1e-9),
        reason:
            'Corrected coordinates must not be discarded and replaced by BFS',
      );
      expect(decoded.toJson(), raw);
    },
  );

  test('closing a drifted recording must persist its display positions', () {
    final map = driftedLoop();
    expect(map.corridors.map((c) => c.steps), [10, 10, 10, 7]);
    expect(map.corridors.map((c) => c.heading), [0, 90, 180, 270]);
    for (final place in map.toJson()['places'] as List<Map<String, dynamic>>) {
      expect(
        place.containsKey('x') && place.containsKey('y'),
        isTrue,
        reason: '${place['id']} needs optional recorded/corrected coordinates',
      );
    }
  });
}

void walk(recording.MapBuilder b, int steps) {
  for (var i = 0; i < steps; i++) {
    b.onStep(StepEvent(i));
  }
}

Map<String, Object?> allRoutes(MapGraph map) => {
  for (final a in map.places)
    for (final b in map.places)
      '${a.id}->${b.id}': _route(DijkstraRoutePlanner().plan(map, a.id, b.id)),
};
Map<String, Object?> _route(RoutePlan r) => {
  'to': r.toId,
  'steps': r.totalSteps,
  'legs': [
    for (final l in r.legs)
      {
        'id': l.corridorId,
        'reverse': l.reversed,
        'heading': l.heading,
        'steps': l.steps,
        'kind': l.kind.name,
        'floorDelta': l.floorDelta,
      },
  ],
};
