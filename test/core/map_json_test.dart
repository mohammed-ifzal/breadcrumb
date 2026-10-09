import 'package:breadcrumb/core/map_json.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_maps.dart';

void main() {
  test('encodeMap then decodeMap round-trips every field', () {
    final back = decodeMap(encodeMap(demoMap));

    expect(back.toJson(), demoMap.toJson());
    expect(back.placeById('food_counter')!.aliases, ['canteen', 'खाना काउंटर']);
    expect(back.corridorById('c2')!.heading, 90.0);
  });

  test('decodeMap reads integer headings and double steps', () {
    final map = decodeMap('''
{"version": 1, "name": "M", "start": "a",
 "places": [{"id": "a", "name": "A", "aliases": [], "kind": "start"},
            {"id": "b", "name": "B", "aliases": [], "kind": "place"}],
 "corridors": [{"id": "c1", "from": "a", "to": "b", "steps": 7.0, "heading": 90}]}
''');

    expect(map.corridors.single.steps, 7);
    expect(map.corridors.single.heading, 90.0);
  });

  test('decodeMap rejects a corridor to an unknown place', () {
    expect(
      () => decodeMap('''
{"version": 1, "name": "M", "start": "a",
 "places": [{"id": "a", "name": "A", "aliases": [], "kind": "start"}],
 "corridors": [{"id": "c1", "from": "a", "to": "zz", "steps": 3, "heading": 0}]}
'''),
      throwsFormatException,
    );
  });

  test('decodeMap rejects an unknown start and an unsupported version', () {
    const places = '[{"id": "a", "name": "A", "aliases": [], "kind": "start"}]';
    expect(
      () => decodeMap(
        '{"version": 1, "name": "M", "start": "x", "places": $places, "corridors": []}',
      ),
      throwsFormatException,
    );
    expect(
      () => decodeMap(
        '{"version": 2, "name": "M", "start": "a", "places": $places, "corridors": []}',
      ),
      throwsFormatException,
    );
  });

  test('lookups return null for unknown IDs', () {
    expect(demoMap.placeById('nope'), isNull);
    expect(demoMap.corridorById('nope'), isNull);
  });
}
