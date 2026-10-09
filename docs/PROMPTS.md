# First prompts for each agent

Copy and paste these. Each one names the files to read, the scope, and a check that
proves it's done, so the agent can loop without you. Start a fresh session for each
prompt, and `/clear` (or open a new chat) when it's done.

## Everyone: the first message of every session

```
Read AGENTS.md, docs/CONTRACTS.md and the newest entries in docs/status/. In 5 lines,
tell me: what we're building, the hard rules that apply to my paths, and the latest
status. Don't change any files yet.
```

---

## Ifzal (Claude Code)

**1. Hour-0 commit** (plan mode, `/model opusplan`)

```
Read AGENTS.md, docs/CONTEXT.md, docs/CONTRACTS.md and docs/SETUP.md. Plan the hour-0
commit exactly as docs/SETUP.md "Hour 0" describes:
- the Flutter project (Android only, minSdk 30, arm64-v8a)
- the shared debug keystore and signing config
- every package, pinned where versions are given
- the ML Kit Devanagari dependency in build.gradle.kts
- the manifest permissions, <queries> entries and native-library entries
- lib/core/contracts.dart and lib/core/tuning.dart generated from docs/CONTRACTS.md
- Fake implementations of every interface
- one folder per owner with a one-line README
- docs/status/ with one file per person
- the CI workflow
Show me the plan. After I approve it, implement it, run flutter analyze and
flutter test, and commit.
```

**2. Core engine**

```
Implement in lib/core/, exactly per docs/CONTRACTS.md and pure Dart only:
- MapGraph with JSON load/save
- RoutePlanner: Dijkstra on steps, corridors usable both ways, reversed heading
  = heading + 180
- PlaceMatcher, following the four rules, with no packages
- Tracker, following the Tracker rules
- Guide, following the Guide rules and instruction text
Write the tests first in test/core/. Build test maps in code: a synthetic walk from
"start" of 12 steps, a left turn, 10 steps, a mark "Food counter", 8 steps, a right
turn, 6 steps, a mark "Stage side". This is the shape MapBuilder will produce from a
real recorded walk (see docs/DEMO.md).
Test:
- routes between every pair of places, in both directions
- the heading convention (left = positive)
- a straight walk
- a correct turn snapping to the next leg
- a wrong turn giving offRoute
- overwalk giving rescan
- navigating BACK along the trail (reversed legs, so left and right swap)
- a tap "I'm here" anchor mid-leg
- an off-route anchor setting needsReplan
- "platform 3" NOT matching "Platform 2"
- Devanagari text matching an alias
Run flutter test test/core until everything passes, then show me the output.
```

**3. Gemma spike** (lib/ai/ only)

```
Read the flutter_edge_ai 2.1.1 docs on pub.dev. In lib/ai/, create GemmaService:
- load the Gemma 4 E2B .litertlm from the absolute path written in
  docs/DECISIONS.md, with ModelFileType.litertlm and the GPU backend
- warm it up once at startup
Implement DestinationResolver:
- try PlaceMatcher first
- only if that returns null, ask Gemma using function calling, with one tool
  choose_place(place_id) whose description lists the map's place ids and names
- validate the returned id against the map; discard anything else
Add a debug screen showing the load time and answer time. Done when, on the iQOO in
aeroplane mode, with marked places "Food counter" and "Stage side", the requests
"where can I get coffee", "take me back to the stage" and "मुझे खाने की जगह जाना है"
resolve correctly and "take me to the moon" returns null. Write the timings in
docs/DECISIONS.md. If flutter_edge_ai fails to build or load, try flutter_gemma 1.11.4
(its final release) before giving up, and tell me.
```

**4. Merge review** (at every sync point)

```
Use a subagent to review the diff of branch <branch> against main. Check it against
docs/CONTRACTS.md and the ownership table in AGENTS.md. Report only contract breaks,
files outside the owner's paths, missing tests, or anything that could crash on the
phone. No style comments.
```

---

## Teammate 2 (Codex)

**1. Sensing spike**

```
Read AGENTS.md and docs/CONTRACTS.md. You own android/app/src/main/kotlin/,
lib/sensing/, test/sensing/, traces/, lib/core/map_builder.dart and the map-builder
and trace-replay tests only.

1. In Kotlin, add the EventChannel breadcrumb/sensing exactly as "Sensor stream" in
   docs/CONTRACTS.md specifies:
   - hardware step events
   - motion samples at about 50 Hz: yawRate in degrees per second (the gyroscope
     dotted with the unit gravity vector, converted from rad/s) and accel magnitude
   - one broadcast stream, events posted on the main thread
   - an "info" event saying whether a step detector exists
   - no thresholds in Kotlin
2. In lib/sensing/, write pure-Dart StepDetector (fallback) and TurnDetector, following
   the rules in CONTRACTS.md and reading constants from lib/core/tuning.dart. Unit-test
   them with synthetic samples: a 90-degree left turn gives one TurnEvent of about +90;
   a slow 20-degree sway gives none.
3. Write SensingSource wrapping both, and a TraceRecorder writing .jsonl with a meta
   line first to the app's documents/traces/ folder.
4. Build lib/sensing/debug_screen.dart showing: step detector yes/no, step count, the
   last turn angle, and a mark button.

Done when, on the iQOO, 20 real steps show as 18–22, and a left and a right 90-degree
turn show as about +90 and -90. Tell me whether the phone has a hardware step detector.
```

**2. Map builder and record mode**

```
Implement lib/core/map_builder.dart (pure Dart) per CONTRACTS.md, with tests:
- the heading accumulates from turn angles
- every turn creates a junction
- addPlace splits the current corridor at the current step count
- finish() gives a MapGraph whose JSON round-trips
Then build lib/app/screens/record_screen.dart:
- Start: enter the start place name
- live step count and detected turns
- "Add place": open the scan screen, take the SignReader's proposed text, and the
  person confirms or edits it
- Stop: save the map JSON
Done when a map recorded on a real walk loads in the Navigate screen and plans routes
correctly.
```

**3. Trace replay and tuning**

```
Write test/core/trace_replay_test.dart:
- for every traces/*.jsonl, read the meta line (map, from, to)
- run StepDetector/TurnDetector on the motion samples, and feed the Tracker
  (pausing turns between scan on/off lines)
- assert that the final position is within 4 steps of "to"
Print, for each trace: detected versus real (marked) turns, false turns, and steps off
at arrival. Then suggest new tuning values with the numbers that justify them. Don't
edit lib/core/tuning.dart yourself; send the suggestion to Ifzal.
```

---

## Teammate 3 (Antigravity)

**1. App shell on fake data**

```
Read AGENTS.md and docs/CONTRACTS.md. You own lib/main.dart, lib/app/ (except
record_screen.dart), lib/perception/, tools/ and test/app/ only. Use the Fake classes
from lib/core/ until the real ones land, and wire them in one place, such as
lib/app/wiring.dart.

Build:
- Runtime permissions: camera, microphone and activity recognition, with a clear
  message if refused
- Home: two big buttons, Navigate and Map a route
- Destination list: from the map's places (never junctions)
- Navigate screen: the current instruction in very large text, steps left, a progress
  bar, an arrow, an "I'm here" button and a "Scan sign" button
- Speaker: flutter_tts with an offline en-IN voice; vibration left = two short,
  right = one long, arrive = three short
- lib/app/widgets/trail_view.dart: draws a MapGraph as lines (walk each corridor
  from the start using heading and steps), marked places as labelled dots, the route
  highlighted and the current position as a moving dot. It must redraw live as the
  map grows during recording. This is the centre of the demo, so make it look good.
High contrast, large touch targets. Done when it runs on the phone in aeroplane mode,
speaks each new instruction, and vibrates on turns.
```

**2. Sign reading**

```
Implement MlKitSignReader in lib/perception/ (google_mlkit_text_recognition, Latin plus
Devanagari) behind the SignReader interface. Add the scan screen:
- call tracker.pauseTurns(true) when it opens and false when it closes
- a camera preview and a capture button
- the recognised text, then PlaceMatcher's result
- "You're at <place>" or "Couldn't read that, try again"
- if the place isn't on the route, plan again from it
Test it with 10 printed sign photos in test/perception/ and report how many matched.
```

**3. Replay mode and Office Kit export**

```
Add:
- Replay mode: pick a .jsonl trace and feed it through the real detectors, Tracker and
  Guide at real speed, with "Replay" shown on screen at all times
- Map export: use file_picker's save dialog so the person saves the map JSON into
  Download; Office Kit then sends it to the laptop
- Map import: with file_picker
Done when a map makes the round trip phone, laptop, phone through Office Kit.
```

**4. Map desk** (`tools/map_desk.html`, one file, no internet)

```
Create tools/map_desk.html: a single offline HTML file.
- Load a map JSON with a file input.
- Draw the graph: position each place by walking the corridors from the start place,
  using each corridor's heading (counter-clockwise degrees) and step count.
- Draw places as labelled dots and corridors as lines, with lengths in steps.
- View only first. If time allows: click a place to rename it or edit its aliases, and
  save an updated JSON download.
- No external scripts or fonts.
```
