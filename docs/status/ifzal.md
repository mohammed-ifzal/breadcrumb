# Status: Ifzal

Newest entries go at the top. Add 3 lines at every sync and before sleeping. Agents add
their handoff here before a session ends.

## Sat 10 Oct, UI session (branch ifzal/ui, stacked on t3/real-sensors, PR open, not merged)
Done: T3's t3/real-sensors already had theme.dart + Home/Destination logic, so ifzal/ui is
based on it (Ifzal's call). theme.dart replaced: dark #0B0F14/#141A22, teal #2DE2C3, amber
#FFB020, radius 20, 56 dp, type 42/28/17, system font; name BreadcrumbTheme.themeData kept, so
main.dart is untouched. lib/app/widgets/ui/: PrimaryButton, ActionCard, StatusPill,
SectionHeader, ThinkingIndicator. Home and Destination restyled, T3's logic unchanged.
Tests: test/app/widgets/ui/ (16, incl. font scale 1.3 on 360 dp). analyze clean, 206 green.
iQOO check done: Home -> "where can I get coffee" -> Cafe route -> debug steps -> "Cafe is
here." with SIMULATED shown; no crash in logcat. Outlined buttons tightened so the debug row fits.
Found (not mine): TrailView paints place dots/labels black, invisible on the dark background;
'I am here' tapped once per leg ends on "That turn wasn't on the route" at Cafe, not arrival;
Navigate's bottom row and body overflow at font scale 1.3 on 360 dp (widget test).
Next: PR #10 retargets to main once T3's branch merges; T3 fixes the TrailView colours.
Blocked: T3 must open/merge t3/real-sensors first. Last commit: this handoff.

## Sat 10 Oct 10:25, merge round 2: PR #2, #5, #7 merged, D23
PR #2 merged locally 1256dc6 (DECISIONS: Gemma + step + turn spike rows kept), pushed.
PR #5 merged a2c8655 (temp-branch check with #2: analyze clean, 189 tests). PR #7
(tools/ only) merged 19c14d4, teammate3.md conflict kept both entries. No open T2
record-screen PR. D23 (End of walk on Stop; Navigate 'You are at' = last place + selector)
in DECISIONS + CONTRACTS. Main app (a2c8655, app code = 19c14d4) installed on the iQOO,
Home shows, no crash. en-IN + hi-IN speech packs downloaded by Ifzal.
Next: spoken test with the Gemma debug APK; fill DECISIONS speech row + BENCHMARKS.
T2: D22 save + D23 End of walk in record_screen, use tuning.maxMotionGapMs, move
docs/traces/spike_walk_talha.jsonl to traces/. T3: D22 load + D23 start selector.
Blocked: nothing. Last commit: this handoff.

## Sat 10 Oct 09:25, merge round: PR #6 merged, PR #2 blocked, D22, speech diagnosis
PR #2 NOT merged: origin/main conflicts in docs/DECISIONS.md (Spike results rows); fix
posted as a PR comment (also: use tuning.maxMotionGapMs, docs/ is mine). PR #6: speech fix
a4f93ca, review clean, CI green, merged f6b8e8f. D22 on main 74dff2e (DECISIONS + CONTRACTS
MapGraph: record saves <app documents>/maps/latest.json, Navigate loads it else demo map).
Speech diagnosis: both buttons fail in 25-100 ms with error_language_unavailable, because the
en-IN/hi-IN on-device packs (Android System Intelligence) are listed but not installed. Also
fixed: 2 s pauseFor counted from the tap; the error that came after `done` was dropped.
main f6b8e8f: 134 tests green, debug APK installed on the iQOO, Home shows, no FATAL.
Next: Ifzal downloads en-IN + hi-IN under Settings > On-device speech recognition (Wi-Fi once),
reinstall the Gemma debug APK (`flutter build apk --debug -t lib/ai/debug_main.dart`), redo
the spoken test, then fill the DECISIONS spike row + BENCHMARKS "Spoken test 2". T2 rebases
PR #2. D22 implementation: T2 (record_screen save), T3 (Navigate load).
Follow-up: GemmaService serialises calls; a hung call stalls later requests to null.
Blocked: speech packs (phone settings). Last commit: this handoff.

## Sat 10 Oct 05:00, voice + benchmark session (branch ifzal/voice, PR open, not merged)
Done: GemmaService reuses one chat per map, clears history after each answer (conversation
open ~1650 ms moved off the critical path). iQOO GPU, load 2468 ms: Gemma median 2863 -> 1173
ms, p90 4432 -> 2363 ms; 96/120 correct, 0 false positives, 24 misses (8 requests, all to null).
Two prompt rewrites scored 90/120, original kept. docs/BENCHMARKS.md. SpeechInput
(lib/ai/speech_input.dart): on-device only, no network fallback. Offline en-IN yes, hi-IN yes.
analyze clean, 128 tests green. The phone has the Gemma debug APK (not the main app) installed.
Spoken test (yours): phone in aeroplane mode, open Breadcrumb (Gemma debug), wait for "Loaded",
tap "Speak (en-IN)", say "where can I get coffee" -> "Heard (en_IN): ..." then Food counter.
Tap "बोलें (hi-IN)", say "स्टेज कहाँ है" -> Stage side. Say nothing once -> "Heard nothing".
Note: vivo Remote Control in front blocked the run once; I brought the app forward.
Next: spoken test; merge PR after review; reinstall main app (flutter build apk --debug).
Blocked: nothing. Last commit: this handoff (previous 2be332a).

## Sat 10 Oct 03:50, D21 + merge PR #3 and #4 session
Done: D21 on main 303209c (tuning maxMotionGapMs 200, turnSnapDegrees 45; CONTRACTS table;
CI frees runner disk: 82% -> 69% used, 14G -> 23G free). TASKS: T3 follow-up added (f50f2b9).
PR #3 merged (5374364); comment lists the two SIMULATED-label follow-ups for t3/live-trail.
PR #4: merged main into ifzal/gemma (kept both status entries and D21 above D20), analyze
clean, 113 green, CI green incl. `flutter build apk`; merged (5ed8b92).
main 5ed8b92: 113 tests green; debug APK built, installed on the iQOO, launched: Home shows
Navigate / Map a route / Replay mode, no FATAL in logcat.
In progress: nothing; on main, clean.
Next: Home/Navigate/Replay smoke test on the iQOO; T2 uses maxMotionGapMs in TurnDetector
and turnSnapDegrees in MapBuilder; T3 does the SIMULATED follow-ups first on t3/live-trail.
Blocked: nothing. Last commit: this handoff.

## Sat 10 Oct 03:10, merge session for PR #3 + #4 (neither merged)
PR #3 BLOCKED (comment posted): main merged in cleanly, analyze clean, 98 tests green, CI green,
ownership OK, checklist OK. Rule 9 issues: SIMULATED label hides at arrival
(navigate_screen.dart:96-113) while the fake arrival stays on screen, and the kDebugMode
+1 step / ±90° buttons (:135-160, :324-347) move the dot unlabelled in the debug APK.
PR #4 BLOCKED on CI only (comment posted): code review clean, 95 tests green. CI's
`flutter build apk` hits "No space left on device" twice (LiteRT-LM libs). Fix .github/ (mine).
main: 80 tests green; installed on the iQOO, placeholder screen, no crash in logcat. The
Home/Navigate/Replay smoke test waits for #3. DEMO.md: added the Gemma first-load checklist line.
Next: free runner disk space in .github/workflows, re-run #4 CI, merge #4 (resolve the
status-file conflict at the top of this file); T3 fixes #3, then merge #3 and run the smoke
test. Blocked: T3 on #3. Last commit: this handoff.

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
