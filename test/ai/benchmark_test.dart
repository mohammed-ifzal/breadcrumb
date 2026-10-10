import 'package:breadcrumb/ai/benchmark.dart';
import 'package:breadcrumb/ai/destination_resolver.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/place_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/test_maps.dart';

/// Answers from a fixed table; anything else gets no tool call.
class TableChooser implements PlaceChooser {
  TableChooser(this.answers);

  final Map<String, String> answers;
  var asked = 0;

  @override
  Future<String?> choosePlace(String utterance, List<Place> places) async {
    asked++;
    return answers[utterance];
  }
}

BenchResult result(String? expected, String? actual, {int ms = 100, bool gemma = true}) =>
    BenchResult(
      request: 'r',
      expected: expected,
      group: expected == null ? 'null' : 'en',
      actual: actual,
      viaGemma: gemma,
      ms: ms,
    );

void main() {
  group('benchCases', () {
    test('has 15 English, 10 Hindi or Hinglish and 15 must-be-null requests', () {
      expect(benchCases.where((c) => c.group == 'en'), hasLength(15));
      expect(benchCases.where((c) => c.group == 'hi'), hasLength(10));
      expect(benchCases.where((c) => c.group == 'null'), hasLength(15));
      expect(benchCases.where((c) => c.group == 'null').every((c) => c.expected == null), isTrue);
    });

    test('every expected ID is a choosable place on the demo map', () {
      final ids = choosablePlaces(demoMap).map((p) => p.id).toSet();
      for (final c in benchCases.where((c) => c.expected != null)) {
        expect(ids, contains(c.expected), reason: c.request);
      }
    });

    test('requests are unique', () {
      expect(benchCases.map((c) => c.request).toSet(), hasLength(benchCases.length));
    });
  });

  group('runBench', () {
    test('runs every case each round and records path, answer and time', () async {
      final matcher = FuzzyPlaceMatcher();
      final chooser = TableChooser({"I'm hungry": 'food_counter', 'toilet': 'start'});
      final seen = <BenchResult>[];
      final results = await runBench(
        resolver: GemmaDestinationResolver(matcher: matcher, chooser: chooser),
        map: demoMap,
        isMatcherHit: (r) => matcher.match(r, demoMap) != null,
        cases: const [
          BenchCase("I'm hungry", 'food_counter', 'en'),
          BenchCase('toilet', null, 'null'),
          BenchCase('Stage side', 'stage_side', 'en'),
        ],
        rounds: 2,
        onResult: seen.add,
      );
      expect(results, hasLength(6));
      expect(seen, results);
      expect(results.map((r) => r.correct), [true, false, true, true, false, true]);
      expect(results[1].falsePositive, isTrue);
      expect(results[2].viaGemma, isFalse);
      expect(chooser.asked, 4);
    });
  });

  group('BenchResult', () {
    test('sorts outcomes into correct, false positive, wrong place and missed', () {
      expect(result('food_counter', 'food_counter').correct, isTrue);
      expect(result(null, null).correct, isTrue);
      expect(result(null, 'start').falsePositive, isTrue);
      expect(result('food_counter', 'stage_side').wrongPlace, isTrue);
      expect(result('food_counter', null).missed, isTrue);
      expect(result('food_counter', null).falsePositive, isFalse);
    });

    test('toLine is pipe-separated with - for null', () {
      expect(result(null, null, ms: 42).toLine(), 'null|-|-|gemma|42|r');
    });
  });

  group('percentile', () {
    test('uses the nearest rank', () {
      final values = [for (var i = 10; i >= 1; i--) i * 100];
      expect(percentile(values, 50), 500);
      expect(percentile(values, 90), 900);
      expect(percentile(values, 100), 1000);
      expect(percentile([7], 90), 7);
      expect(percentile([], 50), 0);
    });
  });

  group('BenchSummary', () {
    test('counts outcomes and times only the Gemma answers', () {
      final s = BenchSummary([
        result('food_counter', 'food_counter', ms: 4000),
        result('food_counter', 'food_counter', ms: 5, gemma: false),
        result(null, 'start', ms: 6000),
        result('stage_side', null, ms: 5000),
      ]);
      expect(s.correct, 2);
      expect(s.falsePositives, 1);
      expect(s.missed, 1);
      expect(s.wrongPlaces, 0);
      expect(s.gemmaCount, 3);
      expect(s.gemmaMedianMs, 5000);
      expect(s.gemmaP90Ms, 6000);
      expect(s.describe(), contains('correct 2/4'));
    });
  });
}
