# Status: Ifzal

Newest entries go at the top. Add 3 lines at every sync and before sleeping. Agents add
their handoff here before a session ends.

## Sat 10 Oct 02:40, Gemma spike (prompt 3) session
Done: branch ifzal/gemma. lib/ai: GemmaService (flutter_edge_ai 2.1.1 + new
flutter_edge_ai_litertlm 1.10.1, D20), GemmaDestinationResolver (PlaceMatcher first,
then tool choose_place; only real non-junction IDs pass), debug_screen + debug_main.
On the iQOO in aeroplane mode: GPU, load 2758 ms + warm-up 539 ms, all 4 presets pass,
answers 4.1-6.1 s (Spike results in DECISIONS.md). D18 path works; option B not needed.
Added gemmaTimeoutMs (20 s) to tuning.dart + CONTRACTS.md tuning table.
analyze clean, 95 tests green (15 new in test/ai).
In progress: PR open, not merged.
Next: cut answer time: ~4 s/request is createConversation building the tool grammar;
try reusing one chat per map instead of one per request. Wire resolver into the app (T3).
Blocked: nothing. Last commit: this handoff.

## Sat 10 Oct 01:45, end of PR #3 review + D19 session
Done: D19 on main 4782c14 (MapBuilder.snapshot() + "_here"/hereId, FakeMapBuilder + test;
trace name <date>-<walker>-<map>-<micros>.jsonl; stepSource "hardware" | "accel").
main: analyze clean, 80 tests green; installed on the iQOO, launched, no crash
(placeholder screen; Home arrives with PR #3).
PR #3 NOT merged (merges cleanly, 84 green, CI green, paths OK). Blockers: (1)
navigate_screen.dart:34-48 Timer fakes steps/+90 turns, no "Replay" label (rule 9); use
SensingSource.events(). (2) Start place listed as destination: legs [] -> r.legs[0]
throws in initState; trail_view.dart:144 legs.last too. Not posted on the PR yet.
PR #2: no build.gradle.kts change, no comment posted; step-sensor blocker still open.
In progress: nothing; on main, clean.
Next: post the PR #3 blockers for T3 (gh pr comment 3); T2 implements snapshot() in
map_builder.dart; decide T2's android/gradle.properties memory request.
Blocked: nothing. Last commit: this handoff (previous 9363524).

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
