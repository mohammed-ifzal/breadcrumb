# Breadcrumb: instructions for every AI agent

Read this file fully before any task. Codex, Antigravity and Jules read it automatically.
Claude Code reads it through `CLAUDE.md`.

## What we are building

Breadcrumb is an offline Android app (Flutter) for navigation where GPS fails: car parks,
hospitals, metro stations.

- Record mode: someone walks a route once. Steps and turns draw the trail live on
  screen. They tap 'Mark place' to name spots along the way.
- Navigate mode: the user taps or speaks a destination (Gemma maps requests like 'where
  can I get coffee' to a marked place). The app plans the route back along the trail,
  tracks position by steps and turns, and guides with an arrow, voice and vibration
  while a dot moves on the trail view.
- Demo (docs/DEMO.md): record a loop around our table, mark places, then a judge asks
  for a place and is guided there. No venue signs are needed. Sign scanning is a bonus
  anchor only.

Context: iQOO Hackathon 2026 Grand Finale, Mobility track, 48 hours, demo on an iQOO 15
in aeroplane mode. The full background is in `docs/CONTEXT.md`. Read it only when a task
needs it.

## Hard rules (never break these)

1. **Offline only.** No network calls at runtime, no cloud AI, no API keys anywhere
   in the repo.
2. **AI perceives, code decides.** Gemma 4, ML Kit and speech recognition only produce
   text. In navigation, every AI output goes through `PlaceMatcher` and must resolve to
   an existing place ID, or it is discarded. AI never chooses routes, positions or
   instructions.
   - The one exception is record mode. There, a name proposed by OCR or Gemma becomes a
     place only after the person confirms or edits it.
3. **`lib/core/` is pure Dart.** It has no `package:flutter` imports, no plugins and no
   file or network I/O. The same applies to `lib/sensing/step_detector.dart` and
   `lib/sensing/turn_detector.dart`. Every public function in them has unit tests.
4. **Stay inside your owner's paths** (table below). If a change is needed elsewhere,
   stop and say so; the owner makes it.
5. **Only the captain (Ifzal) edits the shared build files:** `pubspec.yaml`,
   `android/app/src/main/AndroidManifest.xml`, `android/app/build.gradle.kts`,
   `android/app/debug.keystore`, `docs/CONTRACTS.md`, `lib/core/contracts.dart`,
   `lib/core/tuning.dart` and `.github/`.
6. **No new packages** without the captain's approval.
7. **Build against `docs/CONTRACTS.md`.** Use the `Fake...` classes until the real
   module lands. Never change a contract shape on your own.
8. **`main` must always install and run on the phone.** Run `flutter analyze` (clean)
   and `flutter test` (green) before every push.
9. **Never fake results.** Don't hardcode demo outcomes. Replay mode must show the word
   "Replay" on screen at all times.
10. **Every threshold lives in `lib/core/tuning.dart`.** Kotlin only streams raw data;
    step and turn detection logic is pure Dart, so recorded walks can retune it.
11. **Never claim NPU acceleration or an Office Kit API.** Office Kit has no developer
    API; we only use its own file transfer, clipboard, Remote PC and mirroring.

## Who owns what

| Paths | Owner | Agent |
| --- | --- | --- |
| `lib/core/` (except `map_builder.dart`), `lib/ai/`, `test/core/` (except the map-builder and trace-replay tests), `test/ai/`, `assets/maps/`, `docs/` (except other people's status files), plus the shared build files in rule 5 | Ifzal (captain) | Claude Code |
| `android/app/src/main/kotlin/`, `lib/sensing/`, `lib/core/map_builder.dart`, `test/core/map_builder_test.dart`, `test/core/trace_replay_test.dart`, `test/sensing/`, `traces/`, `lib/app/screens/record_screen.dart` | Teammate 2 | Codex |
| `lib/main.dart`, `lib/app/` (except `record_screen.dart`), `lib/perception/`, `tools/`, `test/app/`, `test/perception/`, runtime permission requests | Teammate 3 | Antigravity |
| `docs/status/<your-name>.md` | Each person | Their own agent |

The task board `docs/TASKS.md` is ticked by the captain at sync points.

## How the parts connect

```
Kotlin (breadcrumb/sensing): hardware step events + motion samples (yaw rate, accel)
  -> lib/sensing StepDetector / TurnDetector (pure Dart) -> StepEvent, TurnEvent -> lib/core Tracker
Camera -> lib/perception MlKitSignReader -> SignReading -> PlaceMatcher -> Tracker.anchor
Microphone -> lib/ai speech + Gemma 4 -> destination text -> PlaceMatcher -> RoutePlanner
RoutePlanner + Tracker -> Guide -> Instruction -> lib/app (voice, vibration, screen)
MapGraph JSON <-> Office Kit file transfer <-> tools/map_desk.html on the laptop
```

## Commands

```
flutter pub get
flutter analyze
flutter test                      # everything
flutter test test/core            # engine only, fast
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

## Workflow for every task

1. Start the session as "Sessions and handoff" below describes.
2. Work on a branch named `<owner>/<short-task>`, for example `t2/turn-detector`.
3. First write or update a test that proves the task is done. Iterate until it passes.
4. Make small commits, push, and open a pull request to `main`. Never push to `main`
   directly.
5. Write a handoff at the top of `docs/status/<your-name>.md` (see below).
6. Ask the human before deleting files, adding packages or touching another owner's paths.

## Sessions and handoff (every agent)

- **Start of a session:** `git pull`, then read `AGENTS.md`, `docs/CONTRACTS.md`, your
  own `docs/status/<name>.md`, and the newest entry of the other status files.
- **End of a session, before switching tasks, or when the context is about half full:**
  write a handoff entry at the top of your status file: done / in progress (branch,
  files) / next exact step / blockers / last commit. Max 15 lines. Commit and push it.
  Then tell the human to start a fresh session.
- **Never rely on chat history.** If it matters, it's in the repo.

## Words we use

- **Place:** a named node, such as "Platform 2".
- **Junction:** an unnamed node created at a turn.
- **Corridor:** an edge between two nodes, with a step count and a heading.
- **Leg:** one corridor of a planned route, walked in one direction.
- **Anchor:** snapping position to a known node.
- **Trace:** a recorded walk, one JSON event per line, used for replay tests.
