import 'package:breadcrumb/core/route_planner.dart';
import 'package:breadcrumb/core/route_runs.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_maps.dart';

void main() {
  // start -> stage_side: c1 (12, h0) | left | c2 (10, h90) - c3 (8, h90) | right | c4 (6, h0)
  final r = DijkstraRoutePlanner().plan(demoMap, 'start', 'stage_side');

  test('isStraightJoin is true only across a marked place', () {
    expect(isStraightJoin(r, 0), isFalse);
    expect(isStraightJoin(r, 1), isTrue);
    expect(isStraightJoin(r, 2), isFalse);
  });

  test('runEnd stops at the next turn or the last leg', () {
    expect(runEnd(r, 0), 0);
    expect(runEnd(r, 1), 2);
    expect(runEnd(r, 2), 2);
    expect(runEnd(r, 3), 3);
  });

  test('stepsBetween sums legs inclusively', () {
    expect(stepsBetween(r, 1, 2), 18);
    expect(stepsBetween(r, 0, 3), 36);
    expect(stepsBetween(r, 3, 3), 6);
  });
}
