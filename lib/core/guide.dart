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
    if (r.legs.isEmpty || (i == last && p.stepsAlong >= r.legs[last].steps)) {
      return _arrive(r);
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

    final leg = r.legs[i];
    if (j == i && p.stepsAlong - leg.steps > leg.steps * overwalk) {
      return const Instruction(
        kind: InstructionKind.rescan,
        text: 'You may have passed the turn. Point the camera at a sign.',
      );
    }

    final turn = turnBetween(r.legs[j].heading, r.legs[j + 1].heading);
    final now = steps <= turnNowSteps;
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

  Instruction _arrive(RoutePlan r) {
    final name = map.places.firstWhere((p) => p.id == r.toId).name;
    return Instruction(
      kind: InstructionKind.arrive,
      placeName: name,
      text: '$name is here.',
    );
  }
}
