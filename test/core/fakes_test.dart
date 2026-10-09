import 'package:breadcrumb/core/contracts.dart';
import 'package:breadcrumb/core/fakes.dart';
import 'package:breadcrumb/core/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

// entrance --10--> j1 --5 (left)--> cafe
const _map = MapGraph(
  name: 'L',
  start: 'entrance',
  places: [
    Place(id: 'entrance', name: 'Entrance', kind: PlaceKind.start),
    Place(id: 'j1', name: 'Junction 1', kind: PlaceKind.junction),
    Place(id: 'cafe', name: 'Cafe', aliases: ['coffee'], kind: PlaceKind.place),
    Place(id: 'island', name: 'Island', kind: PlaceKind.place),
  ],
  corridors: [
    Corridor(id: 'c1', from: 'entrance', to: 'j1', steps: 10, heading: 0),
    Corridor(id: 'c2', from: 'j1', to: 'cafe', steps: 5, heading: 90),
  ],
);

void main() {
  group('FakeRoutePlanner', () {
    final planner = FakeRoutePlanner();

    test('plans forward along corridors', () {
      final r = planner.plan(_map, 'entrance', 'cafe');
      expect(r.legs.map((l) => l.corridorId), ['c1', 'c2']);
      expect(r.legs.every((l) => !l.reversed), isTrue);
      expect(r.totalSteps, 15);
      expect(r.toId, 'cafe');
    });

    test('plans backward with reversed headings', () {
      final r = planner.plan(_map, 'cafe', 'entrance');
      expect(r.legs.map((l) => l.corridorId), ['c2', 'c1']);
      expect(r.legs.map((l) => l.reversed), [true, true]);
      expect(r.legs.map((l) => l.heading), [270, 180]);
    });

    test('throws when there is no route', () {
      expect(() => planner.plan(_map, 'entrance', 'island'), throwsArgumentError);
    });
  });

  group('FakePlaceMatcher', () {
    final matcher = FakePlaceMatcher();

    test('matches names and aliases, ignoring case', () {
      expect(matcher.match('CAFE', _map)?.placeId, 'cafe');
      expect(matcher.match(' coffee ', _map)?.placeId, 'cafe');
    });

    test('never matches junctions or unknown text', () {
      expect(matcher.match('Junction 1', _map), isNull);
      expect(matcher.match('platform 9', _map), isNull);
    });
  });

  group('FakeTracker', () {
    late FakeTracker tracker;
    setUp(() {
      tracker = FakeTracker(_map)..setRoute(FakeRoutePlanner().plan(_map, 'entrance', 'cafe'));
    });

    test('steps move along the leg; a turn snaps to the next leg', () {
      for (var i = 0; i < 9; i++) {
        tracker.onStep(StepEvent(i));
      }
      final p = tracker.onTurn(const TurnEvent(10, 90));
      expect(p.legIndex, 1);
      expect(p.stepsAlong, 0);
      expect(p.anchoredBy, AnchorSource.turn);
    });

    test('turns are ignored while paused', () {
      tracker.pauseTurns(true);
      expect(tracker.onTurn(const TurnEvent(0, 90)).legIndex, 0);
      tracker.pauseTurns(false);
      expect(tracker.onTurn(const TurnEvent(1, 90)).legIndex, 1);
    });

    test('anchor on the route moves there; off the route asks for a replan', () {
      final p = tracker.anchor('j1');
      expect(p.legIndex, 1);
      expect(p.anchoredBy, AnchorSource.sign);
      expect(p.needsReplan, isFalse);
      expect(tracker.tapHere('cafe').stepsAlong, 5);
      expect(tracker.anchor('island').needsReplan, isTrue);
    });
  });

  test('FakeGuide says straight, then arrive', () {
    final r = FakeRoutePlanner().plan(_map, 'entrance', 'cafe');
    final guide = FakeGuide(_map);
    final first = guide.next(
      r,
      const Position(legIndex: 0, stepsAlong: 4, anchoredBy: AnchorSource.start),
    );
    expect(first.kind, InstructionKind.straight);
    expect(first.text, 'Walk straight, about 6 steps.');
    final last = guide.next(
      r,
      const Position(legIndex: 1, stepsAlong: 5, anchoredBy: AnchorSource.start),
    );
    expect(last.kind, InstructionKind.arrive);
    expect(last.text, 'Cafe is here.');
  });

  test('FakeStepDetector counts rising peaks with a minimum gap', () {
    final d = FakeStepDetector();
    final hi = accelPeakThreshold + 1;
    final lo = accelPeakThreshold - 2;
    expect(d.onMotion(0, hi)?.t, 0);
    expect(d.onMotion(20, hi), isNull); // still above: same peak
    expect(d.onMotion(40, lo), isNull);
    expect(d.onMotion(100, hi), isNull); // too soon after the last step
    expect(d.onMotion(200, lo), isNull);
    expect(d.onMotion(400, hi)?.t, 400);
  });

  test('FakeTurnDetector never fires', () {
    expect(FakeTurnDetector().onMotion(0, 200), isNull);
  });

  test('FakeMapBuilder makes a chain with junctions at turns', () {
    final b = FakeMapBuilder()..start('Table');
    for (var i = 0; i < 10; i++) {
      b.onStep(StepEvent(i));
    }
    b.onTurn(const TurnEvent(10, 90));
    for (var i = 0; i < 5; i++) {
      b.onStep(StepEvent(20 + i));
    }
    b.addPlace('Food counter', ['coffee']);
    final map = b.finish();

    expect(map.start, 'p0');
    expect(map.places.map((p) => p.kind), [
      PlaceKind.start,
      PlaceKind.junction,
      PlaceKind.place,
    ]);
    expect(map.corridors.map((c) => c.steps), [10, 5]);
    expect(map.corridors.map((c) => c.heading), [0, 90]);
    expect(map.corridors[1].to, map.places[2].id);
    expect(map.places[2].aliases, ['coffee']);
  });

  test('FakeMapBuilder.snapshot ends the open corridor at _here', () {
    final b = FakeMapBuilder()..start('Table');
    b.onStep(const StepEvent(0));
    b.onTurn(const TurnEvent(1, -90));
    b.onStep(const StepEvent(2));
    b.onStep(const StepEvent(3));
    final snap = b.snapshot();

    expect(snap.places.last.id, hereId);
    expect(snap.places.last.kind, PlaceKind.junction);
    expect(snap.corridors.last.from, 'j1');
    expect(snap.corridors.last.to, hereId);
    expect(snap.corridors.last.steps, 2);
    expect(snap.corridors.last.heading, 270);
    // snapshot() doesn't change the builder.
    expect(b.finish().places.map((p) => p.id), ['p0', 'j1']);
  });

  test('FakeSensingSource plays its script and records trace calls', () async {
    final s = FakeSensingSource([const StepEvent(1), const TurnEvent(2, -90)]);
    expect(await s.events().toList(), hasLength(2));
    await s.startTrace({'walker': 'T2'});
    expect(s.tracing, isTrue);
    s.mark('arrived');
    await s.stopTrace();
    expect(s.tracing, isFalse);
    expect(s.marks, ['arrived']);
  });

  test('FakeSignReader returns registered text only', () async {
    final r = FakeSignReader({'a.jpg': 'CAFE'});
    expect((await r.read('a.jpg'))?.text, 'CAFE');
    expect(await r.read('b.jpg'), isNull);
  });

  test('FakeDestinationResolver uses exact matching', () async {
    final r = FakeDestinationResolver();
    expect((await r.resolve('coffee', _map))?.placeId, 'cafe');
    expect(await r.resolve('where can I get coffee', _map), isNull);
  });

  test('FakeSpeaker records calls', () async {
    final s = FakeSpeaker();
    await s.speak(const Instruction(kind: InstructionKind.arrive, text: 'x'));
    await s.vibrate(InstructionKind.turnLeft);
    expect(s.spoken, hasLength(1));
    expect(s.vibrations, [InstructionKind.turnLeft]);
  });
}
