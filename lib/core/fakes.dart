/// Simple stand-ins for every interface in `contracts.dart`, so each person can build
/// against the contract before the real module lands. They are deliberately naive:
/// correct for plain cases, never tuned. Pure Dart.
library;

import 'dart:async';
import 'dart:collection';

import 'contracts.dart';
import 'tuning.dart';

/// Plans the route with the fewest corridors (not the fewest steps), walking
/// corridors either way. Throws [ArgumentError] when there is no route.
class FakeRoutePlanner implements RoutePlanner {
  @override
  RoutePlan plan(MapGraph map, String fromId, String toId) {
    final cameFrom = <String, (Corridor, String)>{};
    final seen = {fromId};
    final queue = Queue<String>()..add(fromId);
    while (queue.isNotEmpty && !seen.contains(toId)) {
      final here = queue.removeFirst();
      for (final c in map.corridors) {
        final String next;
        if (c.from == here) {
          next = c.to;
        } else if (c.to == here) {
          next = c.from;
        } else {
          continue;
        }
        if (seen.add(next)) {
          cameFrom[next] = (c, here);
          queue.add(next);
        }
      }
    }
    if (!seen.contains(toId)) {
      throw ArgumentError('No route from $fromId to $toId');
    }

    final legs = <Leg>[];
    for (var node = toId; node != fromId;) {
      final (c, prev) = cameFrom[node]!;
      final reversed = c.from != prev;
      legs.insert(
        0,
        Leg(
          corridorId: c.id,
          reversed: reversed,
          heading: reversed ? reversedHeading(c.heading) : c.heading,
          steps: c.steps,
        ),
      );
      node = prev;
    }
    return RoutePlan(
      legs: legs,
      totalSteps: legs.fold(0, (sum, l) => sum + l.steps),
      toId: toId,
    );
  }
}

/// Exact, case-insensitive match on a name or alias. Skips junctions.
class FakePlaceMatcher implements PlaceMatcher {
  @override
  PlaceMatch? match(String text, MapGraph map) {
    final wanted = text.trim().toLowerCase();
    for (final p in map.places) {
      if (p.kind == PlaceKind.junction) continue;
      if ([p.name, ...p.aliases].any((n) => n.toLowerCase() == wanted)) {
        return PlaceMatch(p.id, 1);
      }
    }
    return null;
  }
}

/// Counts steps along the route. Any turn (when not paused) snaps to the start of
/// the next leg, whatever its direction.
class FakeTracker implements Tracker {
  FakeTracker(this.map);

  final MapGraph map;
  RoutePlan? _route;
  bool _paused = false;
  Position _position = const Position(
    legIndex: 0,
    stepsAlong: 0,
    anchoredBy: AnchorSource.start,
  );

  @override
  void setRoute(RoutePlan r) {
    _route = r;
    _position = const Position(legIndex: 0, stepsAlong: 0, anchoredBy: AnchorSource.start);
  }

  @override
  Position onStep(StepEvent e) => _position = Position(
    legIndex: _position.legIndex,
    stepsAlong: _position.stepsAlong + 1,
    anchoredBy: _position.anchoredBy,
  );

  @override
  Position onTurn(TurnEvent e) {
    final route = _route;
    if (_paused || route == null || _position.legIndex >= route.legs.length - 1) {
      return _position;
    }
    return _position = Position(
      legIndex: _position.legIndex + 1,
      stepsAlong: 0,
      anchoredBy: AnchorSource.turn,
    );
  }

  @override
  Position anchor(String placeId) => _snapTo(placeId, AnchorSource.sign);

  @override
  Position tapHere(String placeId) => _snapTo(placeId, AnchorSource.tap);

  @override
  void pauseTurns(bool on) => _paused = on;

  /// Any floor change moves to the start of the next leg.
  @override
  Position onFloorChange(int delta) {
    final route = _route;
    if (route == null || _position.legIndex >= route.legs.length - 1) {
      return _position;
    }
    return _position = Position(
      legIndex: _position.legIndex + 1,
      stepsAlong: 0,
      anchoredBy: AnchorSource.floor,
    );
  }

  Position _snapTo(String placeId, AnchorSource source) {
    final route = _route;
    if (route != null) {
      for (var i = 0; i < route.legs.length; i++) {
        final leg = route.legs[i];
        final c = map.corridors.firstWhere((c) => c.id == leg.corridorId);
        final legStart = leg.reversed ? c.to : c.from;
        final legEnd = leg.reversed ? c.from : c.to;
        if (legStart == placeId) {
          return _position = Position(legIndex: i, stepsAlong: 0, anchoredBy: source);
        }
        if (legEnd == placeId && i == route.legs.length - 1) {
          return _position = Position(
            legIndex: i,
            stepsAlong: leg.steps,
            anchoredBy: source,
          );
        }
      }
    }
    return _position = Position(
      legIndex: _position.legIndex,
      stepsAlong: _position.stepsAlong,
      anchoredBy: source,
      needsReplan: true,
    );
  }
}

/// Says "walk straight" with the steps left on the leg, then "arrive" at the end of
/// the last leg. Never tells you to turn.
class FakeGuide implements Guide {
  FakeGuide(this.map);

  final MapGraph map;

  @override
  Instruction next(RoutePlan r, Position p) {
    final leg = r.legs[p.legIndex];
    final left = leg.steps - p.stepsAlong;
    if (p.legIndex == r.legs.length - 1 && left <= 0) {
      final name = map.places.firstWhere((pl) => pl.id == r.toId).name;
      return Instruction(
        kind: InstructionKind.arrive,
        placeName: name,
        text: '$name is here.',
      );
    }
    final steps = left < 0 ? 0 : left;
    return Instruction(
      kind: InstructionKind.straight,
      steps: steps,
      text: 'Walk straight, about $steps steps.',
    );
  }
}

/// A step whenever `accel` crosses [accelPeakThreshold] upwards, at most once per
/// [accelPeakMinGapMs].
class FakeStepDetector implements StepDetector {
  bool _above = false;
  int? _lastStepT;

  @override
  StepEvent? onMotion(int t, double accel) {
    final above = accel > accelPeakThreshold;
    final rising = above && !_above;
    _above = above;
    if (!rising) return null;
    final last = _lastStepT;
    if (last != null && t - last < accelPeakMinGapMs) return null;
    _lastStepT = t;
    return StepEvent(t);
  }
}

/// Never detects a turn.
class FakeTurnDetector implements TurnDetector {
  @override
  TurnEvent? onMotion(int t, double yawRate) => null;
}

/// Builds a chain map: each turn ends the current corridor at a new junction, each
/// place ends it at a new place. Place IDs are generated (`p1`, `j1`, ...).
class FakeMapBuilder implements MapBuilder {
  final _places = <Place>[];
  final _corridors = <Corridor>[];
  String? _startId;
  String? _lastNode;
  int _steps = 0;
  double _heading = 0;
  int _junctions = 0;

  @override
  void start(String placeName) {
    _places.clear();
    _corridors.clear();
    _startId = _lastNode = 'p0';
    _places.add(Place(id: 'p0', name: placeName, kind: PlaceKind.start));
    _steps = 0;
    _heading = 0;
    _junctions = 0;
  }

  @override
  void onStep(StepEvent e) => _steps++;

  @override
  void onTurn(TurnEvent e) {
    _junctions++;
    _closeCorridorAt(
      Place(id: 'j$_junctions', name: 'Junction $_junctions', kind: PlaceKind.junction),
    );
    _heading = normalizeHeading(_heading + e.angle);
  }

  @override
  void addPlace(String name, List<String> aliases) => _closeCorridorAt(
    Place(id: 'p${_places.length}', name: name, aliases: aliases, kind: PlaceKind.place),
  );

  @override
  MapGraph snapshot() {
    final from = _lastNode;
    if (from == null) throw StateError('snapshot() before start()');
    final map = finish();
    return MapGraph(
      name: map.name,
      start: map.start,
      places: [
        ...map.places,
        const Place(id: hereId, name: 'You are here', kind: PlaceKind.junction),
      ],
      corridors: [
        ...map.corridors,
        Corridor(
          id: 'c${map.corridors.length + 1}',
          from: from,
          to: hereId,
          steps: _steps,
          heading: _heading,
        ),
      ],
    );
  }

  @override
  MapGraph finish() {
    final start = _startId;
    if (start == null) throw StateError('finish() before start()');
    return MapGraph(
      name: _places.first.name,
      start: start,
      places: List.of(_places),
      corridors: List.of(_corridors),
    );
  }

  void _closeCorridorAt(Place place) {
    final from = _lastNode;
    if (from == null) throw StateError('start() first');
    _places.add(place);
    _corridors.add(
      Corridor(
        id: 'c${_corridors.length + 1}',
        from: from,
        to: place.id,
        steps: _steps,
        heading: _heading,
      ),
    );
    _lastNode = place.id;
    _steps = 0;
  }
}

/// Plays back a scripted list of [StepEvent]s and [TurnEvent]s. Records trace calls.
class FakeSensingSource implements SensingSource {
  FakeSensingSource([this.script = const []]);

  final List<Object> script;
  Map<String, Object?>? traceMeta;
  bool tracing = false;
  final marks = <String>[];

  @override
  Stream<Object> events() => Stream.fromIterable(script);

  @override
  Future<void> startTrace(Map<String, Object?> meta) async {
    traceMeta = meta;
    tracing = true;
  }

  @override
  Future<void> stopTrace() async => tracing = false;

  @override
  void mark(String note) => marks.add(note);
}

/// Returns the text registered for an image path, or `null`.
class FakeSignReader implements SignReader {
  FakeSignReader([this.textByPath = const {}]);

  final Map<String, String> textByPath;

  @override
  Future<SignReading?> read(String imagePath) async {
    final text = textByPath[imagePath];
    return text == null
        ? null
        : SignReading(t: 0, text: text, reader: ReaderKind.mlkit);
  }
}

/// Resolves with [FakePlaceMatcher] only; no Gemma.
class FakeDestinationResolver implements DestinationResolver {
  final _matcher = FakePlaceMatcher();

  @override
  Future<PlaceMatch?> resolve(String utterance, MapGraph map) async =>
      _matcher.match(utterance, map);
}

/// Records what it was asked to say and vibrate.
class FakeSpeaker implements Speaker {
  final spoken = <Instruction>[];
  final vibrations = <InstructionKind>[];

  @override
  Future<void> speak(Instruction i) async => spoken.add(i);

  @override
  Future<void> vibrate(InstructionKind k) async => vibrations.add(k);
}
