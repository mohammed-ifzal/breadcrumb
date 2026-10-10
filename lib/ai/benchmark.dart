/// The on-device destination benchmark (docs/BENCHMARKS.md): 40 requests for
/// the demo map, each with the place it must resolve to, or null. Pure Dart:
/// the debug screen runs it on the phone with the real resolver.
library;

import '../core/contracts.dart';

class BenchCase {
  const BenchCase(this.request, this.expected, this.group);

  final String request;

  /// The place ID it must resolve to; null when it must resolve to nothing.
  final String? expected;

  /// `en`, `hi` (Hindi or Hinglish) or `null` (must return null).
  final String group;
}

const _food = 'food_counter';
const _stage = 'stage_side';

/// For the demo map (`debugDemoMap`): Start, Food counter, Stage side.
const benchCases = [
  // 15 English variants for the two places.
  BenchCase("I'm hungry", _food, 'en'),
  BenchCase('snacks', _food, 'en'),
  BenchCase('where can I get coffee', _food, 'en'),
  BenchCase('I want something to eat', _food, 'en'),
  BenchCase('grab a sandwich', _food, 'en'),
  BenchCase('I need a cup of tea', _food, 'en'),
  BenchCase('lunch', _food, 'en'),
  BenchCase('where is the canteen', _food, 'en'),
  BenchCase("where's the stage", _stage, 'en'),
  BenchCase('take me to the stage', _stage, 'en'),
  BenchCase('where is the show', _stage, 'en'),
  BenchCase('I want to watch the performance', _stage, 'en'),
  BenchCase('where are the speeches happening', _stage, 'en'),
  BenchCase('take me back to the stage area', _stage, 'en'),
  BenchCase("where's the main event", _stage, 'en'),
  // 10 Hindi and Hinglish.
  BenchCase('मुझे भूख लगी है', _food, 'hi'),
  BenchCase('खाना कहाँ मिलेगा', _food, 'hi'),
  BenchCase('chai kahan milegi', _food, 'hi'),
  BenchCase('mujhe kuch khana hai', _food, 'hi'),
  BenchCase('nashta kahan hai', _food, 'hi'),
  BenchCase('स्टेज कहाँ है', _stage, 'hi'),
  BenchCase('मंच पर ले चलो', _stage, 'hi'),
  BenchCase('stage kidhar hai', _stage, 'hi'),
  BenchCase('show kahan ho raha hai', _stage, 'hi'),
  BenchCase('mujhe stage pe jaana hai', _stage, 'hi'),
  // 15 that must return null: places the map doesn't have, and nonsense.
  BenchCase('toilet', null, 'null'),
  BenchCase('parking', null, 'null'),
  BenchCase('take me to the moon', null, 'null'),
  BenchCase('asdf qwerty zxcv', null, 'null'),
  BenchCase('where is the washroom', null, 'null'),
  BenchCase('exit', null, 'null'),
  BenchCase('lift', null, 'null'),
  BenchCase('pharmacy', null, 'null'),
  BenchCase('ATM', null, 'null'),
  BenchCase('car park level 2', null, 'null'),
  BenchCase('bathroom kahan hai', null, 'null'),
  BenchCase('दवाई की दुकान', null, 'null'),
  BenchCase('platform 3', null, 'null'),
  BenchCase("what's the weather", null, 'null'),
  BenchCase('hjkl mnbv', null, 'null'),
];

class BenchResult {
  const BenchResult({
    required this.request,
    required this.expected,
    required this.group,
    required this.actual,
    required this.viaGemma,
    required this.ms,
    this.us = 0,
  });

  final String request;
  final String? expected;
  final String group;
  final String? actual;

  /// False when PlaceMatcher answered and Gemma was never asked.
  final bool viaGemma;
  final int ms;

  /// The same time in microseconds, for PlaceMatcher answers well under 1 ms.
  final int us;

  bool get correct => actual == expected;

  /// A must-be-null request that resolved to a place.
  bool get falsePositive => expected == null && actual != null;

  /// A place request that resolved to a different place.
  bool get wrongPlace => expected != null && actual != null && actual != expected;

  /// A place request that resolved to nothing.
  bool get missed => expected != null && actual == null;

  /// One log line, `|`-separated, for pulling results off the phone.
  String toLine() => [
    group,
    expected ?? '-',
    actual ?? '-',
    viaGemma ? 'gemma' : 'matcher',
    ms,
    request,
  ].join('|');
}

/// Runs every case [rounds] times, in order, one round after another.
/// [isMatcherHit] says whether PlaceMatcher alone would answer the request.
/// [gap] is the pause before each request, standing in for the seconds
/// between two spoken requests; it is not part of the measured time.
Future<List<BenchResult>> runBench({
  required DestinationResolver resolver,
  required MapGraph map,
  required bool Function(String request) isMatcherHit,
  List<BenchCase> cases = benchCases,
  int rounds = 3,
  Duration gap = Duration.zero,
  void Function(BenchResult result)? onResult,
}) async {
  final results = <BenchResult>[];
  for (var round = 0; round < rounds; round++) {
    for (final c in cases) {
      if (gap > Duration.zero) await Future<void>.delayed(gap);
      final watch = Stopwatch()..start();
      final match = await resolver.resolve(c.request, map);
      final result = BenchResult(
        request: c.request,
        expected: c.expected,
        group: c.group,
        actual: match?.placeId,
        viaGemma: !isMatcherHit(c.request),
        ms: watch.elapsedMilliseconds,
        us: watch.elapsedMicroseconds,
      );
      results.add(result);
      onResult?.call(result);
    }
  }
  return results;
}

/// The [p]th percentile (0–100) by nearest rank; 0 for an empty list.
int percentile(Iterable<int> values, double p) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) return 0;
  final rank = (p / 100 * sorted.length).ceil();
  return sorted[(rank - 1).clamp(0, sorted.length - 1)];
}

class BenchSummary {
  BenchSummary(this.results);

  final List<BenchResult> results;

  int get total => results.length;
  int get correct => results.where((r) => r.correct).length;
  int get falsePositives => results.where((r) => r.falsePositive).length;
  int get wrongPlaces => results.where((r) => r.wrongPlace).length;
  int get missed => results.where((r) => r.missed).length;
  int correctIn(String group) =>
      results.where((r) => r.group == group && r.correct).length;
  int totalIn(String group) => results.where((r) => r.group == group).length;

  Iterable<int> get _gemmaMs => results.where((r) => r.viaGemma).map((r) => r.ms);
  int get gemmaCount => _gemmaMs.length;
  int get gemmaMedianMs => percentile(_gemmaMs, 50);
  int get gemmaP90Ms => percentile(_gemmaMs, 90);
  int get allMedianMs => percentile(results.map((r) => r.ms), 50);
  int get allP90Ms => percentile(results.map((r) => r.ms), 90);
  int get allMedianUs => percentile(results.map((r) => r.us), 50);

  String describe() =>
      'correct $correct/$total (en ${correctIn('en')}/${totalIn('en')}, '
      'hi ${correctIn('hi')}/${totalIn('hi')}, '
      'null ${correctIn('null')}/${totalIn('null')}); '
      'false positives $falsePositives, wrong place $wrongPlaces, missed $missed; '
      'Gemma answers $gemmaCount: median $gemmaMedianMs ms, p90 $gemmaP90Ms ms; '
      'all: median $allMedianMs ms ($allMedianUs us), p90 $allP90Ms ms';
}
