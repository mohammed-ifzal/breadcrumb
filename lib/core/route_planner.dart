/// Shortest route by steps along the recorded trail. Pure Dart.
library;

import 'contracts.dart';

/// Dijkstra on steps. Corridors can be walked either way; walking one from `to`
/// to `from` gives a reversed leg with heading + 180. Throws [ArgumentError] for
/// an unknown place or when there is no route.
class DijkstraRoutePlanner implements RoutePlanner {
  @override
  RoutePlan plan(MapGraph map, String fromId, String toId) {
    final ids = {for (final p in map.places) p.id};
    for (final id in [fromId, toId]) {
      if (!ids.contains(id)) throw ArgumentError('Unknown place $id');
    }

    final byNode = <String, List<Corridor>>{};
    for (final c in map.corridors) {
      byNode.putIfAbsent(c.from, () => []).add(c);
      byNode.putIfAbsent(c.to, () => []).add(c);
    }

    // Maps are a few dozen nodes, so a linear scan for the nearest node is fine.
    final dist = <String, int>{fromId: 0};
    final cameFrom = <String, (Corridor, String)>{};
    final done = <String>{};
    while (true) {
      String? here;
      for (final MapEntry(key: id, value: d) in dist.entries) {
        if (!done.contains(id) && (here == null || d < dist[here]!)) here = id;
      }
      if (here == null || here == toId) break;
      done.add(here);
      for (final c in byNode[here] ?? const <Corridor>[]) {
        final next = c.from == here ? c.to : c.from;
        final d = dist[here]! + c.steps;
        if (!done.contains(next) && d < (dist[next] ?? d + 1)) {
          dist[next] = d;
          cameFrom[next] = (c, here);
        }
      }
    }
    if (!dist.containsKey(toId)) {
      throw ArgumentError('No route from $fromId to $toId');
    }

    final legs = <Leg>[];
    for (var node = toId; node != fromId;) {
      final (c, prev) = cameFrom[node]!;
      final reversed = c.from != prev;
      legs.insert(
        0,
        Leg(
          corridorId: c.id,
          reversed: reversed,
          heading: reversed ? reversedHeading(c.heading) : c.heading,
          steps: c.steps,
        ),
      );
      node = prev;
    }
    return RoutePlan(legs: legs, totalSteps: dist[toId]!, toId: toId);
  }
}
