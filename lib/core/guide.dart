/// Turns a route and a position into the next instruction, following the Guide
/// rules and instruction text in docs/CONTRACTS.md. Pure Dart.
library;

import 'contracts.dart';
import 'route_runs.dart';
import 'tuning.dart';

class RouteGuide implements Guide {
  RouteGuide(this.map);

  final MapGraph map;

  @override
  Instruction next(RoutePlan r, Position p) {
    if (p.offRoute) {
      return const Instruction(
        kind: InstructionKind.offRoute,
        text: "Looks like you went off the path. Go back to the last corner or tap I'm here.",
      );
    }
    final last = r.legs.length - 1;
    final i = p.legIndex.clamp(0, last < 0 ? 0 : last);
    if (r.legs.isEmpty || (i == last && p.stepsAlong >= legLength(r.legs[last]))) {
      return _arrive(r);
    }
    if (r.legs[i].isTransition) return _changeFloor(r.legs[i]);
    if (p.orienting) {
      final face = _orient(r, i, p.facing);
      if (face != null) return face;
    }

    // Distance to the next turn, or to the destination, across straight-on joins.
    final j = runEnd(r, i);
    final ahead = stepsBetween(r, i, j) - p.stepsAlong;
    final steps = ahead < 0 ? 0 : ahead;
    if (j == last) {
      return Instruction(
        kind: InstructionKind.straight,
        steps: steps,
        text: 'Walk straight, about $steps steps.',
      );
    }

    final now = steps <= turnNowSteps;
    final next = r.legs[j + 1];
    if (next.isTransition) return _changeFloor(next, steps: steps);

    final turn = turnBetween(r.legs[j].heading, next.heading);
    if (turn.abs() > turnAroundAngle) {
      return now
          ? const Instruction(kind: InstructionKind.turnAround, text: 'Turn around.')
          : Instruction(
              kind: InstructionKind.straight,
              steps: steps,
              text: 'Walk straight, about $steps steps.',
            );
    }

    // Step counts drift, so near the corner it says "get ready" and only "at the
    // corner" once the counted steps run out (D27).
    final left = turn > 0;
    final side = left ? 'left' : 'right';
    return Instruction(
      kind: left ? InstructionKind.turnLeft : InstructionKind.turnRight,
      steps: steps,
      text: steps == 0
          ? 'Turn $side at the corner.'
          : now
          ? 'Get ready to turn $side.'
          : 'In about $steps steps, turn $side.',
    );
  }

  /// Before the first step (D27): turn the walker to face leg [i]. Null when the
  /// assumed [facing] already points along it (within [straightTolerance]).
  Instruction? _orient(RoutePlan r, int i, double? facing) {
    if (facing == null) {
      return Instruction(
        kind: InstructionKind.straight,
        text: 'Face ${_nextPlaceName(r, i)} and start walking.',
      );
    }
    final turn = turnBetween(facing, r.legs[i].heading);
    if (turn.abs() < straightTolerance) return null;
    if (turn.abs() > turnAroundAngle) {
      return const Instruction(
        kind: InstructionKind.turnAround,
        text: 'Turn around, then walk straight.',
      );
    }
    final left = turn > 0;
    return Instruction(
      kind: left ? InstructionKind.turnLeft : InstructionKind.turnRight,
      text: 'Turn ${left ? 'left' : 'right'}, then walk straight.',
    );
  }

  /// The first named place (not a junction) the route reaches from leg [i] on.
  String _nextPlaceName(RoutePlan r, int i) {
    for (var k = i; k < r.legs.length; k++) {
      final leg = r.legs[k];
      final c = map.corridors.firstWhere((c) => c.id == leg.corridorId);
      final end = map.places.firstWhere((p) => p.id == (leg.reversed ? c.from : c.to));
      if (end.kind != PlaceKind.junction) return end.name;
    }
    return map.places.firstWhere((p) => p.id == r.toId).name;
  }

  /// "Take the stairs up to Floor 1." on the leg and in the last [turnNowSteps]
  /// before it; "In about N steps, take ..." further away (D24).
  Instruction _changeFloor(Leg leg, {int? steps}) {
    final c = map.corridors.firstWhere((c) => c.id == leg.corridorId);
    final floor = map.places.firstWhere((p) => p.id == (leg.reversed ? c.from : c.to)).floor;
    final way = leg.floorDelta > 0
        ? ' up'
        : leg.floorDelta < 0
        ? ' down'
        : '';
    final take = 'the ${leg.kind.name}$way to Floor $floor.';
    return Instruction(
      kind: InstructionKind.changeFloor,
      steps: steps,
      text: steps == null || steps <= turnNowSteps
          ? 'Take $take'
          : 'In about $steps steps, take $take',
    );
  }

  Instruction _arrive(RoutePlan r) {
    final name = map.places.firstWhere((p) => p.id == r.toId).name;
    return Instruction(
      kind: InstructionKind.arrive,
      placeName: name,
      text: '$name is here.',
    );
  }
}
