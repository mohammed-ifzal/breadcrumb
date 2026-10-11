/// D33: the order of the "Where are you?" list. Pure Dart.
library;

import 'contracts.dart';
import 'route_planner.dart';

/// Named places (start and marked places, never junctions), nearest first by
/// route steps from [fromId]; [fromId] itself comes first when it is a named
/// place. Ties keep walk order, newest first (the walker most likely stopped
/// near the end of the walk). Places with no route from [fromId] come last, in
/// the same newest-first order. An unknown [fromId] gives every named place in
/// that order.
List<Place> placesNearestFirst(
  MapGraph map,
  String fromId, {
  RoutePlanner? planner,
}) {
  final routes = planner ?? DijkstraRoutePlanner();
  final named = [
    for (final p in map.places.reversed)
      if (p.kind != PlaceKind.junction) p,
  ];
  final known = map.places.any((p) => p.id == fromId);
  final distance = <String, int?>{};
  for (final p in named) {
    if (!known) {
      distance[p.id] = null;
    } else if (p.id == fromId) {
      distance[p.id] = -1;
    } else {
      try {
        distance[p.id] = routes.plan(map, fromId, p.id).totalSteps;
      } on ArgumentError {
        distance[p.id] = null;
      }
    }
  }
  final order = {for (var i = 0; i < named.length; i++) named[i].id: i};
  return named..sort((a, b) {
    final da = distance[a.id], db = distance[b.id];
    if (da != null && db != null && da != db) return da.compareTo(db);
    if (da == null && db != null) return 1;
    if (da != null && db == null) return -1;
    return order[a.id]!.compareTo(order[b.id]!);
  });
}
