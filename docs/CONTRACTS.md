# Contracts: the shapes every module agrees on

Owner: Ifzal. In hour 0, Claude Code turns this file into `lib/core/contracts.dart` and
`lib/core/tuning.dart`. Nobody else changes a shape. Ask the captain, who updates this
file and the Dart files together.

Names avoid Flutter's own `Route` and `Router` classes: use **`RoutePlan`** and
**`RoutePlanner`**.

## Conventions

- **Time:** milliseconds since the walk started (`t`, int).
- **Steps:** integers. Distances are in steps, not metres.
- **Heading:** a double in degrees, 0 to 360, relative to the heading at the start of
  the recorded walk. **Heading grows counter-clockwise (to the left)**, seen from above.
- **Turn angle:** a double in degrees. **Positive = left**, negative = right.
  - After a turn, new heading = (heading + angle) mod 360.
  - The turn needed between two legs = (next heading − current heading), normalised to
    (−180, 180]. Above 0 is a left turn.
- **Reversed corridor:** walking a corridor from `to` to `from` uses
  heading = (heading + 180) mod 360.
- **Parsing:** read every number with `(json['x'] as num).toDouble()` or `.toInt()`,
  never `as int`.
- **IDs:** short lowercase strings: `entrance`, `j1`, `platform_2`.

## MapGraph (JSON file, `assets/maps/*.json` and app storage `maps/`)

```json
{
  "version": 1,
  "name": "Example",
  "start": "entrance",
  "places": [
    {"id": "entrance", "name": "Entrance", "aliases": ["main gate"], "kind": "start"},
    {"id": "j1", "name": "Junction 1", "aliases": [], "kind": "junction"},
    {"id": "lift", "name": "Lift", "aliases": ["elevator"], "kind": "place"},
    {"id": "j2", "name": "Junction 2", "aliases": [], "kind": "junction"},
    {"id": "platform_2", "name": "Platform 2", "aliases": ["platform two", "pf 2"], "kind": "place"}
  ],
  "corridors": [
    {"id": "c1", "from": "entrance", "to": "j1", "steps": 24, "heading": 0},
    {"id": "c2", "from": "j1", "to": "lift", "steps": 14, "heading": 90},
    {"id": "c3", "from": "lift", "to": "j2", "steps": 10, "heading": 90},
    {"id": "c4", "from": "j2", "to": "platform_2", "steps": 18, "heading": 0}
  ]
}
```

Reading the example: c1 → c2 is a **left** turn (0 → 90). c2 → c3 is straight on. c3 →
c4 is a **right** turn (90 → 0). Walking back from Platform 2, c4 reversed has heading
180.

Maps come from record mode (D15). Tests build maps in code. In version 1, **a
map comes from one walk**; merging several walks is a stretch goal, because each walk
has its own heading frame.

**Where the map lives (D22).** When a recording is finished, the record screen writes
`MapBuilder.finish().toJson()` to `<app documents>/maps/latest.json` (path_provider's
application documents directory), replacing the previous file. Navigate loads
`maps/latest.json` if it exists and parses; otherwise it loads the bundled demo map from
`assets/maps/`. Navigate re-reads the file every time it opens, so a map saved after app
start is used without a restart; an unchanged file keeps the "You are at" choice. Only
the app layer does this file I/O; `lib/core/` stays pure.

**End of walk and the start place (D23).** When the walker taps Stop, the record screen
calls `addPlace('End of walk', [])` and then `finish()`, so every recorded map ends at a
place. It skips the call if a place was marked with no steps after it (no zero-step
corridor). Navigate's "You are at" defaults to the loaded map's last place: the last node
with `kind: place` in `nodes` order (walk order). A selector lists every place so the user
can change it.

**Floors (D24).** All optional, so maps without them load unchanged and one-floor maps
are written without them:

- A place may have `"floor": 1` (int, default 0). Junctions have floors too.
- A corridor may have `"kind"`: `walk` (default), `stairs`, `escalator` or `lift`, and
  `"floorDelta"` (int, default 0) = `to`'s floor − `from`'s floor. Anything but `walk`
  is a **transition**. `decodeMap` throws `FormatException` when `floorDelta` doesn't
  match the floors, or when a `walk` corridor changes floor.

```json
{"id": "c2", "from": "stairs_foot", "to": "stairs_top", "steps": 12, "heading": 0,
 "kind": "stairs", "floorDelta": 1}
```

**The iQOO 15 has no barometer**, so on this phone floor changes are manual: one tap
completes the transition ("I am here" on a transition leg taps the node at its top, or
the app calls `onFloorChange` with the leg's `floorDelta`). Where a barometer exists, a
`FloorDetector` (not built yet) would call `onFloorChange` automatically.

## Sensor stream and trace files

Kotlin (EventChannel `breadcrumb/sensing`, one broadcast stream, events sent on the main
thread) emits only raw data:

```json
{"type": "step", "t": 1532}
{"type": "motion", "t": 1540, "yawRate": 34.2, "accel": 10.9}
```

- `step` comes only from the hardware step detector. If the phone has none, Kotlin sends
  `{"type": "info", "stepDetector": false}` once.
- `yawRate` is in **degrees per second** (converted from the gyroscope's rad/s). It is
  the gyroscope vector dotted with the unit gravity vector, so it is the rotation about
  vertical, however the phone is held. Positive = counter-clockwise = left.
- `accel` is the acceleration magnitude in m/s². Samples arrive at about 50 Hz.

Dart detectors in `lib/sensing/` (pure Dart) turn this into `StepEvent` and `TurnEvent`.
A trace file (`traces/<date>-<walker>-<map>-<micros>.jsonl`, D19) holds everything, starting with a
`meta` line:

```json
{"type": "meta", "map": "table_loop", "from": "p0", "to": "p2", "walker": "T2", "stepSource": "hardware"}
{"type": "motion", "t": 1540, "yawRate": 34.2, "accel": 10.9}
{"type": "step", "t": 1532}
{"type": "mark", "t": 9900, "note": "turned left"}
{"type": "scan", "t": 15000, "on": true}
{"type": "sign", "t": 15800, "text": "PLATFORM 2 / प्लेटफॉर्म 2", "reader": "mlkit"}
{"type": "scan", "t": 16500, "on": false}
{"type": "mark", "t": 30000, "note": "arrived"}
```

`mark` lines are the tester's ground truth. `stepSource` is `"hardware"` (the phone's step
detector) or `"accel"` (the Dart `StepDetector` fallback).

## Dart shapes

| Shape | Fields |
| --- | --- |
| `Place` | `id`, `name`, `aliases` (list), `kind` (start / junction / place), `floor` (int, default 0, D24) |
| `Corridor` | `id`, `from`, `to`, `steps` (int), `heading` (double), `kind` (walk / stairs / escalator / lift, default walk), `floorDelta` (int, default 0); `isTransition` = kind isn't walk (D24) |
| `MapGraph` | `version`, `name`, `start`, `places`, `corridors`; `fromJson`, `toJson` |
| `StepEvent` | `t` |
| `TurnEvent` | `t`, `angle` (double, total angle of the completed turn) |
| `MotionStateEvent` | `state` (walking / still / handling), `tMs` (D29) |
| `PlacementEvent` | `placement` (hand / pocket / unknown), `tMs` (D29) |
| `DeviceTier` | enum: full / basic; full when `totalRamMb()` >= `fullTierMinRamMb` (or 0 = unknown) **and** Gemma loads, else basic; basic never loads Gemma (D29, D30, `lib/ai/device_tier.dart` `AiTierGate`) |
| `SignReading` | `t`, `text`, `reader` (mlkit / gemma) |
| `PlaceMatch` | `placeId`, `score` (0–1) |
| `Leg` | `corridorId`, `reversed`, `heading`, `steps`, `kind` (default walk), `floorDelta` (as walked: negated when reversed; default 0), `isTransition` (D24) |
| `RoutePlan` | ordered `legs`, `totalSteps`, `toId` |
| `Position` | `legIndex`, `stepsAlong`, `anchoredBy` (start / turn / sign / tap / floor), `offRoute` (bool), `needsReplan` (bool), `orienting` (bool, default false), `facing` (double?, assumed facing while orienting, null = unknown) (D27), `confidence` (double 0-1, default 1.0, D29), `unconfirmedArrival` (bool, default false: at or past the destination without the arrival guard met, D29), `stepsOffRoute` (int, default 0), `awayHeading` (double?), `backOnRoute` (bool, default false) (D31); `facing` is also the running facing while `offRoute` (D31) |
| `Instruction` | `kind` (straight, turnLeft, turnRight, turnAround, arrive, offRoute, rescan, changeFloor, arrivingConfirm, maybePassed, confirmPlace (D29)), `steps` (int?), `placeName` (String?), `text` |

## Interfaces (one owner each)

| Interface | Methods | Owner |
| --- | --- | --- |
| `RoutePlanner` | `RoutePlan plan(MapGraph map, String fromId, String toId)`: Dijkstra on steps, corridors usable both ways; a transition costs its steps + `floorChangeCostSteps`; `totalSteps` counts steps only (D24) | Ifzal |
| `PlaceMatcher` | `PlaceMatch? match(String text, MapGraph map)` (rules below) | Ifzal |
| `Tracker` | constructor `Tracker(MapGraph map)`; `setRoute(RoutePlan r)`; `Position onStep(StepEvent e)`; `Position onTurn(TurnEvent e)`; `Position anchor(String placeId)`; `Position tapHere(String placeId)`; `Position onFloorChange(int delta)` (D24); `pauseTurns(bool on)` | Ifzal |
| `Guide` | `Instruction next(RoutePlan r, Position p)` | Ifzal |
| `StepDetector` | pure Dart; peaks in `accel`, used only when there's no hardware detector | Teammate 2 |
| `TurnDetector` | pure Dart; `motion` samples to `TurnEvent` (rules below) | Teammate 2 |
| `MapBuilder` | `start(placeName)`, `onStep`, `onTurn`, `addPlace(name, aliases)`, `MapGraph snapshot()`, `MapGraph finish()`. Each turn creates a junction, each place splits the current corridor. `snapshot()` (D19) returns the map so far plus the open corridor ending at a temporary node `"_here"` (kind junction); pure Dart. The record screen calls it after every step, turn and mark and pushes it to `TrailView` via `ValueNotifier<MapGraph>`; `TrailView` draws `"_here"` as the moving dot. | Teammate 2 |
| `SensingSource` | `Stream<Object> events()` (StepEvent or TurnEvent), `startTrace(meta)`, `stopTrace()`, `mark(note)`, `Stream<MotionStateEvent> motionStates()`, `Stream<PlacementEvent> placements()`, `Future<int> totalRamMb()` (0 = unknown) (D29) | Teammate 2 |
| `TurnConfirmer` | `onStep(StepEvent)`, `onTurn(TurnEvent)`, `onMotionState(MotionStateEvent)`, `Stream<TurnEvent> confirmed` (rules below, D29) | Ifzal |
| `SignReader` | `Future<SignReading?> read(String imagePath)`; `MlKitSignReader` is required, `GemmaSignReader` is a stretch goal | Teammate 3 / Ifzal |
| `DestinationResolver` | `Future<PlaceMatch?> resolve(String utterance, MapGraph map)`: fuzzy match first, Gemma fallback, always validated. Basic tier: `BasicDestinationResolver`, PlaceMatcher over names + aliases only; the AI chip says "Basic matching" (D30) | Ifzal |
| `AliasSuggester` (D30, `lib/ai/alias_suggester.dart`) | `Future<List<String>> suggest(String placeName, Iterable<Place> otherPlaces)`: one Gemma call, returns at most `maxAliases` validated aliases (lowercase, 1 to `maxAliasWords` words, filler trimmed, no duplicates, none that belongs to another place), `[]` on the basic tier, an error or `aliasSuggestTimeoutMs`. `MapGraph applyAliases(MapGraph map, Map<String, List<String>> aliasesById)` merges them into `Place.aliases`, re-validated against the whole map | Ifzal |
| `Speaker` | `speak(Instruction i)`, `vibrate(InstructionKind k)` | Teammate 3 |

Every interface has a `Fake...` version committed in hour 0, so nobody waits.

## Rules

**TurnDetector**

1. Accumulate `yawRate × dt` while `|yawRate|` > `turnRateMin`.
2. When the rate stays below it for `turnSettleMs`, check the total. If
   `|total|` ≥ `turnMinAngle`, emit one `TurnEvent` with the total angle (so a real turn
   reports about 90, not 60).
3. Reset the total either way.

**TurnConfirmer (D29, `useTurnConfirmer`)**

1. A raw turn is a candidate. It is passed on only once `turnConfirmSteps` steps follow
   it within `turnConfirmWindowMs`.
2. Its angle is the net of every candidate since the last confirmed walking heading, so
   a sidestep and back (+90, -90) nets ~0 and is dropped (< `turnMinAngle`).
3. Candidates that arrive during `MotionState.handling`, or with no following steps in
   the window, are dropped. Handling while a candidate waits drops it too.
   Candidates with no step between them are a burst (looking around on the spot): the
   burst is never confirmed, and a candidate after a step replaces it (D32).
4. It sits between the `SensingSource` and both the Tracker and the MapBuilder.

**Tracker**

- Each step moves position along the current leg. Turns are ignored while
  `pauseTurns(true)`; the app sets this while the sign-scan screen is open.
- **Orientation phase (D27).** From `setRoute` until the first step, `Position.orienting`
  is true and turns are not route turns: they only add their angle to
  `Position.facing`. The facing starts as the heading of the corridor the walker arrived
  on when the route starts at the node where the recording ended (the last corridor's
  `to`); otherwise it is null (unknown) and turns leave it unknown. `anchor` / `tapHere`
  don't end the phase (Navigate anchors at the start right after `setRoute`).
- A turn in the expected direction near the end of a leg (last `snapZone` fraction or
  within `snapSteps`) snaps position to the start of the next leg.
- A turn in the wrong direction sets `offRoute`.
- **A corner is passed only by a turn or an overwalk (D27).** Steps keep counting past
  the counted corner; walking more than `overwalk` × the run past it with no turn moves
  position to the start of the next leg (`stepsAlong` 0, so the real turn, if it comes
  late, is absorbed by the `lateTurnSteps` rule). Not while off route.
- **Auto-recover (D27).** While off route, a turn in the direction the next turning
  point needs, within 2 × `snapSteps` of it (before or after), snaps position to the
  start of the leg after it and clears `offRoute`. Other turns are ignored.
- **Rejoin (D31).** Leaving the route starts a running facing (the leg's heading turned by
  that turn); every off-route turn updates it. Off-route steps count net steps away
  (`stepsOffRoute`: along `awayHeading` up, the opposite way down, sideways not). Facing
  the current leg within `straightTolerance` at most `walkBackMinSteps` away rejoins the
  same leg at the step count it was left at, with `backOnRoute` on that one position.
  This is checked before auto-recover; a turn-around never auto-recovers onto a left or
  right corner.
- Turns after arriving (last leg, its steps done) are ignored (D26).
- **Confidence (D29, `useConfidence`).** x `confidenceDecayPerStep` on every counted
  step; up to `confidenceCornerReset` on a snapped corner (never lowered); 1.0 on
  `tapHere`, `anchor`, a completed floor change and arrival.
- **Arrival guard (D29, `useArrivalGuard`).** Arrival needs the final run (the legs
  after the last turning point) to be reached with evidence (a turn snap, an anchor, a
  floor change or the route start; not an overwalk) and at least `arrivalMinFraction` of
  its remaining steps walked since. At or past the end without that, the position sets
  `unconfirmedArrival`. `tapHere` / `anchor` on the destination always arrive.
- A turn within `lateTurnSteps` after a node the position already moved past (by
  `tapHere`, `anchor` or a turn snap), in the direction that node needs, is that node's
  turn: the position stays and it is not `offRoute` (D26).
- `anchor(placeId)` moves position to that place. If the place isn't on the current
  route, it sets `needsReplan`; the app then plans again from that place.
- **Transitions (D24).** A stairs, escalator or lift leg always ends a straight run.
  Walking to the end of the leg before it moves position onto it (`stepsAlong` 0); a
  turn near its foot in the right direction snaps onto it, like any turn. On a
  transition leg, steps and turns are ignored. `onFloorChange(delta)` (+1 up, −1 down)
  counts floors towards the next transition (the current leg or the first one after
  it); when they reach its `floorDelta`, position moves to the start of the leg after it
  (`anchoredBy: floor`), or to arrival if it is the last leg. A floor change the other
  way, or with no transition ahead, is ignored. `tapHere` / `anchor` on the node at the
  top also completes it. A 0-step transition counts as 1 step long, so standing at its
  foot is never arrival.

**Guide**

- Take the turn between the current leg and the next. If `|turn|` < `straightTolerance`,
  just continue.
- If `|turn|` > `turnAroundAngle`, say "turn around".
- When the steps left are at most `turnNowSteps`, say "Get ready to turn left/right.";
  when they reach 0, "Turn left/right at the corner." (D27; was "turn left now").
- **Orienting (D27).** While `Position.orienting`, before the normal instruction: facing
  unknown → "Face {next place} and start walking." (`straight`, no steps; the next place is
  the first non-junction node ahead); first leg about 180° from the facing (more than
  `turnAroundAngle`) → "Turn around, then walk straight." (`turnAround`); at least
  `straightTolerance` off → "Turn left/right, then walk straight." (`turnLeft` /
  `turnRight`, no steps). Within `straightTolerance` → the normal instruction.
- **Confirm place (D29).** When `Position.confidence` < `confidenceAskBelow`: "Are you
  at {place}?" (`confirmPlace`), once per leg, about the node at the end of the current
  leg (the one the app's "I'm here" taps); a junction is "the next corner".
- **Arrival guard (D29).** When `Position.unconfirmedArrival`, instead of arrival: "{place}
  should be right here — tap I'm here to confirm" (`arrivingConfirm`); further than
  `overwalk` x the leg past it: "You may have passed {place}" (`maybePassed`).
- **Off route (D31).** From `facing` vs the current leg: about 180° → "Turn around to get
  back on the path." (`turnAround`); otherwise "Turn left/right to face the path."
  (`turnLeft` / `turnRight`, no steps). More than `walkBackMinSteps` away: "Walk back about
  N steps, then turn left/right." (`turnAround`; `straight` once facing back). On
  `backOnRoute`: "Back on route. " + the normal instruction.
- Off route with no facing → "Looks like you went off the path. Go back to the last corner or tap I'm
  here." The Guide no longer gives `rescan` (D27); the Scan sign button stays.
- Before a transition, `changeFloor` replaces the turn: "In about {steps} steps, take
  the {kind} {up/down} to Floor {N}.", then "Take the {kind} {up/down} to Floor {N}."
  within `turnNowSteps` and on the transition leg. {N} is the floor of the node at its
  top (D24).

**PlaceMatcher**

1. Lowercase. Replace anything that isn't a letter, combining mark or digit in any
   script with a space, using `RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true)`, so
   Devanagari survives (its vowel signs are `\p{M}`; without it words break apart).
2. Never match junctions.
3. **If the text contains a number, the candidate must contain the same number**:
   "Platform 3" never matches "Platform 2".
4. Score with token overlap plus normalised Levenshtein over names and aliases. Return
   `null` below `matchThreshold`.

**Clarifications** (from the core engine, PR #1)

- **A correct turn before the snap zone is `offRoute`.** The snap zone is measured over
  the straight run up to the next turn, not a single leg.
- **While off route, turns are ignored** until an anchor (`anchor` / `tapHere`), a
  new route (`setRoute`) or a matching turn near the next corner (auto-recover, D27)
  clears `offRoute`.
- **Places mid-corridor are passed through.** A place splits a corridor into two legs
  with the same heading; walking past it is straight on, never a turn.
- **`RoutePlanner.plan` throws `ArgumentError`** for an unknown place ID or when there is
  no route. Callers must catch it.

## Tuning (`lib/core/tuning.dart`, starting guesses to tune with traces)

| Constant | Start | Meaning |
| --- | --- | --- |
| `turnRateMin` | 25 | deg/s above which the phone is turning |
| `turnSettleMs` | 500 | ms the rate must stay below `turnRateMin` to finish a turn |
| `turnMinAngle` | 60 | Minimum total degrees to count as a turn |
| `maxMotionGapMs` | 200 | Motion samples with a bigger gap (ms) reset turn integration |
| `turnSnapDegrees` | 90 | `MapBuilder` rounds each recorded turn angle to the nearest multiple (D25; was 45) |
| `straightTolerance` | 30 | Leg-to-leg changes smaller than this are "straight on" |
| `turnAroundAngle` | 150 | Changes larger than this are "turn around" |
| `turnNowSteps` | 3 | Say "Get ready to turn" this many steps before the corner |
| `snapZone` | 0.5 | A turn snaps in the last half of a leg… (D27; was 0.4) |
| `snapSteps` | 10 | …or within this many steps of its end; off route, 2× this is the auto-recover window (D27; was 8) |
| `lateTurnSteps` | 3 | A turn this many steps after a node the position already moved past is that node's turn (D26) |
| `floorChangeCostSteps` | 20 | Extra route cost of each stairs, escalator or lift corridor (D24) |
| `overwalk` | 0.3 | 30% of a run past its corner with no turn moves on to the next leg (D27; was a rescan prompt) |
| `matchThreshold` | 0.8 | Minimum fuzzy score for a place match |
| `accelPeakThreshold` | 11.5 | m/s² peak needed to count a step (fallback only) |
| `accelPeakMinGapMs` | 300 | Minimum ms between fallback step peaks |
| `gemmaTimeoutMs` | 20000 | Longest wait for Gemma to choose a destination; then `null` |
| `useTurnConfirmer` | false | Flag: TurnConfirmer between sensing and Tracker / MapBuilder (D29) |
| `turnConfirmSteps` | 2 | Steps that must follow a raw turn to confirm it (D29) |
| `turnConfirmWindowMs` | 8000 | ...within this many ms (D29; 4000 missed all 3 turns of the spike walk, which pauses after each turn) |
| `useConfidence` | false | Flag: position confidence and "Are you at...?" (D29) |
| `confidenceDecayPerStep` | 0.98 | Confidence x this per step (D29) |
| `confidenceCornerReset` | 0.9 | Confidence after a snapped corner (D29) |
| `confidenceAskBelow` | 0.5 | Ask "Are you at {place}?" below this (D29) |
| `useArrivalGuard` | false | Flag: arrival guard (D29) |
| `walkBackMinSteps` | 2 | Off route, facing the leg again this close rejoins it; further, "Walk back about N steps" (D31) |
| `arrivalMinFraction` | 0.7 | Fraction of the final leg needed before arrival (D29) |
| `stillAfterMs` | 1500 | No step for this long -> `MotionState.still` (T2, D29) |
| `handlingRotationMin` | 120 | deg/s of non-yaw rotation -> `MotionState.handling` (T2, D29) |
| `fullTierMinRamMb` | 8000 | Total RAM for `DeviceTier.full` (D29) |
| `maxAliases` | 8 | Aliases kept per suggested place (D30) |
| `maxAliasWords` | 3 | Words in one alias (D30) |
| `aliasSuggestTimeoutMs` | 15000 | Wait for Gemma's alias reply (D30) |

## Instruction text (English; Hindi strings are a stretch goal)

| Kind | Text |
| --- | --- |
| straight | "Walk straight, about {steps} steps." |
| turnLeft / turnRight | "In about {steps} steps, turn left." Then "Get ready to turn left." Then "Turn left at the corner." (D27) |
| orienting (D27) | "Turn around, then walk straight." / "Turn left, then walk straight." / "Face {place} and start walking." |
| turnAround | "Turn around." |
| arrive | "{placeName} is here." |
| offRoute | "Looks like you went off the path. Go back to the last corner or tap I'm here." (D27, no facing) |
| off route (D31) | "Turn around to get back on the path." / "Turn left to face the path." / "Walk back about {N} steps, then turn right." |
| back on route (D31) | "Back on route. " + the normal instruction |
| confirmPlace | "Are you at {place}?" / "Are you at the next corner?" (D29) |
| arrivingConfirm | "{place} should be right here — tap I'm here to confirm." (D29) |
| maybePassed | "You may have passed {place}." (D29) |
| rescan | No longer given by the Guide (D27); kept in the enum. |
| changeFloor | "In about {steps} steps, take the stairs up to Floor 1." Then "Take the stairs up to Floor 1." (D24) |

Vibration: left = two short pulses, right = one long pulse, arrive = three short pulses.
