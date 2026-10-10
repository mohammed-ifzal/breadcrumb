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

  /// Floors moved towards the next transition leg so far (D24).
  int _floorsMoved = 0;

  /// True from [setRoute] until the first step: turns only update [_facing] (D27).
  bool _orienting = true;

  /// The assumed facing while orienting, in map degrees; null when unknown.
  double? _facing;

  static const _origin = Position(
    legIndex: 0,
    stepsAlong: 0,
    anchoredBy: AnchorSource.start,
  );

  /// The latest position, for screens that redraw without an event.
  Position get position => _position;

  /// Starts the orientation phase (D27): until the first step, turns are not
  /// route turns. The assumed facing is the heading of the corridor the walker
  /// arrived on when the route starts where the recording ended, else unknown.
  @override
  void setRoute(RoutePlan r) {
    _route = r;
    _floorsMoved = 0;
    _orienting = true;
    _facing = _arrivalFacing(r);
    _set(_origin);
  }

  double? _arrivalFacing(RoutePlan r) {
    if (r.legs.isEmpty || map.corridors.isEmpty) return null;
    final arrivedOn = map.corridors.last;
    return arrivedOn.to == _legStart(r.legs.first) ? arrivedOn.heading : null;
  }

  @override
  void pauseTurns(bool on) => _paused = on;

  bool get _onTransition {
    final route = _route;
    final i = _position.legIndex;
    return route != null && i < route.legs.length && route.legs[i].isTransition;
  }

  /// One step along the current leg. The first step ends the orientation phase
  /// (D27). At the end of a leg that joins the next one straight on (a place
  /// marked mid-corridor), carry on into the next leg. At the end of a leg before
  /// stairs, an escalator or a lift, move onto it; steps on it are ignored (D24).
  /// A corner is passed only by a turn, or by walking more than [overwalk] of the
  /// run past it with no turn seen: then the position moves to the start of the
  /// next leg, so the real turn, if it comes late, is absorbed (D26, D27).
  @override
  Position onStep(StepEvent e) {
    _orienting = false;
    if (_onTransition) return _set(_position);
    var leg = _position.legIndex;
    var along = _position.stepsAlong + 1;
    final route = _route;
    if (route != null) {
      while (leg < route.legs.length - 1 &&
          along >= route.legs[leg].steps &&
          (isStraightJoin(route, leg) || route.legs[leg + 1].isTransition)) {
        along -= route.legs[leg].steps;
        leg++;
        if (route.legs[leg].isTransition) {
          along = 0;
          break;
        }
      }
      final j = runEnd(route, leg);
      if (!_position.offRoute && j < route.legs.length - 1 && !route.legs[leg].isTransition) {
        final run = stepsBetween(route, leg, j);
        if (along - run > run * overwalk) {
          leg = j + 1;
          along = 0;
        }
      }
    }
    return _set(_copy(legIndex: leg, stepsAlong: along));
  }

  /// Completes the next transition leg (the current leg or the first one after
  /// it) once the floors moved in its direction reach its `floorDelta`: the
  /// position moves to the start of the leg after it, or to arrival when it is
  /// the last leg. Floor changes the other way, or with no transition ahead,
  /// are ignored (D24).
  @override
  Position onFloorChange(int delta) {
    final route = _route;
    if (route == null || delta == 0) return _position;
    var k = _position.legIndex;
    while (k < route.legs.length && !route.legs[k].isTransition) {
      k++;
    }
    if (k >= route.legs.length) return _position;
    final need = route.legs[k].floorDelta;
    if (need == 0 || delta.sign != need.sign) return _position;

    _floorsMoved += delta;
    if (_floorsMoved.abs() < need.abs()) return _position;
    _floorsMoved = 0;
    final last = route.legs.length - 1;
    return _set(
      Position(
        legIndex: k == last ? last : k + 1,
        stepsAlong: k == last ? legLength(route.legs[last]) : 0,
        anchoredBy: AnchorSource.floor,
      ),
    );
  }

  /// A turn in the expected direction near the next turning point snaps to the
  /// start of the leg after it. A turn in the wrong direction, far from the
  /// turning point, or where the route goes straight on sets [Position.offRoute].
  ///
  /// Before the first step a turn only updates the assumed facing (D27). While
  /// off route, only a turn that matches the next turning point within
  /// 2 x [snapSteps] counts: it snaps back onto the route (D27). Turns after
  /// arriving are ignored, and so is the turn at a node the position already
  /// moved past ("I am here", a sign or a turn snap) when it comes within
  /// [lateTurnSteps] of that node in the expected direction (D26). Turns on a
  /// stairs, escalator or lift leg are ignored (D24).
  @override
  Position onTurn(TurnEvent e) {
    final route = _route;
    if (_paused || route == null || route.legs.isEmpty) return _position;
    if (_orienting) {
      final facing = _facing;
      if (facing != null) _facing = normalizeHeading(facing + e.angle);
      return _set(_position);
    }
    if (_onTransition) return _position;
    if (_position.offRoute) return _set(_recover(route, e) ?? _position);

    final i = _position.legIndex;
    final last = route.legs.length - 1;
    if (i >= last && _position.stepsAlong >= legLength(route.legs[last])) {
      return _position;
    }
    if (i > 0 && _position.stepsAlong <= lateTurnSteps) {
      final passed = turnBetween(route.legs[i - 1].heading, route.legs[i].heading);
      if (passed.abs() >= straightTolerance && _isRightWay(e.angle, passed)) {
        return _position;
      }
    }

    final j = runEnd(route, i);
    if (j == last) return _set(_copy(offRoute: true));

    final needed = turnBetween(route.legs[j].heading, route.legs[j + 1].heading);
    final run = stepsBetween(route, i, j);
    final toTurn = run - _position.stepsAlong;
    final near = toTurn <= snapSteps || toTurn <= run * snapZone;

    if (near && _isRightWay(e.angle, needed)) return _set(_afterTurn(j));
    return _set(_copy(offRoute: true));
  }

  /// Off route: a turn in the direction the next turning point needs, within
  /// 2 x [snapSteps] of it either side, puts the position back after it.
  Position? _recover(RoutePlan route, TurnEvent e) {
    final i = _position.legIndex;
    final j = runEnd(route, i);
    if (j >= route.legs.length - 1) return null;
    final needed = turnBetween(route.legs[j].heading, route.legs[j + 1].heading);
    final toTurn = stepsBetween(route, i, j) - _position.stepsAlong;
    if (toTurn.abs() > 2 * snapSteps || !_isRightWay(e.angle, needed)) return null;
    return _afterTurn(j);
  }

  static Position _afterTurn(int j) =>
      Position(legIndex: j + 1, stepsAlong: 0, anchoredBy: AnchorSource.turn);

  static bool _isRightWay(double angle, double needed) =>
      needed.abs() > turnAroundAngle
          ? angle.abs() > turnAroundAngle
          : angle.sign == needed.sign;

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
    _floorsMoved = 0;
    if (route == null || route.legs.isEmpty) {
      return _set(_copy(anchoredBy: source, needsReplan: true));
    }

    // nodes[k] is where leg k starts; the last entry is the destination.
    final nodes = [
      for (final leg in route.legs) _legStart(leg),
      route.toId,
    ];
    final current = _position.legIndex;
    var k = nodes.indexOf(placeId, current);
    if (k < 0) k = nodes.indexOf(placeId);
    if (k < 0) return _set(_copy(anchoredBy: source, needsReplan: true));

    final last = route.legs.length - 1;
    return _set(
      Position(
        legIndex: k > last ? last : k,
        stepsAlong: k > last ? legLength(route.legs[last]) : 0,
        anchoredBy: source,
      ),
    );
  }

  String _legStart(Leg leg) {
    final c = map.corridors.firstWhere((c) => c.id == leg.corridorId);
    return leg.reversed ? c.to : c.from;
  }

  /// Stores [p] as the position, carrying the orientation phase and facing.
  Position _set(Position p) => _position = Position(
    legIndex: p.legIndex,
    stepsAlong: p.stepsAlong,
    anchoredBy: p.anchoredBy,
    offRoute: p.offRoute,
    needsReplan: p.needsReplan,
    orienting: _orienting,
    facing: _orienting ? _facing : null,
  );

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
