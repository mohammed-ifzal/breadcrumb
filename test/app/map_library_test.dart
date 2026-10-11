import 'dart:io';

import 'package:breadcrumb/app/map_library.dart';
import 'package:breadcrumb/app/wiring.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/map_json.dart';
import 'package:flutter_test/flutter_test.dart';

MapGraph named(String name, [String place = 'Cafe']) => MapGraph(
  name: name,
  start: 'p0',
  places: [
    Place(id: 'p0', name: name, kind: PlaceKind.start),
    Place(id: 'p1', name: place, kind: PlaceKind.place),
  ],
  corridors: const [
    Corridor(id: 'c1', from: 'p0', to: 'p1', steps: 10, heading: 0),
  ],
);

void main() {
  late Directory docs;
  late MapLibrary library;
  final sep = Platform.pathSeparator;

  File mapsFile(String name) => File('${docs.path}${sep}maps$sep$name');

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('breadcrumb-library-');
    library = MapLibrary(documentsDirectory: () async => docs);
  });
  tearDown(() => docs.delete(recursive: true));

  test('slug makes safe file names', () {
    expect(MapLibrary.slug('Team Groza table!'), 'team-groza-table');
    expect(MapLibrary.slug('  '), 'map');
    expect(MapLibrary.slug('कैफ़े'), 'map');
    expect(MapLibrary.slug('a' * 60).length, 40);
  });

  test('empty library: no maps, no active map', () async {
    expect(await library.list(), isEmpty);
    expect(await library.activeId(), isNull);
    expect(await library.loadActive(), isNull);
  });

  test('saving never overwrites; the newest save is active', () async {
    final a = await library.save(
      named('Demo loop'),
      now: DateTime(2026, 10, 11, 9, 0, 0),
    );
    final b = await library.save(
      named('Test walk'),
      now: DateTime(2026, 10, 11, 9, 5, 0),
    );
    expect(a.id, 'demo-loop-20261011-090000.json');
    final list = await library.list();
    expect(list.map((m) => m.name), ['Test walk', 'Demo loop']);
    expect(await library.activeId(), b.id);
    expect(list.last.placeCount, 2);
    expect(list.last.savedAt, DateTime(2026, 10, 11, 9));
  });

  test('two saves in the same second get distinct files', () async {
    final at = DateTime(2026, 10, 11, 9);
    final a = await library.save(named('Loop'), now: at);
    final b = await library.save(named('Loop'), now: at);
    expect(a.id, isNot(b.id));
    expect(await library.list(), hasLength(2));
  });

  test('setActive switches the active map and mirrors latest.json', () async {
    final a = await library.save(
      named('Demo loop'),
      now: DateTime(2026, 10, 11, 9),
    );
    await library.save(named('Test walk'), now: DateTime(2026, 10, 11, 10));
    await library.setActive(a.id);
    expect((await library.loadActive())!.name, 'Demo loop');
    expect(
      decodeMap(await mapsFile('latest.json').readAsString()).name,
      'Demo loop',
    );
    expect(() => library.setActive('nope.json'), throwsArgumentError);
  });

  test(
    'rename changes the name, keeps the ID and updates latest.json when active',
    () async {
      final a = await library.save(
        named('Demo loop'),
        now: DateTime(2026, 10, 11, 9),
      );
      await library.rename(a.id, '  Stage demo ');
      final list = await library.list();
      expect(list.single.id, a.id);
      expect(list.single.name, 'Stage demo');
      expect(
        decodeMap(await mapsFile('latest.json').readAsString()).name,
        'Stage demo',
      );
      expect(() => library.rename(a.id, '   '), throwsArgumentError);
    },
  );

  test('deleting the active map activates the newest remaining one', () async {
    final a = await library.save(named('Old'), now: DateTime(2026, 10, 11, 8));
    final b = await library.save(named('Mid'), now: DateTime(2026, 10, 11, 9));
    final c = await library.save(named('New'), now: DateTime(2026, 10, 11, 10));
    await library.delete(b.id); // not active: active stays
    expect(await library.activeId(), c.id);
    await library.delete(c.id);
    expect(await library.activeId(), a.id);
    expect(decodeMap(await mapsFile('latest.json').readAsString()).name, 'Old');
    await library.delete(a.id);
    expect(await library.activeId(), isNull);
    expect(await mapsFile('latest.json').exists(), isFalse);
    expect(await library.list(), isEmpty);
  });

  test(
    'a pre-D33 latest.json is migrated once as the first saved map',
    () async {
      await Directory('${docs.path}${sep}maps').create();
      await mapsFile('latest.json').writeAsString(encodeMap(named('Old demo')));
      final list = await library.list();
      expect(list.single.name, 'Old demo');
      expect(await library.activeId(), list.single.id);
      expect(await mapsFile('latest.json').exists(), isTrue);
      // Deleting it must not bring it back on the next read.
      await library.delete(list.single.id);
      expect(await library.list(), isEmpty);
      expect(await library.loadActive(), isNull);
    },
  );

  test(
    'an unreadable latest.json is not migrated and does not break the library',
    () async {
      await Directory('${docs.path}${sep}maps').create();
      await mapsFile('latest.json').writeAsString('{not json');
      expect(await library.list(), isEmpty);
      final saved = await library.save(named('Fresh'));
      expect((await library.loadActive())!.id, saved.id);
    },
  );

  test('a corrupt saved file is skipped, not deleted', () async {
    await library.save(named('Good'), now: DateTime(2026, 10, 11, 9));
    final bad = mapsFile('bad-20261011-100000.json');
    await bad.writeAsString('{');
    expect((await library.list()).map((m) => m.name), ['Good']);
    expect(await bad.exists(), isTrue);
  });

  group('Wiring.reloadActiveMap', () {
    final wiring = Wiring.instance;
    tearDown(() {
      wiring.map = Wiring.defaultDemoMap;
      wiring.currentPlaceId = null;
    });

    test(
      'uses the active map, keeps the start choice while unchanged, '
      'and falls back to the demo map when the last map is deleted',
      () async {
        wiring.map = Wiring.defaultDemoMap;
        expect(await wiring.reloadActiveMap(documentsDir: docs), isFalse);
        expect(wiring.map.name, 'Demo Map');

        final a = await library.save(
          named('Demo loop', 'Food counter'),
          now: DateTime(2026, 10, 11, 9),
        );
        final b = await library.save(
          named('Test walk', 'Washroom'),
          now: DateTime(2026, 10, 11, 10),
        );
        expect(await wiring.reloadActiveMap(documentsDir: docs), isTrue);
        expect(wiring.map.name, 'Test walk');
        wiring.currentPlaceId = 'p0';
        expect(await wiring.reloadActiveMap(documentsDir: docs), isTrue);
        expect(
          wiring.currentPlaceId,
          'p0',
          reason: 'unchanged map keeps the choice',
        );

        await library.setActive(a.id);
        await wiring.reloadActiveMap(documentsDir: docs);
        expect(wiring.map.name, 'Demo loop');
        expect(wiring.currentPlaceId, 'p1');

        await library.delete(a.id);
        await wiring.reloadActiveMap(documentsDir: docs);
        expect(wiring.map.name, 'Test walk');
        await library.delete(b.id);
        expect(await wiring.reloadActiveMap(documentsDir: docs), isFalse);
        expect(wiring.map.name, 'Demo Map');
      },
    );
  });
}
