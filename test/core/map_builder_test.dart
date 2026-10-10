import 'dart:convert';

import 'package:breadcrumb/core/contracts.dart' as contracts;
import 'package:breadcrumb/core/map_builder.dart';
import 'package:breadcrumb/core/map_json.dart';
import 'package:breadcrumb/core/route_planner.dart';
import 'package:breadcrumb/core/tuning.dart' as tuning;
import 'package:flutter_test/flutter_test.dart';

void walk(MapBuilder builder, int count) {
  for (var i = 0; i < count; i++) {
    builder.onStep(contracts.StepEvent(i * 333));
  }
}

void main() {
  test('implements the exact contract and starts at a named start node', () {
    final contracts.MapBuilder builder = MapBuilder();
    builder.start('Entrance');
    final map = builder.snapshot();
    expect(map.name, 'Entrance');
    expect(map.start, 'p0');
    expect(map.places.first.name, 'Entrance');
    expect(map.places.first.kind, contracts.PlaceKind.start);
    expect(map.corridors.single.heading, 0);
  });

  test(
    'snaps individual turn angles before accumulating and wrapping headings',
    () {
      final builder = MapBuilder()..start('Entrance');
      for (final angle in [88.0, 91.0, -88.0, -181.0, 44.0]) {
        walk(builder, 2);
        builder.onTurn(contracts.TurnEvent(100, angle));
      }
      final map = builder.snapshot();
      // D25: 90-degree snapping, so 44 rounds to straight on.
      expect(map.corridors.map((c) => c.heading), [0, 90, 180, 90, 270, 270]);
      expect(
        map.places.where(
          (p) =>
              p.kind == contracts.PlaceKind.junction &&
              p.id != contracts.hereId,
        ),
        hasLength(5),
      );
    },
  );

  test('D25: the turns walked on the iQOO loop snap to right angles', () {
    final builder = MapBuilder()..start('team groza table');
    for (final angle in [-63.0, 108.0, -60.0, -78.0, 75.0, 66.0]) {
      walk(builder, 3);
      builder.onTurn(contracts.TurnEvent(100, angle));
    }
    expect(builder.snapshot().corridors.map((c) => c.heading), [
      0,
      270,
      0,
      270,
      180,
      270,
      0,
    ]);
  });

  for (final sign in [1, -1]) {
    test('half-way snapping rounds away from zero for sign $sign', () {
      final builder = MapBuilder()..start('Entrance');
      builder.onTurn(contracts.TurnEvent(0, sign * tuning.turnSnapDegrees / 2));
      expect(
        builder.snapshot().corridors.last.heading,
        contracts.normalizeHeading(sign * tuning.turnSnapDegrees),
      );
    });
  }

  test(
    'every turn creates a distinct junction including a turn snapped to zero',
    () {
      final builder = MapBuilder()..start('Entrance');
      builder.onTurn(const contracts.TurnEvent(0, 90));
      builder.onTurn(const contracts.TurnEvent(20, 10));
      final map = builder.finish();
      expect(map.places.map((p) => p.id), ['p0', 'j1', 'j2']);
      expect(map.corridors.map((c) => c.steps), [0, 0]);
      expect(map.corridors.map((c) => c.heading), [0, 90]);
    },
  );

  test('addPlace splits step counts without changing the heading', () {
    final builder = MapBuilder()..start('Entrance');
    walk(builder, 5);
    builder.onTurn(const contracts.TurnEvent(0, 89));
    walk(builder, 3);
    builder.addPlace('Coffee', ['Cafe']);
    walk(builder, 4);
    builder.addPlace('Stage', []);
    final map = builder.finish();
    expect(map.corridors.map((c) => c.steps), [5, 3, 4]);
    expect(map.corridors.map((c) => c.heading), [0, 90, 90]);
    expect(map.places.where((p) => p.name == 'Coffee').single.aliases, [
      'Cafe',
    ]);
    expect(map.places.last.kind, contracts.PlaceKind.place);
  });

  test(
    'snapshot includes a temporary junction and the complete open corridor',
    () {
      final builder = MapBuilder()..start('Entrance');
      walk(builder, 5);
      builder.onTurn(const contracts.TurnEvent(0, 90));
      walk(builder, 3);
      final map = builder.snapshot();
      expect(map.places.last.id, contracts.hereId);
      expect(map.places.last.kind, contracts.PlaceKind.junction);
      expect(map.corridors.last.from, 'j1');
      expect(map.corridors.last.to, contracts.hereId);
      expect(map.corridors.last.steps, 3);
      expect(map.corridors.last.heading, 90);
      expect(decodeMap(encodeMap(map)).toJson(), map.toJson());
    },
  );

  test(
    'repeated snapshots do not consume steps, IDs or change later recording',
    () {
      final builder = MapBuilder()..start('Entrance');
      final control = MapBuilder()..start('Entrance');
      for (final b in [builder, control]) {
        walk(b, 3);
      }
      final first = builder.snapshot();
      expect(builder.snapshot().toJson(), first.toJson());
      for (final b in [builder, control]) {
        walk(b, 2);
        b.onTurn(const contracts.TurnEvent(0, -90));
        walk(b, 4);
        b.addPlace('Exit', ['Door']);
        walk(b, 1);
      }
      expect(builder.finish().toJson(), control.finish().toJson());
      expect(first.corridors.last.steps, 3);
      expect(first.places, hasLength(2));
    },
  );

  test('snapshot collections and aliases cannot mutate builder state', () {
    final builder = MapBuilder()..start('Entrance');
    final aliases = ['Cafe'];
    builder.addPlace('Coffee', aliases);
    aliases.add('Injected');
    final map = builder.snapshot();
    expect(map.places[1].aliases, ['Cafe']);
    expect(() => map.places.clear(), throwsUnsupportedError);
    expect(() => map.corridors.clear(), throwsUnsupportedError);
    expect(() => map.places[1].aliases.add('Injected'), throwsUnsupportedError);
    expect(builder.snapshot().toJson(), map.toJson());
  });

  test(
    'finish preserves trailing steps at a permanent endpoint and round-trips',
    () {
      final builder = MapBuilder()..start('Entrance');
      walk(builder, 4);
      builder.onTurn(const contracts.TurnEvent(0, 90));
      walk(builder, 6);
      builder.snapshot();
      final map = builder.finish();
      expect(map.places.any((p) => p.id == contracts.hereId), isFalse);
      expect(map.places.last.kind, contracts.PlaceKind.junction);
      expect(map.corridors.map((c) => c.steps), [4, 6]);
      expect(map.corridors.last.to, map.places.last.id);
      final decoded = contracts.MapGraph.fromJson(
        jsonDecode(jsonEncode(map.toJson())) as Map<String, dynamic>,
      );
      expect(decoded.toJson(), map.toJson());
      expect(decodeMap(encodeMap(map)).toJson(), map.toJson());
    },
  );

  test('events before start are safely ignored', () {
    final builder = MapBuilder();
    builder.onStep(const contracts.StepEvent(0));
    builder.onTurn(const contracts.TurnEvent(20, 90));
    builder.addPlace('Unstarted', []);
    builder.start('Entrance');
    final map = builder.snapshot();
    expect(map.places, hasLength(2));
    expect(map.corridors.single.steps, 0);
    expect(map.corridors.single.heading, 0);
  });

  test('snapshot and finish before start report a clear lifecycle error', () {
    final builder = MapBuilder();
    expect(builder.snapshot, throwsStateError);
    expect(builder.finish, throwsStateError);
  });

  test('zero steps between turns keep distinct connected junctions', () {
    final builder = MapBuilder()..start('Entrance');
    walk(builder, 2);
    builder.onTurn(const contracts.TurnEvent(0, 90));
    builder.onTurn(const contracts.TurnEvent(20, -90));
    walk(builder, 3);
    builder.addPlace('Exit', []);
    final map = builder.finish();
    expect(map.corridors.map((c) => c.steps), [2, 0, 3]);
    expect(
      DijkstraRoutePlanner()
          .plan(map, map.start, map.places.last.id)
          .totalSteps,
      5,
    );
  });

  test(
    'addPlace at step zero and twice at the same step retains both labels',
    () {
      final builder = MapBuilder()..start('Entrance');
      builder.addPlace('Desk', ['Reception']);
      builder.addPlace('Lift', []);
      final map = builder.finish();
      expect(map.places.map((p) => p.name), ['Entrance', 'Desk', 'Lift']);
      expect(map.places.map((p) => p.id).toSet(), hasLength(3));
      expect(map.corridors.map((c) => c.steps), [0, 0]);
      final route = DijkstraRoutePlanner().plan(
        map,
        map.start,
        map.places.last.id,
      );
      expect(route.totalSteps, 0);
      expect(route.legs, hasLength(2));
    },
  );

  test('finish without steps gives a valid start-only map', () {
    final builder = MapBuilder()..start('Entrance');
    final snapshot = builder.snapshot();
    expect(snapshot.corridors.single.steps, 0);
    expect(snapshot.places.last.id, contracts.hereId);
    final map = builder.finish();
    expect(map.places, hasLength(1));
    expect(map.corridors, isEmpty);
    expect(decodeMap(encodeMap(map)).toJson(), map.toJson());
    expect(
      DijkstraRoutePlanner().plan(map, map.start, map.start).legs,
      isEmpty,
    );
  });

  test('finish is idempotent and events after finish cannot alter the map', () {
    final builder = MapBuilder()..start('Entrance');
    walk(builder, 3);
    final map = builder.finish();
    builder.onStep(const contracts.StepEvent(20));
    builder.onTurn(const contracts.TurnEvent(40, 90));
    builder.addPlace('Late', []);
    expect(builder.finish().toJson(), map.toJson());
    expect(builder.snapshot().toJson(), map.toJson());
  });

  test('start resets a finished walk without changing old returned maps', () {
    final builder = MapBuilder()..start('Old');
    walk(builder, 3);
    final old = builder.finish();
    builder.start('New');
    final fresh = builder.snapshot();
    expect(fresh.name, 'New');
    expect(fresh.corridors.single.steps, 0);
    expect(fresh.corridors.single.heading, 0);
    expect(old.name, 'Old');
    expect(old.corridors.single.steps, 3);
  });

  test('non-finite turn angles do not corrupt an active map', () {
    final builder = MapBuilder()..start('Entrance');
    walk(builder, 3);
    builder.onTurn(const contracts.TurnEvent(0, double.nan));
    builder.onTurn(const contracts.TurnEvent(20, double.infinity));
    expect(builder.snapshot().corridors.single.steps, 3);
    expect(builder.snapshot().corridors.single.heading, 0);
  });

  test(
    'recorded map supports forward and reverse routes between named places',
    () {
      final builder = MapBuilder()..start('Entrance');
      walk(builder, 5);
      builder.onTurn(const contracts.TurnEvent(0, 89));
      walk(builder, 3);
      builder.addPlace('Coffee', ['Cafe']);
      walk(builder, 4);
      builder.addPlace('Stage', []);
      final map = builder.finish();
      final stage = map.places.singleWhere((p) => p.name == 'Stage').id;
      final planner = DijkstraRoutePlanner();
      final forward = planner.plan(map, map.start, stage);
      final reverse = planner.plan(map, stage, map.start);
      expect(forward.totalSteps, 12);
      expect(forward.legs.map((leg) => leg.heading), [0, 90, 90]);
      expect(reverse.totalSteps, 12);
      expect(reverse.legs.map((leg) => leg.heading), [270, 270, 180]);
      expect(reverse.legs.every((leg) => leg.reversed), isTrue);
    },
  );
  group('D24 recorded floors', () {
    for (final kind in [
      contracts.CorridorKind.stairs,
      contracts.CorridorKind.escalator,
      contracts.CorridorKind.lift,
    ]) {
      test('$kind separates prior walking from a completed transition', () {
        final builder = MapBuilder()..start('Entrance');
        walk(builder, 5);
        builder.changeFloor(1, kind);
        final snapshot = builder.snapshot();
        expect(snapshot.corridors.map((c) => c.steps), [5, 0, 0]);
        expect(snapshot.corridors.map((c) => c.kind), [
          contracts.CorridorKind.walk,
          kind,
          contracts.CorridorKind.walk,
        ]);
        expect(snapshot.corridors.map((c) => c.floorDelta), [0, 1, 0]);
        expect(snapshot.places.last.floor, 1);
        expect(builder.snapshot().toJson(), snapshot.toJson());
        walk(builder, 2);
        builder.addPlace('Upper desk', []);
        final finished = builder.finish();
        expect(finished.places.last.floor, 1);
        expect(finished.corridors.last.steps, 2);
        expect(decodeMap(encodeMap(finished)).toJson(), finished.toJson());
        expect(
          DijkstraRoutePlanner()
              .plan(finished, finished.start, finished.places.last.id)
              .legs
              .map((l) => l.floorDelta),
          [0, 1, 0],
        );
      });
    }
    test('no-step consecutive changes and finish retain all transitions', () {
      final builder = MapBuilder()..start('Entrance');
      builder.changeFloor(1, contracts.CorridorKind.stairs);
      builder.changeFloor(1, contracts.CorridorKind.escalator);
      builder.changeFloor(-1, contracts.CorridorKind.lift);
      builder.addPlace('End of walk', []);
      final map = builder.finish();
      expect(map.corridors.map((c) => c.floorDelta), [1, 1, -1, 0]);
      expect(map.corridors.map((c) => c.steps), everyElement(0));
      expect(map.places.map((p) => p.floor), [0, 1, 2, 1, 1]);
      expect(decodeMap(encodeMap(map)).toJson(), map.toJson());
      final reverse = DijkstraRoutePlanner().plan(
        map,
        map.places.last.id,
        map.start,
      );
      expect(reverse.legs.map((l) => l.floorDelta), [0, 1, -1, -1]);
    });
    test('a change immediately after a turn preserves its heading', () {
      final builder = MapBuilder()..start('Entrance');
      walk(builder, 3);
      builder.onTurn(const contracts.TurnEvent(100, 90));
      builder.changeFloor(-1, contracts.CorridorKind.lift);
      final map = builder.snapshot();
      expect(map.corridors.map((c) => c.steps), [3, 0, 0]);
      expect(map.corridors.map((c) => c.heading), [0, 90, 90]);
      expect(map.places.last.floor, -1);
      expect(decodeMap(encodeMap(map)).toJson(), map.toJson());
    });
    test('invalid transitions do not mutate an active walk', () {
      final builder = MapBuilder()..start('Entrance');
      final before = builder.snapshot().toJson();
      expect(
        () => builder.changeFloor(0, contracts.CorridorKind.stairs),
        throwsArgumentError,
      );
      expect(
        () => builder.changeFloor(1, contracts.CorridorKind.walk),
        throwsArgumentError,
      );
      expect(builder.snapshot().toJson(), before);
    });
    test(
      'floor changes outside recording are ignored and start resets the floor',
      () {
        final builder = MapBuilder();
        builder.changeFloor(1, contracts.CorridorKind.lift);
        builder.start('Entrance');
        expect(builder.snapshot().places.last.floor, 0);
        builder.changeFloor(-1, contracts.CorridorKind.stairs);
        final map = builder.finish();
        builder.changeFloor(1, contracts.CorridorKind.lift);
        expect(builder.finish().toJson(), map.toJson());
        builder.start('Fresh');
        expect(builder.snapshot().places.last.floor, 0);
        expect(
          builder.snapshot().corridors.single.kind,
          contracts.CorridorKind.walk,
        );
      },
    );
  });
}
