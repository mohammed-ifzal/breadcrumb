/// The shapes and interfaces every module agrees on.
///
/// This file mirrors `docs/CONTRACTS.md`. Only the captain changes it, together with
/// that document. Pure Dart: no Flutter, no plugins, no I/O.
library;

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum PlaceKind { start, junction, place }

/// How a corridor is walked (D24). Anything but [walk] is a floor transition.
enum CorridorKind { walk, stairs, escalator, lift }

/// What last fixed the position. [floor]: a floor change completed a
/// transition leg (D24).
enum AnchorSource { start, turn, sign, tap, floor }

enum InstructionKind {
  straight,
  turnLeft,
  turnRight,
  turnAround,
  arrive,
  offRoute,
  rescan,

  /// Take the stairs, escalator or lift to another floor (D24).
  changeFloor,

  /// At the end of the final leg without enough evidence of arrival: "{place}
  /// should be right here — tap I'm here to confirm" (D29).
  arrivingConfirm,

  /// Past the final leg plus the overwalk: "You may have passed {place}" (D29).
  maybePassed,

  /// Position confidence dropped below `confidenceAskBelow`: "Are you at {next
  /// place}?", once per leg (D29).
  confirmPlace,
}

/// What the walker is doing, from the motion sensors (D29). [handling]: the phone
/// is being moved in the hand (picked up, put in a pocket, looked at), so yaw is
/// not a body turn.
enum MotionState { walking, still, handling }

/// Where the phone is carried (D29).
enum Placement { hand, pocket, unknown }

/// What the phone can run (D29), from its total RAM: [full] runs Gemma, [basic]
/// uses fuzzy matching and tap-a-place only.
enum DeviceTier { full, basic }

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
    this.floor = 0,
    this.x,
    this.y,
  });

  final String id;
  final String name;
  final List<String> aliases;
  final PlaceKind kind;

  /// The floor this node is on; 0 when the map has one floor (D24).
  final int floor;

  /// Optional display coordinates in steps (+y forward, +x right). D34.
  /// Complete finite pairs override legacy layout; not used for routing.
  final double? x, y;

  factory Place.fromJson(Map<String, dynamic> json) => Place(
    id: json['id'] as String,
    name: json['name'] as String,
    aliases: [for (final a in (json['aliases'] as List? ?? const [])) a as String],
    kind: PlaceKind.values.byName(json['kind'] as String),
    floor: (json['floor'] as num? ?? 0).toInt(),
    x: json['x'] == null ? null : (json['x'] as num).toDouble(),
    y: json['y'] == null ? null : (json['y'] as num).toDouble(),
  );

  /// Leaves out `floor` when it is 0, so one-floor maps are written as before.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'aliases': aliases,
    'kind': kind.name,
    if (floor != 0) 'floor': floor,
    if (x != null) 'x': x,
    if (y != null) 'y': y,
  };
}

class Corridor {
  const Corridor({
    required this.id,
    required this.from,
    required this.to,
    required this.steps,
    required this.heading,
    this.kind = CorridorKind.walk,
    this.floorDelta = 0,
  });

  final String id;
  final String from;
  final String to;
  final int steps;

  /// Degrees, counter-clockwise, relative to the heading at the start of the walk.
  final double heading;

  /// [CorridorKind.walk] unless this corridor changes floor (D24).
  final CorridorKind kind;

  /// Floors gained going from `from` to `to`: `to.floor - from.floor`.
  final int floorDelta;

  bool get isTransition => kind != CorridorKind.walk;

  factory Corridor.fromJson(Map<String, dynamic> json) => Corridor(
    id: json['id'] as String,
    from: json['from'] as String,
    to: json['to'] as String,
    steps: (json['steps'] as num).toInt(),
    heading: (json['heading'] as num).toDouble(),
    kind: CorridorKind.values.byName(json['kind'] as String? ?? 'walk'),
    floorDelta: (json['floorDelta'] as num? ?? 0).toInt(),
  );

  /// Leaves out `kind` and `floorDelta` at their defaults, so one-floor maps are
  /// written as before.
  Map<String, dynamic> toJson() => {
    'id': id,
    'from': from,
    'to': to,
    'steps': steps,
    'heading': heading,
    if (kind != CorridorKind.walk) 'kind': kind.name,
    if (floorDelta != 0) 'floorDelta': floorDelta,
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

/// The walker's motion state changed (D29).
class MotionStateEvent {
  const MotionStateEvent(this.state, this.tMs);

  final MotionState state;

  /// Milliseconds since the walk started.
  final int tMs;
}

/// Where the phone is carried changed (D29).
class PlacementEvent {
  const PlacementEvent(this.placement, this.tMs);

  final Placement placement;

  /// Milliseconds since the walk started.
  final int tMs;
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
    this.kind = CorridorKind.walk,
    this.floorDelta = 0,
  });

  final String corridorId;

  /// True when the corridor is walked from `to` to `from`.
  final bool reversed;

  /// The heading actually walked (already reversed when [reversed]).
  final double heading;
  final int steps;

  /// The corridor's kind (D24).
  final CorridorKind kind;

  /// Floors gained on this leg, as walked (already negated when [reversed]).
  final int floorDelta;

  /// A stairs, escalator or lift leg: the Tracker ignores steps and turns on it.
  bool get isTransition => kind != CorridorKind.walk;
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
    this.orienting = false,
    this.facing,
    this.confidence = 1.0,
    this.unconfirmedArrival = false,
    this.stepsOffRoute = 0,
    this.awayHeading,
    this.backOnRoute = false,
  });

  final int legIndex;
  final int stepsAlong;
  final AnchorSource anchoredBy;
  final bool offRoute;

  /// Set when an anchor lands on a place that isn't on the current route.
  final bool needsReplan;

  /// True from the start of a route until the first step (D27).
  final bool orienting;

  /// While [orienting]: the direction the walker is assumed to face, in map
  /// degrees, or null when unknown (D27). While [offRoute]: the running facing
  /// from every turn since leaving the route, starting at the leg's heading (D31).
  final double? facing;

  /// How sure the Tracker is of [stepsAlong], 0 to 1 (D29). Decays every step,
  /// recovers on a snapped corner, an "I'm here" tap or arrival. Always 1.0 when
  /// `useConfidence` is off.
  final double confidence;

  /// At or past the end of the route, but the arrival guard is not met (D29):
  /// the final run was reached by an overwalk, not a turn or an anchor, or too
  /// few of its steps were walked. The Guide asks for "I'm here" instead of
  /// announcing arrival. Always false when `useArrivalGuard` is off.
  final bool unconfirmedArrival;

  /// While [offRoute]: net steps walked away from the path since leaving it;
  /// steps walked back the other way count down (D31). 0 on route.
  final int stepsOffRoute;

  /// While [offRoute] and after a step: the heading walked away from the path
  /// on, or null (D31).
  final double? awayHeading;

  /// True on the position where the facing came back to the leg's heading and
  /// the walker rejoined the same leg; the next event clears it (D31).
  final bool backOnRoute;
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

  /// [delta] floors moved: +1 up, -1 down (D24). Completes the next transition
  /// leg once the floors moved reach its `floorDelta`. Comes from one tap in the
  /// app (no barometer, like the iQOO 15) or from a FloorDetector.
  Position onFloorChange(int delta);

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

  /// Motion state changes: walking, still, handling (D29).
  Stream<MotionStateEvent> motionStates();

  /// Phone placement changes: hand, pocket, unknown (D29).
  Stream<PlacementEvent> placements();

  /// Total device RAM in MB, for [DeviceTier] (D29); 0 when unknown.
  Future<int> totalRamMb();
}

/// Owner: Ifzal. Sits between the [SensingSource] and its consumers (Tracker,
/// MapBuilder) and passes on only turns that walking confirms (D29). Feed it
/// every step, raw turn and motion state; listen to [confirmed].
abstract interface class TurnConfirmer {
  void onStep(StepEvent e);
  void onTurn(TurnEvent e);
  void onMotionState(MotionStateEvent e);

  /// Turns confirmed by `turnConfirmSteps` steps, with their net angle.
  Stream<TurnEvent> get confirmed;
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
