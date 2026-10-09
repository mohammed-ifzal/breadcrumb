/// Groups a route's legs into straight runs, shared by the Tracker and the Guide.
/// A place marked mid-corridor splits it into two legs with the same heading;
/// walking past it is straight on, not a turn. Pure Dart.
library;

import 'contracts.dart';
import 'tuning.dart';

/// True when going from leg [i] to leg [i] + 1 needs no turn.
bool isStraightJoin(RoutePlan r, int i) =>
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

/// Steps from the start of leg [from] to the end of leg [to], inclusive.
int stepsBetween(RoutePlan r, int from, int to) {
  var sum = 0;
  for (var k = from; k <= to; k++) {
    sum += r.legs[k].steps;
  }
  return sum;
}
