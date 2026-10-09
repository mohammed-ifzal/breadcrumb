/// Matches free text (a sign, a spoken request) to a place on the map, following
/// the four PlaceMatcher rules in docs/CONTRACTS.md. Pure Dart, no packages.
library;

import 'dart:math' as math;

import 'contracts.dart';
import 'tuning.dart';

// CONTRACTS.md gives [^\p{L}\p{N}]; \p{M} is added because Devanagari vowel signs
// and the virama are combining marks, and without it "प्लेटफॉर्म" splits apart.
final _notLetterOrDigit = RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true);
final _digitRun = RegExp(r'\p{Nd}+', unicode: true);

/// Rule 1: lowercase, and anything that isn't a letter, combining mark or digit in
/// any script becomes a single space.
String normalizePlaceText(String text) =>
    text.toLowerCase().replaceAll(_notLetterOrDigit, ' ').trim();

class FuzzyPlaceMatcher implements PlaceMatcher {
  @override
  PlaceMatch? match(String text, MapGraph map) {
    final wanted = normalizePlaceText(text);
    if (wanted.isEmpty) return null;
    final wantedTokens = wanted.split(' ');
    final wantedNumbers = _numbers(wanted);

    PlaceMatch? best;
    for (final place in map.places) {
      if (place.kind == PlaceKind.junction) continue; // rule 2
      for (final candidate in [place.name, ...place.aliases]) {
        final norm = normalizePlaceText(candidate);
        if (norm.isEmpty) continue;
        // Rule 3: every number in the text must be in the candidate.
        if (!_numbers(norm).containsAll(wantedNumbers)) continue;
        final score = _score(wanted, wantedTokens, norm);
        if (best == null || score > best.score) best = PlaceMatch(place.id, score);
      }
    }
    return best != null && best.score >= matchThreshold ? best : null;
  }

  /// Rule 4: the better of token overlap (how well each candidate word is found
  /// in the text, so a name inside a longer request still scores high) and the
  /// normalised Levenshtein similarity of the whole strings.
  double _score(String wanted, List<String> wantedTokens, String candidate) {
    final tokens = candidate.split(' ');
    var overlap = 0.0;
    for (final token in tokens) {
      overlap += wantedTokens.map((w) => _similarity(token, w)).reduce(math.max);
    }
    return math.max(overlap / tokens.length, _similarity(wanted, candidate));
  }
}

/// Digit runs, with any script's digits read as ASCII ("२" is "2").
Set<String> _numbers(String text) => {
  for (final m in _digitRun.allMatches(text))
    String.fromCharCodes(m[0]!.runes.map(_asciiDigit)),
};

int _asciiDigit(int rune) {
  // Devanagari digits are U+0966..U+096F.
  if (rune >= 0x30 && rune <= 0x39) return rune;
  if (rune >= 0x0966 && rune <= 0x096F) return 0x30 + rune - 0x0966;
  return rune;
}

/// 1 minus the Levenshtein distance over the longer length, on code points.
double _similarity(String a, String b) {
  if (a == b) return 1;
  final x = a.runes.toList();
  final y = b.runes.toList();
  final longest = math.max(x.length, y.length);
  if (longest == 0) return 1;
  return 1 - _levenshtein(x, y) / longest;
}

int _levenshtein(List<int> a, List<int> b) {
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final row = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      row[j] = math.min(math.min(row[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
    }
    prev = row;
  }
  return prev[b.length];
}
