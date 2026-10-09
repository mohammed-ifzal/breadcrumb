import 'dart:convert';

import 'package:breadcrumb/core/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

const _exampleJson = '''
{
  "version": 1,
  "name": "Example",
  "start": "entrance",
  "places": [
    {"id": "entrance", "name": "Entrance", "aliases": ["main gate"], "kind": "start"},
    {"id": "j1", "name": "Junction 1", "aliases": [], "kind": "junction"},
    {"id": "lift", "name": "Lift", "aliases": ["elevator"], "kind": "place"}
  ],
  "corridors": [
    {"id": "c1", "from": "entrance", "to": "j1", "steps": 24.0, "heading": 0},
    {"id": "c2", "from": "j1", "to": "lift", "steps": 14, "heading": 90.5}
  ]
}
''';

void main() {
  group('heading conventions', () {
    test('normalizeHeading wraps into [0, 360)', () {
      expect(normalizeHeading(0), 0);
      expect(normalizeHeading(360), 0);
      expect(normalizeHeading(450), 90);
      expect(normalizeHeading(-90), 270);
    });

    test('reversedHeading adds 180', () {
      expect(reversedHeading(0), 180);
      expect(reversedHeading(270), 90);
    });

    test('turnBetween is positive for left, in (-180, 180]', () {
      expect(turnBetween(0, 90), 90);
      expect(turnBetween(90, 0), -90);
      expect(turnBetween(350, 10), 20);
      expect(turnBetween(10, 350), -20);
      expect(turnBetween(0, 180), 180);
      expect(turnBetween(90, 270), 180);
    });
  });

  group('MapGraph JSON', () {
    test('parses numbers with num, whatever their JSON type', () {
      final map = MapGraph.fromJson(jsonDecode(_exampleJson) as Map<String, dynamic>);
      expect(map.version, 1);
      expect(map.start, 'entrance');
      expect(map.places[1].kind, PlaceKind.junction);
      expect(map.places[0].aliases, ['main gate']);
      expect(map.corridors[0].steps, 24);
      expect(map.corridors[0].heading, 0.0);
      expect(map.corridors[1].heading, 90.5);
    });

    test('round-trips through toJson', () {
      final original = jsonDecode(_exampleJson) as Map<String, dynamic>;
      final map = MapGraph.fromJson(original);
      final again = MapGraph.fromJson(
        jsonDecode(jsonEncode(map.toJson())) as Map<String, dynamic>,
      );
      expect(jsonEncode(again.toJson()), jsonEncode(map.toJson()));
      expect(map.toJson()['places'], hasLength(3));
    });

    test('missing aliases read as empty', () {
      final p = Place.fromJson({'id': 'x', 'name': 'X', 'kind': 'place'});
      expect(p.aliases, isEmpty);
    });
  });
}
