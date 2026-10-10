import 'dart:async';

import 'package:breadcrumb/ai/alias_suggester.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/place_matcher.dart';
import 'package:breadcrumb/core/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/test_maps.dart';

/// Replies with fixed text (or throws, or never answers); records each ask.
class FakeAliasModel implements AliasModel {
  FakeAliasModel(this.reply, {this.error, this.hang = false});

  final String? reply;
  final Object? error;
  final bool hang;
  final asked = <String>[];

  @override
  Future<String?> suggestAliases(String placeName) async {
    asked.add(placeName);
    if (hang) return Completer<String?>().future;
    if (error != null) throw error!;
    return reply;
  }
}

const _stage = Place(id: 'stage_side', name: 'Stage side', kind: PlaceKind.place);
const _food = Place(
  id: 'food_counter',
  name: 'Food counter',
  aliases: ['canteen'],
  kind: PlaceKind.place,
);

void main() {
  group('parseAliasReply', () {
    test('one per line, with bullets, numbering and notes removed', () {
      expect(
        parseAliasReply('Here are some words:\n1. Canteen\n- snacks (English)\n* खाना\n• chai'),
        ['Canteen', 'snacks', 'खाना', 'chai'],
      );
    });

    test('comma and slash separated', () {
      expect(parseAliasReply('canteen, snacks / khana; chai'), [
        'canteen',
        'snacks',
        'khana',
        'chai',
      ]);
    });

    test('a translation note after a dash is its own candidate', () {
      expect(parseAliasReply('khana - food'), ['khana', 'food']);
    });
  });

  group('validateAliases', () {
    List<String> valid(List<String> c, {String name = 'Food counter', List<Place>? others}) =>
        validateAliases(c, placeName: name, otherPlaces: others ?? const [_stage]);

    test('lowercases and strips punctuation', () {
      expect(valid(['Canteen!', '"Snacks"']), ['canteen', 'snacks']);
    });

    test('keeps 1 to 3 words only', () {
      expect(valid(['tea', 'tea stall', 'cup of tea', 'a hot cup of tea']), [
        'tea',
        'tea stall',
        'cup of tea',
      ]);
    });

    test('trims filler words from both ends', () {
      expect(valid(['the canteen', 'tea stall in', 'cup of tea', 'chai kahan hai']), [
        'canteen',
        'tea stall',
        'cup of tea',
        'chai',
      ]);
    });

    test('drops aliases made only of filler words', () {
      expect(valid(['where is it', 'kahan hai', 'room', 'कहाँ है', 'snacks']), ['snacks']);
    });

    test('drops duplicates after normalising', () {
      expect(valid(['Snacks', 'snacks', 'SNACKS.']), ['snacks']);
    });

    test('keeps at most maxAliases', () {
      final many = [for (var i = 0; i < 12; i++) 'word${String.fromCharCode(97 + i)}'];
      expect(valid(many), hasLength(maxAliases));
      expect(valid(many).first, 'worda');
    });

    test('drops the place name itself', () {
      expect(valid(['Food Counter', 'canteen']), ['canteen']);
    });

    test('keeps Devanagari', () {
      expect(valid(['खाना', 'नाश्ता']), ['खाना', 'नाश्ता']);
    });

    test("drops another place's name or alias", () {
      expect(
        valid(['stage side', 'canteen', 'chai'], name: 'Tea stall', others: [_stage, _food]),
        ['chai'],
      );
    });

    test("drops a word inside another place's name", () {
      expect(valid(['stage', 'counter food', 'snacks'], name: 'Snack bar', others: [_stage, _food]), [
        'snacks',
      ]);
    });

    test('drops what PlaceMatcher would resolve to another place', () {
      // "the stage side" scores 1.0 for Stage side by token overlap.
      expect(valid(['the stage side', 'canteen']), ['canteen']);
    });

    test('ignores junctions and the _here dot', () {
      const others = [
        Place(id: 'j1', name: 'Junction 1', kind: PlaceKind.junction),
        Place(id: hereId, name: 'You are here', kind: PlaceKind.junction),
      ];
      expect(valid(['junction', 'you'], others: others), ['junction', 'you']);
    });

    test('drops numbers the name does not have', () {
      expect(valid(['platform 3', 'pf 2', 'platform'], name: 'Platform 2', others: const []), [
        'pf 2',
        'platform',
      ]);
    });

    test('the new place already on the map does not block its own words', () {
      expect(valid(['canteen', 'snacks'], others: [_food, _stage]), ['canteen', 'snacks']);
    });
  });

  group('AliasSuggester', () {
    test('asks once and returns validated aliases', () async {
      final model = FakeAliasModel('1. Canteen\n2. snacks\n3. Stage side\n4. खाना\n5. chai');
      final aliases = await AliasSuggester(model: model).suggest('Food counter', [_stage]);
      expect(model.asked, ['Food counter']);
      expect(aliases, ['canteen', 'snacks', 'खाना', 'chai']);
    });

    test('no model (basic tier) returns none', () async {
      expect(await AliasSuggester(model: null).suggest('Food counter', const []), isEmpty);
    });

    test('a model error returns none', () async {
      final model = FakeAliasModel(null, error: StateError('boom'));
      expect(await AliasSuggester(model: model).suggest('Food counter', const []), isEmpty);
    });

    test('a timeout returns none', () async {
      final model = FakeAliasModel(null, hang: true);
      final s = AliasSuggester(model: model, timeout: const Duration(milliseconds: 10));
      expect(await s.suggest('Food counter', const []), isEmpty);
    });

    test('a null reply returns none', () async {
      expect(await AliasSuggester(model: FakeAliasModel(null)).suggest('X', const []), isEmpty);
    });

    test('an empty name is not asked', () async {
      final model = FakeAliasModel('a');
      expect(await AliasSuggester(model: model).suggest('  ', const []), isEmpty);
      expect(model.asked, isEmpty);
    });
  });

  group('aliasPrompt', () {
    test('names the place and the limits', () {
      final p = aliasPrompt(' Food counter ');
      expect(p, contains('"Food counter"'));
      expect(p, contains('up to $maxAliases'));
      expect(p, contains('1 to $maxAliasWords words'));
    });
  });

  group('applyAliases', () {
    test('adds suggestions to the right places and keeps the rest', () {
      final map = applyAliases(demoMap, {
        'stage_side': ['show', 'मंच'],
        'food_counter': ['snacks'],
      });
      final byId = {for (final p in map.places) p.id: p};
      expect(byId['stage_side']!.aliases, ['show', 'मंच']);
      expect(byId['food_counter']!.aliases, ['canteen', 'खाना काउंटर', 'snacks']);
      expect(byId['start']!.aliases, isEmpty);
      expect(map.corridors, same(demoMap.corridors));
      expect(map.start, demoMap.start);
    });

    test('a word suggested for two places stays with the first', () {
      final map = applyAliases(demoMap, {
        'food_counter': ['hall'],
        'stage_side': ['hall', 'show'],
      });
      final byId = {for (final p in map.places) p.id: p};
      expect(byId['food_counter']!.aliases, contains('hall'));
      expect(byId['stage_side']!.aliases, ['show']);
    });

    test('an existing alias is not added twice', () {
      final map = applyAliases(demoMap, {
        'food_counter': ['Canteen', 'tea'],
      });
      final food = map.places.firstWhere((p) => p.id == 'food_counter');
      expect(food.aliases, ['canteen', 'खाना काउंटर', 'tea']);
    });

    test('PlaceMatcher finds a place by an applied alias', () {
      final map = applyAliases(demoMap, {
        'stage_side': ['show'],
      });
      expect(FuzzyPlaceMatcher().match('where is the show', map)?.placeId, 'stage_side');
    });
  });
}
