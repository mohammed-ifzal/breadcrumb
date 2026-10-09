/// Position along a planned route from steps, turns and anchors, following the
/// Tracker rules in docs/CONTRACTS.md. Pure Dart.
library;

import 'contracts.dart';
import 'route_runs.dart';
import 'tuning.dart';

class RouteTracker implements Tracker {
  RouteTracker(this.map);

  final MapGraph map;
  RoutePlan? _route;
  bool _paused = false;
  Position _position = _origin;

  static const _origin = Position(
    legIndex: 0,
    stepsAlong: 0,
    anchoredBy: AnchorSource.start,
  );

  /// The latest position, for screens that redraw without an event.
  Position get position => _position;

  @override
  void setRoute(RoutePlan r) {
    _route = r;
    _position = _origin;
  }

  @override
  void pauseTurns(bool on) => _paused = on;

  /// One step along the current leg. At the end of a leg that joins the next one
  /// straight on (a place marked mid-corridor), carry on into the next leg.
  @override
  Position onStep(StepEvent e) {
    var leg = _position.legIndex;
    var along = _position.stepsAlong + 1;
    final route = _route;
    if (route != null) {
      while (leg < route.legs.length - 1 &&
          along >= route.legs[leg].steps &&
          isStraightJoin(route, leg)) {
        along -= route.legs[leg].steps;
        leg++;
      }
    }
    return _position = _copy(legIndex: leg, stepsAlong: along);
  }

  /// A turn in the expected direction near the next turning point snaps to the
  /// start of the leg after it. A turn in the wrong direction, far from the
  /// turning point, or where the route goes straight on sets [Position.offRoute].
  /// Once off route, turns are ignored until an anchor or a new route.
  @override
  Position onTurn(TurnEvent e) {
    final route = _route;
    if (_paused || route == null || route.legs.isEmpty || _position.offRoute) {
      return _position;
    }

    final i = _position.legIndex;
    final j = runEnd(route, i);
    if (j == route.legs.length - 1) return _position = _copy(offRoute: true);

    final needed = turnBetween(route.legs[j].heading, route.legs[j + 1].heading);
    final run = stepsBetween(route, i, j);
    final toTurn = run - _position.stepsAlong;
    final near = toTurn <= snapSteps || toTurn <= run * snapZone;
    final rightWay = needed.abs() > turnAroundAngle
        ? e.angle.abs() > turnAroundAngle
        : e.angle.sign == needed.sign;

    if (near && rightWay) {
      return _position = Position(
        legIndex: j + 1,
        stepsAlong: 0,
        anchoredBy: AnchorSource.turn,
      );
    }
    return _position = _copy(offRoute: true);
  }

  @override
  Position anchor(String placeId) => _snapTo(placeId, AnchorSource.sign);

  @override
  Position tapHere(String placeId) => _snapTo(placeId, AnchorSource.tap);

  /// Moves to [placeId] on the route: the start of the leg leaving it, or the end
  /// of the last leg for the destination. If the route passes it twice, the first
  /// visit from the current leg on wins. Off the route, the position stays and
  /// [Position.needsReplan] is set.
  Position _snapTo(String placeId, AnchorSource source) {
    if (!map.places.any((p) => p.id == placeId)) {
      throw ArgumentError('Unknown place $placeId');
    }
    final route = _route;
    if (route == null || route.legs.isEmpty) {
      return _position = _copy(anchoredBy: source, needsReplan: true);
    }

    // nodes[k] is where leg k starts; the last entry is the destination.
    final nodes = [
      for (final leg in route.legs) _legStart(leg),
      route.toId,
    ];
    final current = _position.legIndex;
    var k = nodes.indexOf(placeId, current);
    if (k < 0) k = nodes.indexOf(placeId);
    if (k < 0) return _position = _copy(anchoredBy: source, needsReplan: true);

    final last = route.legs.length - 1;
    return _position = Position(
      legIndex: k > last ? last : k,
      stepsAlong: k > last ? route.legs[last].steps : 0,
      anchoredBy: source,
    );
  }

  String _legStart(Leg leg) {
    final c = map.corridors.firstWhere((c) => c.id == leg.corridorId);
    return leg.reversed ? c.to : c.from;
  }

  Position _copy({
    int? legIndex,
    int? stepsAlong,
    AnchorSource? anchoredBy,
    bool? offRoute,
    bool? needsReplan,
  }) => Position(
    legIndex: legIndex ?? _position.legIndex,
    stepsAlong: stepsAlong ?? _position.stepsAlong,
    anchoredBy: anchoredBy ?? _position.anchoredBy,
    offRoute: offRoute ?? _position.offRoute,
    needsReplan: needsReplan ?? _position.needsReplan,
  );
}
