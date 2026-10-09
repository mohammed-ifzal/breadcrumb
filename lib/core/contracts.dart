/// The shapes and interfaces every module agrees on.
///
/// This file mirrors `docs/CONTRACTS.md`. Only the captain changes it, together with
/// that document. Pure Dart: no Flutter, no plugins, no I/O.
library;

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum PlaceKind { start, junction, place }

/// What last fixed the position.
enum AnchorSource { start, turn, sign, tap }

enum InstructionKind {
  straight,
  turnLeft,
  turnRight,
  turnAround,
  arrive,
  offRoute,
  rescan,
}

enum ReaderKind { mlkit, gemma }

// ---------------------------------------------------------------------------
// Heading conventions
// ---------------------------------------------------------------------------

/// Wraps [degrees] into [0, 360).
double normalizeHeading(double degrees) {
  final h = degrees % 360;
  return h < 0 ? h + 360 : h;
}

/// The heading of a corridor walked from `to` back to `from`.
double reversedHeading(double heading) => normalizeHeading(heading + 180);

/// The turn needed to go from heading [from] to heading [to], in (-180, 180].
/// Positive is a left turn.
double turnBetween(double from, double to) {
  final d = normalizeHeading(to - from);
  return d > 180 ? d - 360 : d;
}

// ---------------------------------------------------------------------------
// Map
// ---------------------------------------------------------------------------

class Place {
  const Place({
    required this.id,
    required this.name,
    this.aliases = const [],
    required this.kind,
  });

  final String id;
  final String name;
  final List<String> aliases;
  final PlaceKind kind;

  factory Place.fromJson(Map<String, dynamic> json) => Place(
    id: json['id'] as String,
    name: json['name'] as String,
    aliases: [for (final a in (json['aliases'] as List? ?? const [])) a as String],
    kind: PlaceKind.values.byName(json['kind'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'aliases': aliases,
    'kind': kind.name,
  };
}

class Corridor {
  const Corridor({
    required this.id,
    required this.from,
    required this.to,
    required this.steps,
    required this.heading,
  });

  final String id;
  final String from;
  final String to;
  final int steps;

  /// Degrees, counter-clockwise, relative to the heading at the start of the walk.
  final double heading;

  factory Corridor.fromJson(Map<String, dynamic> json) => Corridor(
    id: json['id'] as String,
    from: json['from'] as String,
    to: json['to'] as String,
    steps: (json['steps'] as num).toInt(),
    heading: (json['heading'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'from': from,
    'to': to,
    'steps': steps,
    'heading': heading,
  };
}

class MapGraph {
  const MapGraph({
    this.version = 1,
    required this.name,
    required this.start,
    required this.places,
    required this.corridors,
  });

  final int version;
  final String name;

  /// The place ID where the recorded walk began.
  final String start;
  final List<Place> places;
  final List<Corridor> corridors;

  factory MapGraph.fromJson(Map<String, dynamic> json) => MapGraph(
    version: (json['version'] as num).toInt(),
    name: json['name'] as String,
    start: json['start'] as String,
    places: [
      for (final p in json['places'] as List) Place.fromJson(p as Map<String, dynamic>),
    ],
    corridors: [
      for (final c in json['corridors'] as List)
        Corridor.fromJson(c as Map<String, dynamic>),
    ],
  );

  Map<String, dynamic> toJson() => {
    'version': version,
    'name': name,
    'start': start,
    'places': [for (final p in places) p.toJson()],
    'corridors': [for (final c in corridors) c.toJson()],
  };
}

// ---------------------------------------------------------------------------
// Events and readings
// ---------------------------------------------------------------------------

class StepEvent {
  const StepEvent(this.t);

  /// Milliseconds since the walk started.
  final int t;
}

class TurnEvent {
  const TurnEvent(this.t, this.angle);

  final int t;

  /// Total angle of the completed turn in degrees. Positive is left.
  final double angle;
}

class SignReading {
  const SignReading({required this.t, required this.text, required this.reader});

  final int t;
  final String text;
  final ReaderKind reader;
}

class PlaceMatch {
  const PlaceMatch(this.placeId, this.score);

  final String placeId;

  /// 0 to 1.
  final double score;
}

// ---------------------------------------------------------------------------
// Routes, position, instructions
// ---------------------------------------------------------------------------

class Leg {
  const Leg({
    required this.corridorId,
    required this.reversed,
    required this.heading,
    required this.steps,
  });

  final String corridorId;

  /// True when the corridor is walked from `to` to `from`.
  final bool reversed;

  /// The heading actually walked (already reversed when [reversed]).
  final double heading;
  final int steps;
}

class RoutePlan {
  const RoutePlan({required this.legs, required this.totalSteps, required this.toId});

  final List<Leg> legs;
  final int totalSteps;
  final String toId;
}

class Position {
  const Position({
    required this.legIndex,
    required this.stepsAlong,
    required this.anchoredBy,
    this.offRoute = false,
    this.needsReplan = false,
  });

  final int legIndex;
  final int stepsAlong;
  final AnchorSource anchoredBy;
  final bool offRoute;

  /// Set when an anchor lands on a place that isn't on the current route.
  final bool needsReplan;
}

class Instruction {
  const Instruction({
    required this.kind,
    this.steps,
    this.placeName,
    required this.text,
  });

  final InstructionKind kind;
  final int? steps;
  final String? placeName;

  /// The English sentence to show and speak (see docs/CONTRACTS.md).
  final String text;
}

// ---------------------------------------------------------------------------
// Interfaces (one owner each; see docs/CONTRACTS.md)
// ---------------------------------------------------------------------------

/// Owner: Ifzal. Dijkstra on steps; corridors usable both ways.
abstract interface class RoutePlanner {
  RoutePlan plan(MapGraph map, String fromId, String toId);
}

/// Owner: Ifzal. Never matches junctions; numbers must match; `null` below
/// `matchThreshold`.
abstract interface class PlaceMatcher {
  PlaceMatch? match(String text, MapGraph map);
}

/// Owner: Ifzal. Implementations take the map in their constructor:
/// `Tracker(MapGraph map)`.
abstract interface class Tracker {
  void setRoute(RoutePlan r);
  Position onStep(StepEvent e);
  Position onTurn(TurnEvent e);
  Position anchor(String placeId);
  Position tapHere(String placeId);

  /// The app turns this on while the sign-scan screen is open.
  void pauseTurns(bool on);
}

/// Owner: Ifzal.
abstract interface class Guide {
  Instruction next(RoutePlan r, Position p);
}

/// Owner: Teammate 2. Peaks in `accel`; used only when there's no hardware step
/// detector. Feed every motion sample; returns a step when one is detected.
abstract interface class StepDetector {
  StepEvent? onMotion(int t, double accel);
}

/// Owner: Teammate 2. Feed every motion sample; returns a turn once it settles.
abstract interface class TurnDetector {
  TurnEvent? onMotion(int t, double yawRate);
}

/// Temporary node ID that [MapBuilder.snapshot] uses for the walker's position.
const String hereId = '_here';

/// Owner: Teammate 2. Each turn creates a junction; each place splits the current
/// corridor.
abstract interface class MapBuilder {
  void start(String placeName);
  void onStep(StepEvent e);
  void onTurn(TurnEvent e);
  void addPlace(String name, List<String> aliases);

  /// The map so far, plus the open corridor ending at a temporary junction
  /// [hereId] (D19). The record screen draws [hereId] as the moving dot.
  MapGraph snapshot();
  MapGraph finish();
}

/// Owner: Teammate 2. [events] emits [StepEvent] and [TurnEvent] objects.
abstract interface class SensingSource {
  Stream<Object> events();
  Future<void> startTrace(Map<String, Object?> meta);
  Future<void> stopTrace();
  void mark(String note);
}

/// Owner: Teammate 3 (ML Kit) / Ifzal (Gemma, stretch).
abstract interface class SignReader {
  Future<SignReading?> read(String imagePath);
}

/// Owner: Ifzal. Fuzzy match first, Gemma fallback, always validated.
abstract interface class DestinationResolver {
  Future<PlaceMatch?> resolve(String utterance, MapGraph map);
}

/// Owner: Teammate 3.
abstract interface class Speaker {
  Future<void> speak(Instruction i);
  Future<void> vibrate(InstructionKind k);
}
