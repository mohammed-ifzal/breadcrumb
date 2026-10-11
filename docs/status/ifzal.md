# Status: Ifzal

Newest entries go at the top. Add 3 lines at every sync and before sleeping. Agents add
their handoff here before a session ends.

## Sat 10 Oct 23:50, D29 robust core (branch ifzal/robust-core)
Done: PR #21 (D29 contracts + tuning flags) merged de810fe, CI green. Steps 1-4 on the
branch: lib/core/turn_confirmer.dart (StepTurnConfirmer + order-keeping ConfirmedEvents),
Tracker confidence + arrival guard (new Position.unconfirmedArrival), Guide confirmPlace /
arrivingConfirm / maybePassed, wiring.dart (T3) + record_screen.dart (T2) behind
useTurnConfirmer. All D29 flags are false on main.
Replay (4 traces, 9 labelled turns): confirmer off 0 missed / 0 false, on 0 / 0 at
turnConfirmWindowMs 8000 (was 4000: missed all 3 spike-walk turns). Synthetic straight
walk + 3 sidesteps + 2 handlings: off passes 8 false turns, on 0. analyze clean, 404 green.
iQOO: debug APK installed and launched, no FATAL / E/flutter.
In progress: PR #23 (Steps 1-4) open, CI green, not merged; flags not walked on the phone.
Next: merge PR #23; walk the loop with the flags on, then flip them in tuning.dart.
T2: real motionStates()/placements()/totalRamMb() (stubs return empty / 0).
Blocked: nothing. Last commit: this handoff.

## Sat 10 Oct 22:55, end of session: demo build merged to main
Done: PR #20 (demo/now -> main) merged 7014b0d, CI green. Brings in D28 tuning
(turnRateMin 15, turnSettleMs 300), PRs #17, #18 and #19 (now shown as merged), trail labels
and the Navigate layout. Local: analyze clean, 359 tests green.
Final map skipped: origin/t2/final-map doesn't exist yet, so assets/maps/final_map.json
isn't bundled, there's no latest.json fallback, and nothing was pushed via run-as.
iQOO: debug APK from main 7014b0d installed and launched, Gemma 4 loads (prefill 514 ms),
no FATAL or E/flutter in logcat. Screens not checked by hand.
New remote branch seen: origin/t2/robust-sensing (not reviewed).
Next: when T2 pushes t2/final-map, copy demo/final_map.json, bundle it as
assets/maps/final_map.json, add the fallback and its test, then push it as
app_flutter/maps/latest.json via run-as.
Blocked: final map from T2. Last commit: this handoff.

## Sat 10 Oct 16:40, merge round 5: PR #16 and #14 merged
Docs on main 1a082f8: docs/MENTOR.md (10:00 mentor Q&A + feedback), TASKS Saturday plan.
PR #16 merged a90e6bf (CI green, temp merge with main: docs only, 300 green).
PR #14 (t3/polish) merged d38631e: merge of main had no conflicts; #12 reload, Home ->
RecordScreen, speaker D24/D27 wording and main.dart theme all intact. Added 378da6f:
navigate_screen vibrates at "Turn left/right at the corner" (steps == 0), not "Get ready";
bug_regressions_test updated. analyze clean, 319 green, CI green.
iQOO: main d38631e installed, Home / Destination / Navigate OK, no FATAL or E/flutter.
Seen on device: Navigate trail labels "End of walk" and "washroom" overlap; the
orientation card shows "0 steps left on this leg" under "Turn around, then walk straight."
Next: device-load benchmark -> BENCHMARKS.md; pitch; 16:45 final map walk.
Blocked: nothing. Last commit: this handoff.

## Sat 10 Oct 15:55, end of session: D27 robust navigation (branch ifzal/nav-robust)
Done: PR #15 (ifzal/floors, D24) merged 0477be5 (CI green, temp merge up to date, 281 green).
In progress: PR #16 open, not merged (ifzal/nav-robust, D27, CI was pending). Fixes from the
iQOO loop test: orientation phase until the first step (turns only update facing; facing =
arrival corridor if starting where the recording ended, else unknown); "Get ready to turn" ->
"Turn left at the corner", leg advances only on a correct turn or overwalk, snapZone 0.5,
snapSteps 10; off-route text without Scan sign; off route, a matching turn within 2x snapSteps
recovers. T3 path: speaker.dart speaks the Guide text (+ test/app/speaker_wording_test.dart).
analyze clean, 300 green. Debug APK installed + launched on iQOO, no crash; loop not re-walked.
Not handled: (1) turns made before Navigate opens are unseen, so "Turn around" can be wrong
if the walker already turned after Stop; (2) navigate_screen.dart (T3) still vibrates at
"Get ready" (3 steps before the corner), not at the corner.
Next: merge PR #16 once CI is green, then re-walk the loop on the iQOO in aeroplane mode.
Blocked: nothing. Last commit: this handoff.

## Sat 10 Oct, Session A2: D24 floors + speech fallback (branch ifzal/floors, PR open)
PR #13 (t3/ai-status) closed: "Moving into t3/polish per Teammate 3."
D24 in lib/core: Place.floor, Corridor/Leg kind + floorDelta (optional, old maps load and are
written unchanged), decodeMap checks floorDelta, planner +floorChangeCostSteps (20) per
transition, Guide changeFloor ("Take the stairs up to Floor 1."), Tracker.onFloorChange (new
interface method; steps/turns ignored on stairs/lift legs). Tests: test/core/floors_test.dart.
lib/ai/speech_input.dart: en_IN error_language_unavailable -> one retry in en_US (fake recogniser test).
T3 paths touched only to compile: speaker.dart (changeFloor case speaks i.text), scan_screen_test.dart stub.
analyze clean, 281 tests green. Not tried on the iQOO.
Next (T3): Navigate's simulate loop spins on a transition leg (steps ignored): emit onFloorChange
there; optionally a "Took the stairs" button (I am here already completes it); changeFloor icon.
Loop re-test notes were not pasted into the session, so no loop fix in this PR.
Blocked: nothing. Last commit: this handoff.

## Sat 10 Oct 14:40, merge round 4: PR #12 merged, #11 closed
PR #12 (ifzal/loop-fixes) merged e3156fe: temp-branch merge of origin/main (already up to date),
analyze clean, 255 tests green, CI green. D25 (90-degree snap) and D26 (late/arrival turns) are on main.
PR #11 (T3 reload fix) closed as superseded by #12; T3 asked to move the warmAi() early return and the
90 s AI-unavailable timeout into t3/polish.
PR #13 (t3/ai-status) open, not reviewed; Teammate 3 is moving it into t3/polish.
t2/turns: no commits beyond main yet, no PR.
iQOO: main e3156fe debug APK installed and launched, no FATAL / E/flutter in logcat.
Next: loop re-test on the iQOO in aeroplane mode (record -> Navigate -> I am here to arrival),
then Session A2 (D24 floors + speech fallback).
Blocked: nothing. Last commit: this handoff.

## Sat 10 Oct 14:10, loop fixes (branch ifzal/loop-fixes, PR open)
Missing places cause: Home's initState was the only reloadActiveMap() call. App started 13:08:44,
maps/ first written 13:24, latest.json 13:26, so Navigate kept the demo map. Fix: DestinationListScreen
reloads on open; Wiring skips an unchanged file (keeps "You are at"). Start/place/End of walk filters were fine.
D25 turnSnapDegrees 45 -> 90. D26 Tracker: turns ignored after arrival; a turn within lateTurnSteps (3)
after a node already passed by tap/sign/snap, right direction, is absorbed (fixes "I am here" -> offRoute).
Files touched for T3: lib/app/wiring.dart, lib/app/screens/destination_list_screen.dart,
test/app/latest_map_reload_test.dart (new). For T2: test/core/map_builder_test.dart (44 deg now -> 0; iQOO angles case).
analyze clean, 255 tests green. Installed on iQOO: Navigate shows team groza table / washroom / food counter.
Next: Ifzal re-records the loop and navigates it in aeroplane mode; check End of walk + arrival on device.
Blocked: GitHub unreachable at 13:50 (pull/push failed); main not re-pulled. Last commit: this handoff.

## Sat 10 Oct 13:10, merge round 3: PR #9, #8, #10 merged
PR #9 (T3 real sensors + sign scan, head 9f040b9) merged 40f16af: analyze clean, 201 tests, CI green.
PR #8 (T2 record, cf0404a) merged 0cf4c60: 231 tests, CI green. Ownership note: T2 added two new
files in T3 paths (lib/app/screens/record_debug_main.dart, test/app/record_screen_test.dart);
accepted, they only touch the record screen. Trace path fix on main 280f154.
PR #10 (ifzal/ui) retargeted to main, origin/main merged in with no conflicts (T3 logic was already
in from 979484e), Home "Map a route" placeholder replaced by "Record a trail" -> RecordScreen
(7bd43f7, + widget test), CI green, merged 96f6843. main: analyze clean, 248 tests green.
iQOO (main 96f6843 debug APK): Home shows both cards, Record screen opens, Destination shows
"AI ready" + mic + start selector, Cafe -> Navigate with no SIMULATED, Scan sign button. No FATAL.
Not checked in aeroplane mode (Wi-Fi was on).
Still open (T3): TrailView place dots/labels black on dark background; Navigate overflow at 1.3.
Next: full demo loop on the phone in aeroplane mode (record -> latest.json -> navigate).
Blocked: nothing. Last commit: this handoff.

## Sat 10 Oct, UI session (branch ifzal/ui, stacked on t3/real-sensors, PR open, not merged)
Done: T3's t3/real-sensors already had theme.dart + Home/Destination logic, so ifzal/ui is
based on it (Ifzal's call). theme.dart replaced: dark #0B0F14/#141A22, teal #2DE2C3, amber
#FFB020, radius 20, 56 dp, type 42/28/17, system font; name BreadcrumbTheme.themeData kept, so
main.dart is untouched. lib/app/widgets/ui/: PrimaryButton, ActionCard, StatusPill,
SectionHeader, ThinkingIndicator. Home and Destination restyled, T3's logic unchanged.
Tests: test/app/widgets/ui/ (16, incl. font scale 1.3 on 360 dp). analyze clean, 217 green.
Merged T3's newer t3/real-sensors (sign scan; T3 dropped their theme): kept my 3 files, main.dart
keeps BreadcrumbTheme.themeData (T3 had reverted it to blue). Re-checked on iQOO in aeroplane mode.
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
the spike trace to traces/spike_walk_talha.jsonl (done in PR 8). T3: D22 load + D23 start selector.
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
