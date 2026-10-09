/// Turns a [MapGraph] into x/y points, for the trail view and the laptop map desk.
/// Pure Dart.
library;

import 'dart:collection';
import 'dart:math' as math;

import 'contracts.dart';

/// A node's position in steps. The walk starts at (0, 0) facing +y; heading 90
/// (a left turn) faces -x. y grows upwards, so screen code must flip it.
class TrailPoint {
  const TrailPoint(this.placeId, this.x, this.y);

  final String placeId;
  final double x;
  final double y;
}

/// Lays out every node reachable from `map.start` by walking corridors in either
/// direction. On a loop, the first route found to a node wins. Unreachable nodes
/// are left out.
List<TrailPoint> layoutMap(MapGraph map) {
  final byNode = <String, List<Corridor>>{};
  for (final c in map.corridors) {
    byNode.putIfAbsent(c.from, () => []).add(c);
    byNode.putIfAbsent(c.to, () => []).add(c);
  }

  final points = <String, TrailPoint>{map.start: TrailPoint(map.start, 0, 0)};
  final queue = Queue<String>()..add(map.start);
  while (queue.isNotEmpty) {
    final here = points[queue.removeFirst()]!;
    for (final c in byNode[here.placeId] ?? const <Corridor>[]) {
      final forward = c.from == here.placeId;
      final next = forward ? c.to : c.from;
      if (points.containsKey(next)) continue;
      final heading = forward ? c.heading : reversedHeading(c.heading);
      final rad = heading * math.pi / 180;
      points[next] = TrailPoint(
        next,
        here.x - c.steps * math.sin(rad),
        here.y + c.steps * math.cos(rad),
      );
      queue.add(next);
    }
  }
  return points.values.toList();
}
