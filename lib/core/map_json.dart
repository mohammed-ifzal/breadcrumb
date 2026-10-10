/// Loading and saving a [MapGraph] as JSON text, plus lookups by ID. Pure Dart: the
/// caller reads and writes the file.
library;

import 'dart:convert';

import 'contracts.dart';

/// Parses map JSON text and checks that it hangs together. Throws
/// [FormatException] on a bad version, an unknown start, a corridor that points
/// at an unknown place, or a `floorDelta` that doesn't fit its places' floors.
MapGraph decodeMap(String source) {
  final MapGraph map;
  try {
    map = MapGraph.fromJson(jsonDecode(source) as Map<String, dynamic>);
  } on FormatException {
    rethrow;
  } catch (e) {
    throw FormatException('Not a map file: $e');
  }

  if (map.version != 1) {
    throw FormatException('Unsupported map version ${map.version}');
  }
  final floors = {for (final p in map.places) p.id: p.floor};
  if (!floors.containsKey(map.start)) {
    throw FormatException('Start "${map.start}" is not a place');
  }
  for (final c in map.corridors) {
    final from = floors[c.from];
    final to = floors[c.to];
    if (from == null || to == null) {
      throw FormatException('Corridor ${c.id} joins an unknown place');
    }
    // D24: floorDelta matches the floors it joins, and only stairs, escalators
    // and lifts change floor.
    if (c.floorDelta != to - from || (c.floorDelta != 0 && !c.isTransition)) {
      throw FormatException('Corridor ${c.id} floorDelta does not fit its places');
    }
  }
  return map;
}

/// Map JSON text, indented so it reads well on the laptop.
String encodeMap(MapGraph map) =>
    const JsonEncoder.withIndent('  ').convert(map.toJson());

extension MapGraphLookup on MapGraph {
  Place? placeById(String id) {
    for (final p in places) {
      if (p.id == id) return p;
    }
    return null;
  }

  Corridor? corridorById(String id) {
    for (final c in corridors) {
      if (c.id == id) return c;
    }
    return null;
  }
}
