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
        text: "That turn wasn't on the route. Scan a nearby sign to re-locate.",
      );
    }
    final last = r.legs.length - 1;
    final i = p.legIndex.clamp(0, last < 0 ? 0 : last);
    if (r.legs.isEmpty || (i == last && p.stepsAlong >= legLength(r.legs[last]))) {
      return _arrive(r);
    }
    if (r.legs[i].isTransition) return _changeFloor(r.legs[i]);

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

    final leg = r.legs[i];
    if (j == i && p.stepsAlong - leg.steps > leg.steps * overwalk) {
      return const Instruction(
        kind: InstructionKind.rescan,
        text: 'You may have passed the turn. Point the camera at a sign.',
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

    final left = turn > 0;
    final side = left ? 'left' : 'right';
    return Instruction(
      kind: left ? InstructionKind.turnLeft : InstructionKind.turnRight,
      steps: steps,
      text: now ? 'Turn $side now.' : 'In about $steps steps, turn $side.',
    );
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
