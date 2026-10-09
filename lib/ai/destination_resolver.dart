/// Turns a spoken or typed request into a place on the map (docs/CONTRACTS.md,
/// `DestinationResolver`). PlaceMatcher runs first; Gemma is asked only when it
/// finds nothing, and whatever Gemma says is checked against the map (rule 2:
/// AI perceives, code decides). Pure Dart: the model sits behind [PlaceChooser].
library;

import 'dart:async';

import '../core/contracts.dart';
import '../core/tuning.dart';

/// Name of the one tool Gemma may call.
const String choosePlaceTool = 'choose_place';

/// The places Gemma may choose from: never junctions, never the [hereId] dot.
List<Place> choosablePlaces(MapGraph map) => [
  for (final p in map.places)
    if (p.kind != PlaceKind.junction && p.id != hereId) p,
];

/// The tool description: every choosable place ID with its name and aliases.
String choosePlaceDescription(List<Place> places) {
  final lines = [
    for (final p in places)
      '- ${p.id}: ${p.name}'
          '${p.aliases.isEmpty ? '' : ' (also: ${p.aliases.join(', ')})'}',
  ];
  return 'Choose the place on the indoor map that the person wants to go to. '
      'place_id must be exactly one of these IDs:\n${lines.join('\n')}';
}

/// The language model, seen from the resolver: given the request and the
/// choosable places, it returns the raw `place_id` argument of a
/// [choosePlaceTool] call, or null when it answered in text instead. It may
/// throw; the resolver treats that as "no answer".
abstract interface class PlaceChooser {
  Future<String?> choosePlace(String utterance, List<Place> places);
}

class GemmaDestinationResolver implements DestinationResolver {
  GemmaDestinationResolver({
    required this.matcher,
    required this.chooser,
    this.timeout = const Duration(milliseconds: gemmaTimeoutMs),
  });

  final PlaceMatcher matcher;
  final PlaceChooser chooser;
  final Duration timeout;

  @override
  Future<PlaceMatch?> resolve(String utterance, MapGraph map) async {
    if (utterance.trim().isEmpty) return null;
    final fuzzy = matcher.match(utterance, map);
    if (fuzzy != null) return fuzzy;

    final places = choosablePlaces(map);
    if (places.isEmpty) return null;
    String? raw;
    try {
      raw = await chooser.choosePlace(utterance, places).timeout(timeout);
    } catch (_) {
      return null; // model error or timeout: no destination
    }
    final id = raw?.trim();
    for (final p in places) {
      // Gemma matches carry the lowest accepted score: it picked the place,
      // but nothing in the text spelled it out.
      if (p.id == id) return PlaceMatch(p.id, matchThreshold);
    }
    return null; // unknown ID, junction, "_here" or free text
  }
}
