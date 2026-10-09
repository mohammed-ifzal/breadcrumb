# Status: Ifzal

Newest entries go at the top. Add 3 lines at every sync and before sleeping. Agents add
their handoff here before a session ends.

## Sat 10 Oct 01:40, PR #3 review + D19 session
Done: D19 on main 4782c14 (MapBuilder.snapshot() with "_here" + hereId const +
FakeMapBuilder impl + test; trace name <date>-<walker>-<map>-<micros>.jsonl; stepSource
"hardware" | "accel"). main: analyze clean, 80 tests green. Built, installed on the iQOO,
launched, no crash; it shows the placeholder screen (Home isn't on main yet).
PR #3 NOT merged: main merges cleanly, analyze clean, 84 tests green, CI green, all files
in T3 paths. Blocking: (1) navigate_screen.dart:34-48 Timer.periodic fakes steps and +90
turns with no "Replay" label (rule 9); must use SensingSource.events(). (2) The start place
is listed as a destination; plan(start,start) gives legs [] and FakeGuide r.legs[0] throws
in initState; trail_view.dart:144 legs.last also throws. Not yet posted on the PR.
PR #2: has NO build.gradle.kts change (only Kotlin, lib/sensing, tests, status), so no
comment posted. The step-sensor blocker from the last session is still open.
Next: post the PR #3 blockers to T3; T2 implements snapshot() in map_builder.dart; decide
T2's android/gradle.properties memory request.
Blocked: nothing. Last commit: this handoff.

## Sat 10 Oct 01:05, end of merge-review session
Done: merged PR #1 (core engine, a93c607); main analyze clean, 79 tests green. Contract
update a4a4bc6: PlaceMatcher regex keeps \p{M}; Clarifications list (offRoute before snap
zone, turns ignored while off route, places passed through, RoutePlanner ArgumentError).
main built, installed and launched on the iQOO, no crash (placeholder screen).
Reviewed PR #2 (t2/sensing-spike), NOT merged: CI green; main merged into it passes plain
flutter test (96). Blocking: SensingChannel.kt registers the step sensor in the same loop
as gyro/accel, so if it fails (e.g. no ACTIVITY_RECOGNITION) the whole stream dies.
PR #3 (t3/app-shell) is open and not reviewed yet.
In progress: nothing; on main, clean.
Last commit: 9ab4520 (handoff), then this end-of-session edit.
Next: review PR #3 (t3/app-shell) with a subagent per CLAUDE.md; merge PR #2 once T2 fixes
the step-sensor blocker and posts phone results; then PROMPTS.md Ifzal prompt 3 (Gemma).
Blocked: nothing. T2 asks for android/gradle.properties memory changes (decide).

## Fri 9 Oct, core-engine session
Done: Gemma pushed to `/data/local/tmp/llm/gemma-4-E2B-it.litertlm`, 2588147712 bytes,
sizes match (D18, on main 0b70abf). Core engine (prompt 2) on branch
`ifzal/core-engine`: map_json, route_planner (DijkstraRoutePlanner), place_matcher
(FuzzyPlaceMatcher), tracker (RouteTracker), guide (RouteGuide), route_runs; tests in
test/core/ (78 core tests green, analyze clean). PR open to main, not merged.
Contract deviation: PlaceMatcher keeps `\p{M}` too, or Devanagari words break apart.
CONTRACTS.md rule 1 still shows the old regex; update it if accepted.
Next: merge the PR after review, swap the fakes in lib/app/wiring for the real classes
(Teammate 3), then prompt 3 (Gemma spike, lib/ai/).
Blocked: nothing.

## Fri 9 Oct, end of hour-0 session
Done: hour 0 complete. CI run #2 green. Debug APK installed and running on the iQOO
(I2501, Android 16). Docs synced to D15; D16 and D17 recorded.
In progress: nothing (all on main, no open branch).
Last commit on main before this entry: ca4fab3 (Docs: sync to D15 record-and-return demo).
Next: push the Gemma .litertlm to the phone (docs/SETUP.md option A or B) and record the
path in DECISIONS.md; then the core engine = docs/PROMPTS.md, Ifzal prompt 2.
Open issues:
- flutter_tts applies the Kotlin Gradle Plugin; future Flutter will reject it (warning only).
- Android SDK has no cmdline-tools, so no sdkmanager; flutter doctor flags one category.
- Check the APK really contains only arm64-v8a libs (unzip -l app-debug.apk | grep lib/).
Blocked: nothing.

## Fri 9 Oct, hour 0
Done: hour-0 commit (Flutter 3.47.7, AGP 9.1.0, pinned packages, shared debug key, manifest, contracts, tuning, trail_geometry, fakes, owner READMEs, CI); docs synced to the D15 record-and-return demo; D16 and D17 recorded. Debug APK installs and opens on the iQOO (I2501, Android 16).
Next: core engine (RoutePlanner, PlaceMatcher, Tracker, Guide) with tests, then the Gemma DestinationResolver.
Blocked: nothing.

## Thu 8 Oct
Done: plan, starter pack, research.
Next: hour-0 setup at the venue.
Blocked: nothing.
