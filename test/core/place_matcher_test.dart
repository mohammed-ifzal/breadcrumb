import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/place_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_maps.dart';

void main() {
  final matcher = FuzzyPlaceMatcher();

  const station = MapGraph(
    name: 'Station',
    start: 'entrance',
    places: [
      Place(id: 'entrance', name: 'Entrance', aliases: ['main gate'], kind: PlaceKind.start),
      Place(id: 'j1', name: 'Junction 1', kind: PlaceKind.junction),
      Place(
        id: 'platform_2',
        name: 'Platform 2',
        aliases: ['platform two', 'pf 2', 'प्लेटफॉर्म 2'],
        kind: PlaceKind.place,
      ),
      Place(id: 'lift', name: 'Lift', aliases: ['elevator'], kind: PlaceKind.place),
    ],
    corridors: [],
  );

  test('normalize keeps Devanagari and splits on punctuation', () {
    expect(normalizePlaceText('  PLATFORM-2 / प्लेटफॉर्म 2!! '), 'platform 2 प्लेटफॉर्म 2');
  });

  test('exact name, any case, scores 1', () {
    final m = matcher.match('FOOD COUNTER', demoMap)!;
    expect(m.placeId, 'food_counter');
    expect(m.score, 1);
  });

  test('a name inside a longer request matches', () {
    expect(matcher.match('take me to the food counter please', demoMap)?.placeId, 'food_counter');
    expect(matcher.match('Stage side', demoMap)?.placeId, 'stage_side');
  });

  test('small typos still match', () {
    expect(matcher.match('food countr', demoMap)?.placeId, 'food_counter');
    expect(matcher.match('elevater', station)?.placeId, 'lift');
  });

  test('"platform 3" does NOT match "Platform 2"', () {
    expect(matcher.match('platform 3', station), isNull);
    expect(matcher.match('PLATFORM 3 / प्लेटफॉर्म 3', station), isNull);
  });

  test('"platform 2" matches, including a sign with both scripts', () {
    expect(matcher.match('platform 2', station)?.placeId, 'platform_2');
    expect(matcher.match('PLATFORM 2 / प्लेटफॉर्म 2', station)?.placeId, 'platform_2');
  });

  test('with two numbered platforms, the number picks the right one', () {
    final both = MapGraph(
      name: 'Both',
      start: 'entrance',
      places: [
        ...station.places,
        const Place(id: 'platform_3', name: 'Platform 3', kind: PlaceKind.place),
      ],
      corridors: const [],
    );
    expect(matcher.match('platform 3', both)?.placeId, 'platform_3');
    expect(matcher.match('platform 2', both)?.placeId, 'platform_2');
  });

  test('Devanagari text matches an alias', () {
    expect(matcher.match('खाना काउंटर', demoMap)?.placeId, 'food_counter');
    expect(matcher.match('प्लेटफॉर्म 2', station)?.placeId, 'platform_2');
  });

  test('Devanagari digits count as the same number', () {
    expect(matcher.match('प्लेटफॉर्म २', station)?.placeId, 'platform_2');
    expect(matcher.match('प्लेटफॉर्म ३', station), isNull);
  });

  test('never matches a junction', () {
    expect(matcher.match('Junction 1', station), isNull);
  });

  test('unrelated text and empty text give null', () {
    expect(matcher.match('take me to the moon', demoMap), isNull);
    expect(matcher.match('', demoMap), isNull);
    expect(matcher.match('?!', demoMap), isNull);
  });
}
