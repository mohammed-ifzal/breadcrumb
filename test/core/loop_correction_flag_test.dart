import 'dart:convert';
import 'dart:io';

import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/map_builder.dart' as recording;
import 'package:breadcrumb/core/map_json.dart';
import 'package:breadcrumb/core/trail_geometry.dart';
import 'package:breadcrumb/core/tuning.dart' as tuning;
import 'package:flutter_test/flutter_test.dart';

import 'loop_correction_test.dart' show allRoutes;

void main() {
  test(
    'D33 defaults on; flag off keeps legacy recording and saved bytes',
    () async {
      expect(tuning.useLoopCorrection, isTrue);
      final builder = recording.MapBuilder(useLoopCorrection: false)
        ..start('Start');
      for (var leg = 0; leg < 4; leg++) {
        for (var i = 0; i < (leg == 3 ? 7 : 10); i++) {
          builder.onStep(StepEvent(i));
        }
        if (leg < 3) builder.onTurn(const TurnEvent(0, 90));
      }
      const places = [
        Place(id: 'p0', name: 'Start', kind: PlaceKind.start),
        Place(id: 'j1', name: 'Junction 1', kind: PlaceKind.junction),
        Place(id: 'j2', name: 'Junction 2', kind: PlaceKind.junction),
        Place(id: 'j3', name: 'Junction 3', kind: PlaceKind.junction),
      ];
      const corridors = [
        Corridor(id: 'c1', from: 'p0', to: 'j1', steps: 10, heading: 0),
        Corridor(id: 'c2', from: 'j1', to: 'j2', steps: 10, heading: 90),
        Corridor(id: 'c3', from: 'j2', to: 'j3', steps: 10, heading: 180),
      ];
      final legacySnapshot = MapGraph(
        name: 'Start',
        start: 'p0',
        places: [
          ...places,
          const Place(
            id: hereId,
            name: 'You are here',
            kind: PlaceKind.junction,
          ),
        ],
        corridors: [
          ...corridors,
          const Corridor(
            id: 'c4',
            from: 'j3',
            to: hereId,
            steps: 7,
            heading: 270,
          ),
        ],
      );
      expect(encodeMap(builder.snapshot()), encodeMap(legacySnapshot));
      expect(encodeMap(builder.snapshot()), encodeMap(legacySnapshot));
      expect(builder.previewLoopClosure('Start'), isNull);
      builder.addPlace(' START ', []);
      final legacyClosed = MapGraph(
        name: 'Start',
        start: 'p0',
        places: places,
        corridors: [
          ...corridors,
          const Corridor(
            id: 'c4',
            from: 'j3',
            to: 'p0',
            steps: 7,
            heading: 270,
          ),
        ],
      );
      final closed = builder.finish();
      expect(encodeMap(closed), encodeMap(legacyClosed));
      expect(jsonEncode(closed.toJson()), jsonEncode(legacyClosed.toJson()));
      expect(encodeMap(decodeMap(encodeMap(closed))), encodeMap(legacyClosed));
      final baseline = jsonDecode(
        await File('test/core/fixtures/loop_correction_baseline.json')
            .readAsString(),
      ) as Map;
      expect(
        closed.corridors.map((c) => c.toJson()).toList(),
        baseline['drifted_loop']['corridors'],
      );
      expect(allRoutes(closed), baseline['drifted_loop']['routes']);
      List<Object> positions(MapGraph map) => [
        for (final p in layoutMap(map)) [p.placeId, p.x, p.y],
      ];
      expect(positions(closed), positions(legacyClosed));
      expect(positions(builder.snapshot()), positions(legacyClosed));
    },
  );

  test(
    'flag off omits coordinates from marks, floors, zero steps and finish',
    () {
      final builder = recording.MapBuilder(useLoopCorrection: false)
        ..start('Start');
      builder.addPlace('Desk', ['work']);
      builder.addPlace(' desk ', []);
      builder.changeFloor(1, CorridorKind.stairs);
      builder.onTurn(const TurnEvent(0, -90));
      builder.onStep(const StepEvent(1));
      for (final map in [builder.snapshot(), builder.finish()]) {
        for (final p in map.places) {
          expect(p.toJson().containsKey('x'), isFalse);
          expect(p.toJson().containsKey('y'), isFalse);
        }
        expect(encodeMap(decodeMap(encodeMap(map))), encodeMap(map));
      }
      final empty = recording.MapBuilder(useLoopCorrection: false)
        ..start('Empty');
      expect(empty.finish().places.single.x, isNull);
      expect(empty.finish().corridors, isEmpty);
    },
  );
}
