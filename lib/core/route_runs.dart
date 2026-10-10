/// Groups a route's legs into straight runs, shared by the Tracker and the Guide.
/// A place marked mid-corridor splits it into two legs with the same heading;
/// walking past it is straight on, not a turn. Pure Dart.
library;

import 'contracts.dart';
import 'tuning.dart';

/// True when going from leg [i] to leg [i] + 1 needs no turn. A stairs,
/// escalator or lift leg always ends a run (D24).
bool isStraightJoin(RoutePlan r, int i) =>
    !r.legs[i].isTransition &&
    !r.legs[i + 1].isTransition &&
    turnBetween(r.legs[i].heading, r.legs[i + 1].heading).abs() < straightTolerance;

/// The index of the last leg in the straight run that starts at leg [i]: the leg
/// that ends at the next turn, or the last leg of the route.
int runEnd(RoutePlan r, int i) {
  var j = i;
  while (j < r.legs.length - 1 && isStraightJoin(r, j)) {
    j++;
  }
  return j;
}

/// The `stepsAlong` at which [leg] is done. A transition leg counts as at least
/// one, so standing at the foot of a 0-step lift is never its end (D24).
int legLength(Leg leg) => leg.isTransition && leg.steps < 1 ? 1 : leg.steps;

/// Steps from the start of leg [from] to the end of leg [to], inclusive.
int stepsBetween(RoutePlan r, int from, int to) {
  var sum = 0;
  for (var k = from; k <= to; k++) {
    sum += r.legs[k].steps;
  }
  return sum;
}
