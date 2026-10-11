import 'package:breadcrumb/app/speaker.dart';
import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/guide.dart';
import 'package:breadcrumb/core/route_planner.dart';
import 'package:flutter_test/flutter_test.dart';

/// "1 step", never "1 steps", in every spoken or shown step count.
void main() {
  test('stepCount', () {
    expect(stepCount(0), '0 steps');
    expect(stepCount(1), '1 step');
    expect(stepCount(2), '2 steps');
    expect(stepCount(14), '14 steps');
  });

  const map = MapGraph(
    name: 'Line',
    start: 'a',
    places: [
      Place(id: 'a', name: 'A', kind: PlaceKind.start),
      Place(id: 'j', name: 'Junction 1', kind: PlaceKind.junction),
      Place(id: 'b', name: 'B', kind: PlaceKind.place),
    ],
    corridors: [
      Corridor(id: 'c1', from: 'a', to: 'j', steps: 10, heading: 0),
      Corridor(id: 'c2', from: 'j', to: 'b', steps: 5, heading: 90),
    ],
  );

  Position at(int leg, int along) =>
      Position(legIndex: leg, stepsAlong: along, anchoredBy: AnchorSource.turn);

  test('Guide: one step to go is singular, more is plural', () {
    final r = DijkstraRoutePlanner().plan(map, 'a', 'b');
    final guide = RouteGuide(map);
    expect(guide.next(r, at(1, 4)).text, 'Walk straight, about 1 step.');
    expect(guide.next(r, at(1, 3)).text, 'Walk straight, about 2 steps.');
    expect(guide.next(r, at(0, 2)).text, 'In about 8 steps, turn left.');
  });

  test('Guide: no instruction text says "1 steps" on a whole walk', () {
    final r = DijkstraRoutePlanner().plan(map, 'a', 'b');
    final guide = RouteGuide(map);
    for (var leg = 0; leg < r.legs.length; leg++) {
      for (var s = 0; s <= r.legs[leg].steps; s++) {
        expect(guide.next(r, at(leg, s)).text, isNot(contains('1 steps')));
      }
    }
  });

  test('Speaker keeps plural counts for spoken turns', () {
    expect(
      AppSpeaker.formatSpeech(
        const Instruction(kind: InstructionKind.turnLeft, steps: 8, text: ''),
      ),
      'In 8 steps, turn left.',
    );
  });
}
