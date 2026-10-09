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

`assets/maps/demo_route.json` uses the 8 places from `docs/DEMO.md`. In version 1, **a
map comes from one walk**; merging several walks is a stretch goal, because each walk
has its own heading frame.

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
A trace file (`traces/<date>-<walker>-<route>.jsonl`) holds everything, starting with a
`meta` line:

```json
{"type": "meta", "map": "demo_route", "from": "entrance", "to": "platform_2", "walker": "T2", "stepSource": "detector"}
{"type": "motion", "t": 1540, "yawRate": 34.2, "accel": 10.9}
{"type": "step", "t": 1532}
{"type": "mark", "t": 9900, "note": "turned left"}
{"type": "scan", "t": 15000, "on": true}
{"type": "sign", "t": 15800, "text": "PLATFORM 2 / प्लेटफॉर्म 2", "reader": "mlkit"}
{"type": "scan", "t": 16500, "on": false}
{"type": "mark", "t": 30000, "note": "arrived"}
```

`mark` lines are the tester's ground truth.

## Dart shapes

| Shape | Fields |
| --- | --- |
| `Place` | `id`, `name`, `aliases` (list), `kind` (start / junction / place) |
| `Corridor` | `id`, `from`, `to`, `steps` (int), `heading` (double) |
| `MapGraph` | `version`, `name`, `start`, `places`, `corridors`; `fromJson`, `toJson` |
| `StepEvent` | `t` |
| `TurnEvent` | `t`, `angle` (double, total angle of the completed turn) |
| `SignReading` | `t`, `text`, `reader` (mlkit / gemma) |
| `PlaceMatch` | `placeId`, `score` (0–1) |
| `Leg` | `corridorId`, `reversed`, `heading`, `steps` |
| `RoutePlan` | ordered `legs`, `totalSteps`, `toId` |
| `Position` | `legIndex`, `stepsAlong`, `anchoredBy` (start / turn / sign / tap), `offRoute` (bool), `needsReplan` (bool) |
| `Instruction` | `kind` (straight, turnLeft, turnRight, turnAround, arrive, offRoute, rescan), `steps` (int?), `placeName` (String?), `text` |

## Interfaces (one owner each)

| Interface | Methods | Owner |
| --- | --- | --- |
| `RoutePlanner` | `RoutePlan plan(MapGraph map, String fromId, String toId)`: Dijkstra on steps, corridors usable both ways | Ifzal |
| `PlaceMatcher` | `PlaceMatch? match(String text, MapGraph map)` (rules below) | Ifzal |
| `Tracker` | constructor `Tracker(MapGraph map)`; `setRoute(RoutePlan r)`; `Position onStep(StepEvent e)`; `Position onTurn(TurnEvent e)`; `Position anchor(String placeId)`; `Position tapHere(String placeId)`; `pauseTurns(bool on)` | Ifzal |
| `Guide` | `Instruction next(RoutePlan r, Position p)` | Ifzal |
| `StepDetector` | pure Dart; peaks in `accel`, used only when there's no hardware detector | Teammate 2 |
| `TurnDetector` | pure Dart; `motion` samples to `TurnEvent` (rules below) | Teammate 2 |
| `MapBuilder` | `start(placeName)`, `onStep`, `onTurn`, `addPlace(name, aliases)`, `MapGraph finish()`. Each turn creates a junction, each place splits the current corridor. | Teammate 2 |
| `SensingSource` | `Stream<Object> events()` (StepEvent or TurnEvent), `startTrace(meta)`, `stopTrace()`, `mark(note)` | Teammate 2 |
| `SignReader` | `Future<SignReading?> read(String imagePath)`; `MlKitSignReader` is required, `GemmaSignReader` is a stretch goal | Teammate 3 / Ifzal |
| `DestinationResolver` | `Future<PlaceMatch?> resolve(String utterance, MapGraph map)`: fuzzy match first, Gemma fallback, always validated | Ifzal |
| `Speaker` | `speak(Instruction i)`, `vibrate(InstructionKind k)` | Teammate 3 |

Every interface has a `Fake...` version committed in hour 0, so nobody waits.

## Rules

**TurnDetector**

1. Accumulate `yawRate × dt` while `|yawRate|` > `turnRateMin`.
2. When the rate stays below it for `turnSettleMs`, check the total. If
   `|total|` ≥ `turnMinAngle`, emit one `TurnEvent` with the total angle (so a real turn
   reports about 90, not 60).
3. Reset the total either way.

**Tracker**

- Each step moves position along the current leg. Turns are ignored while
  `pauseTurns(true)`; the app sets this while the sign-scan screen is open.
- A turn in the expected direction near the end of a leg (last `snapZone` fraction or
  within `snapSteps`) snaps position to the start of the next leg.
- A turn in the wrong direction sets `offRoute`.
- Walking more than `overwalk` past a leg's length gives a "may have passed the turn"
  `rescan` instruction.
- `anchor(placeId)` moves position to that place. If the place isn't on the current
  route, it sets `needsReplan`; the app then plans again from that place.

**Guide**

- Take the turn between the current leg and the next. If `|turn|` < `straightTolerance`,
  just continue.
- If `|turn|` > `turnAroundAngle`, say "turn around".
- When the steps left on a leg are at most `turnNowSteps`, say "turn left now" or
  "turn right now".

**PlaceMatcher**

1. Lowercase. Replace anything that isn't a letter or digit in any script with a space,
   using `RegExp(r'[^\p{L}\p{N}]+', unicode: true)`, so Devanagari survives.
2. Never match junctions.
3. **If the text contains a number, the candidate must contain the same number**:
   "Platform 3" never matches "Platform 2".
4. Score with token overlap plus normalised Levenshtein over names and aliases. Return
   `null` below `matchThreshold`.

## Tuning (`lib/core/tuning.dart`, starting guesses to tune with traces)

| Constant | Start | Meaning |
| --- | --- | --- |
| `turnRateMin` | 25 | deg/s above which the phone is turning |
| `turnSettleMs` | 500 | ms the rate must stay below `turnRateMin` to finish a turn |
| `turnMinAngle` | 60 | Minimum total degrees to count as a turn |
| `straightTolerance` | 30 | Leg-to-leg changes smaller than this are "straight on" |
| `turnAroundAngle` | 150 | Changes larger than this are "turn around" |
| `turnNowSteps` | 3 | Say "turn now" this many steps before the end of a leg |
| `snapZone` | 0.4 | A turn snaps in the last 40% of a leg… |
| `snapSteps` | 8 | …or within this many steps of its end |
| `overwalk` | 0.3 | 30% past a leg's length triggers a rescan prompt |
| `matchThreshold` | 0.8 | Minimum fuzzy score for a place match |
| `accelPeakThreshold` | 11.5 | m/s² peak needed to count a step (fallback only) |
| `accelPeakMinGapMs` | 300 | Minimum ms between fallback step peaks |

## Instruction text (English; Hindi strings are a stretch goal)

| Kind | Text |
| --- | --- |
| straight | "Walk straight, about {steps} steps." |
| turnLeft / turnRight | "In about {steps} steps, turn left." Then "Turn left now." |
| turnAround | "Turn around." |
| arrive | "{placeName} is here." |
| offRoute | "That turn wasn't on the route. Scan a nearby sign to re-locate." |
| rescan | "You may have passed the turn. Point the camera at a sign." |

Vibration: left = two short pulses, right = one long pulse, arrive = three short pulses.
