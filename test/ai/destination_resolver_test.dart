import 'dart:async';

import 'package:breadcrumb/ai/destination_resolver.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/place_matcher.dart';
import 'package:breadcrumb/core/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/test_maps.dart';

/// Answers with a fixed raw `place_id` (or throws), and records each question.
class FakeChooser implements PlaceChooser {
  FakeChooser(this.answer, {this.error, this.hang = false});

  final String? answer;
  final Object? error;
  final bool hang;
  final asked = <String>[];
  List<Place> offered = const [];

  @override
  Future<String?> choosePlace(String utterance, List<Place> places) async {
    asked.add(utterance);
    offered = places;
    if (hang) return Completer<String?>().future;
    if (error != null) throw error!;
    return answer;
  }
}

/// The demo map plus MapBuilder's temporary "_here" junction.
final mapWithHere = MapGraph(
  name: demoMap.name,
  start: demoMap.start,
  places: [
    ...demoMap.places,
    const Place(id: hereId, name: 'Here', kind: PlaceKind.junction),
  ],
  corridors: [
    ...demoMap.corridors,
    const Corridor(id: 'c5', from: 'stage_side', to: hereId, steps: 3, heading: 0),
  ],
);

GemmaDestinationResolver resolver(FakeChooser chooser) =>
    GemmaDestinationResolver(matcher: FuzzyPlaceMatcher(), chooser: chooser);

void main() {
  group('GemmaDestinationResolver', () {
    test('a PlaceMatcher hit skips Gemma', () async {
      final chooser = FakeChooser('stage_side');
      final match = await resolver(chooser).resolve('Food counter', demoMap);
      expect(match?.placeId, 'food_counter');
      expect(match!.score, greaterThanOrEqualTo(matchThreshold));
      expect(chooser.asked, isEmpty);
    });

    test('a valid place ID from Gemma is accepted', () async {
      final chooser = FakeChooser('food_counter');
      final match = await resolver(chooser).resolve('where can I get coffee', demoMap);
      expect(chooser.asked, ['where can I get coffee']);
      expect(match?.placeId, 'food_counter');
      expect(match?.score, matchThreshold);
    });

    test('surrounding whitespace in the ID is ignored', () async {
      final match = await resolver(
        FakeChooser(' stage_side\n'),
      ).resolve('take me back to the show', demoMap);
      expect(match?.placeId, 'stage_side');
    });

    test('Gemma is offered only real places, never junctions or _here', () async {
      final chooser = FakeChooser(null);
      await resolver(chooser).resolve('take me to the moon', mapWithHere);
      expect(chooser.offered.map((p) => p.id), ['start', 'food_counter', 'stage_side']);
    });

    for (final (label, answer) in [
      ('an unknown ID', 'moon'),
      ('a junction ID', 'j1'),
      ('"_here"', hereId),
      ('garbage text', 'Sure! The food counter is to your left.'),
      ('a place name instead of its ID', 'Food counter'),
      ('an empty string', ''),
      ('no tool call', null),
    ]) {
      test('$label becomes null', () async {
        final chooser = FakeChooser(answer);
        expect(await resolver(chooser).resolve('take me to the moon', mapWithHere), isNull);
        expect(chooser.asked, hasLength(1));
      });
    }

    test('a model error becomes null', () async {
      final chooser = FakeChooser('food_counter', error: StateError('GPU lost'));
      expect(await resolver(chooser).resolve('coffee please', demoMap), isNull);
    });

    test('a model that never answers times out to null', () async {
      final r = GemmaDestinationResolver(
        matcher: FuzzyPlaceMatcher(),
        chooser: FakeChooser(null, hang: true),
        timeout: const Duration(milliseconds: 10),
      );
      expect(await r.resolve('coffee please', demoMap), isNull);
    });

    test('an empty request asks nobody', () async {
      final chooser = FakeChooser('food_counter');
      expect(await resolver(chooser).resolve('   ', demoMap), isNull);
      expect(chooser.asked, isEmpty);
    });
  });

  group('choosePlaceDescription', () {
    test('lists every choosable ID with its name and aliases', () {
      final text = choosePlaceDescription(choosablePlaces(mapWithHere));
      expect(text, contains('- food_counter: Food counter (also: canteen, खाना काउंटर)'));
      expect(text, contains('- stage_side: Stage side'));
      expect(text, contains('- start: Start'));
      expect(text, isNot(contains('j1')));
      expect(text, isNot(contains(hereId)));
    });
  });
}
