/// Everyday words for a newly marked place (D30). After "Mark place" the record
/// screen asks Gemma once for short words people would say for the place, in
/// English, Hindi and Hinglish, and stores the ones that pass [validateAliases]
/// in `Place.aliases`. PlaceMatcher then finds the place by those words with no
/// model at all, which is what the basic tier relies on. Pure Dart: the model
/// sits behind [AliasModel].
library;

import 'dart:async';

import '../core/contracts.dart';
import '../core/place_matcher.dart';
import '../core/tuning.dart';

/// The one prompt for alias suggestions. `{name}` is replaced by the place name.
const String aliasPromptTemplate =
    'Someone marked a place called "{name}" inside a building. Later, other '
    'people will ask for it by voice in their own words, often naming what '
    'they want there instead of the place. List up to $maxAliases such words '
    'or short phrases (1 to $maxAliasWords words each): things people get or '
    'do there, and other names for the place, in English, Hinglish (Hindi in '
    'English letters) and Hindi in Devanagari. Do not repeat the name. One per '
    'line, lowercase, nothing else.\n\n'
    'Example for "Ticket counter":\ntickets\nbooking\nticket window\n'
    'tikat ghar\nटिकट\nटिकट घर\n\nNow for "{name}":';

String aliasPrompt(String placeName) =>
    aliasPromptTemplate.replaceAll('{name}', placeName.trim());

/// The language model, seen from the suggester: one free-text reply to
/// [aliasPrompt]. It may throw; the suggester treats that as no reply.
abstract interface class AliasModel {
  Future<String?> suggestAliases(String placeName);
}

class AliasSuggester {
  /// [model] is null on the basic tier (no Gemma): [suggest] then returns none.
  AliasSuggester({
    required this.model,
    PlaceMatcher? matcher,
    this.timeout = const Duration(milliseconds: aliasSuggestTimeoutMs),
  }) : matcher = matcher ?? FuzzyPlaceMatcher();

  final AliasModel? model;
  final PlaceMatcher matcher;
  final Duration timeout;

  /// Asks the model once and returns at most [maxAliases] validated aliases for
  /// [placeName]; empty on no model, an error, a timeout or nothing valid.
  /// [otherPlaces] are the places already on the map; the new place may or may
  /// not be among them (matched by name).
  Future<List<String>> suggest(String placeName, Iterable<Place> otherPlaces) async {
    final m = model;
    if (m == null || normalizePlaceText(placeName).isEmpty) return const [];
    String? reply;
    try {
      reply = await m.suggestAliases(placeName).timeout(timeout);
    } catch (_) {
      return const [];
    }
    if (reply == null) return const [];
    return validateAliases(
      parseAliasReply(reply),
      placeName: placeName,
      otherPlaces: otherPlaces,
      matcher: matcher,
    );
  }
}

final _splitter = RegExp(r'[\n,;/|]|\s[-–—:]\s');
final _bullet = RegExp(r'^\s*(?:[-*•·]+|\d+[.)])\s*');
final _bracketed = RegExp(r'\([^)]*\)|\[[^\]]*\]');

/// Splits a model reply into candidate aliases: one per line or comma, with
/// bullets, numbering and bracketed notes like "(Hindi)" removed. Lines that end
/// in a colon ("Here are some words:") are preambles and dropped.
List<String> parseAliasReply(String reply) => [
  for (final line in reply.split('\n'))
    if (!line.trimRight().endsWith(':'))
      for (final part in line.split(_splitter))
        part.replaceAll(_bracketed, ' ').replaceFirst(_bullet, '').trim(),
]..removeWhere((s) => s.isEmpty);

/// Keeps the candidates that can safely be aliases of [placeName], in order:
/// normalised like PlaceMatcher text (lowercase, no punctuation), [fillerWords]
/// trimmed from both ends, 1 to
/// [maxAliasWords] words, no number the name doesn't have, not the name itself,
/// no duplicates, at most [maxAliases]. Never a word that already belongs to
/// another place: not another place's name or alias, not a word run inside one,
/// and not something PlaceMatcher would resolve to another place.
List<String> validateAliases(
  Iterable<String> candidates, {
  required String placeName,
  required Iterable<Place> otherPlaces,
  PlaceMatcher? matcher,
}) {
  final name = normalizePlaceText(placeName);
  final others = [
    for (final p in otherPlaces)
      if (p.kind != PlaceKind.junction &&
          p.id != hereId &&
          normalizePlaceText(p.name) != name)
        p,
  ];
  final taken = [
    for (final p in others)
      for (final n in [p.name, ...p.aliases]) normalizePlaceText(n),
  ]..removeWhere((n) => n.isEmpty);
  final othersMap = MapGraph(name: '', start: '', places: others, corridors: const []);
  final m = matcher ?? FuzzyPlaceMatcher();
  final nameNumbers = _digits.allMatches(name).map((d) => d[0]).toSet();

  final kept = <String>[];
  for (final raw in candidates) {
    if (kept.length >= maxAliases) break;
    final alias = _trimFiller(normalizePlaceText(raw));
    if (alias.isEmpty || alias == name || kept.contains(alias)) continue;
    if (alias.split(' ').length > maxAliasWords) continue;
    if (!_digits.allMatches(alias).every((d) => nameNumbers.contains(d[0]))) continue;
    if (taken.any((t) => _containsWords(t, alias))) continue;
    if (m.match(alias, othersMap) != null) continue;
    kept.add(alias);
  }
  return kept;
}

final _digits = RegExp(r'\p{Nd}+', unicode: true);

/// Words that say nothing about a place on their own: question words, filler,
/// and generic place words, in English, Hinglish and Hindi. They are trimmed
/// from both ends of an alias, and an alias made only of them is dropped
/// ("where is it", "kahan hai", "room").
const fillerWords = {
  // English
  'a', 'an', 'the', 'is', 'are', 'it', 'this', 'that', 'here', 'there', 'where',
  'what', 'which', 'how', 'to', 'in', 'at', 'on', 'of', 'for', 'near', 'me', 'my',
  'i', 'want', 'go', 'take', 'find', 'get', 'please', 'place', 'area', 'spot',
  'room', 'side', 'way', 'thing', 'something',
  // Hinglish
  'kahan', 'kahaan', 'kaha', 'kidhar', 'idhar', 'udhar', 'hai', 'hain', 'ho',
  'kya', 'ka', 'ki', 'ke', 'ko', 'se', 'mein', 'par', 'pe', 'yahan',
  'wahan', 'kuch', 'kuchh', 'jagah', 'jaana', 'jana', 'chalo', 'mujhe',
  // Hindi
  'कहाँ', 'कहां', 'किधर', 'है', 'हैं', 'का', 'की', 'के', 'को', 'से', 'में', 'पर',
  'यहाँ', 'यहां', 'वहाँ', 'वहां', 'कुछ', 'जगह', 'मुझे', 'क्या',
};

/// [alias] with filler words trimmed from both ends; empty if nothing is left.
String _trimFiller(String alias) {
  final words = alias.split(' ');
  var start = 0;
  var end = words.length;
  while (start < end && fillerWords.contains(words[start])) {
    start++;
  }
  while (end > start && fillerWords.contains(words[end - 1])) {
    end--;
  }
  return words.sublist(start, end).join(' ');
}

/// Whether [words] appears in [text] as whole words ("stage" in "main stage").
bool _containsWords(String text, String words) =>
    ' $text '.contains(' $words ');

/// [map] with each place's suggestions from [aliasesById] added to its aliases,
/// for the record screen to call on `MapBuilder.finish()`. Places are handled in
/// map order and re-checked with [validateAliases] against the whole map as it
/// grows, so a word suggested for two places stays with the first.
MapGraph applyAliases(MapGraph map, Map<String, List<String>> aliasesById) {
  var places = List.of(map.places);
  for (var i = 0; i < places.length; i++) {
    final p = places[i];
    final suggested = aliasesById[p.id];
    if (suggested == null || suggested.isEmpty) continue;
    final others = [for (final o in places) if (o.id != p.id) o];
    final added = validateAliases(
      suggested,
      placeName: p.name,
      otherPlaces: others,
    ).where((a) => !p.aliases.map(normalizePlaceText).contains(a));
    places[i] = Place(
      id: p.id,
      name: p.name,
      aliases: [...p.aliases, ...added],
      kind: p.kind,
      floor: p.floor,
    );
  }
  places = List.unmodifiable(places);
  return MapGraph(
    version: map.version,
    name: map.name,
    start: map.start,
    places: places,
    corridors: map.corridors,
  );
}
