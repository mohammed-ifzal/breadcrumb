# Status: teammate3

Newest entries go at the top. Add 3 lines at every sync and before sleeping. Agents add
their handoff here before a session ends.

## Sat 10 Oct, 14:15
Done: 3-state AI status (loading/ready/unavailable with timeout & error handling), fuzzy-first destination search with honest AI fallback, mic error text display with speech-pack note and hint; 262 tests green, flutter analyze clean.
Next: Review captain PR #12 merge, on-device test of speech and Gemma when model is available.
Blocked: Nothing.

## Sat 10 Oct, 13:30
Done: Added live reload of maps/latest.json on DestinationListScreen (and Home Navigate tap) with documentsDirectoryProvider override; added test/app/destination_reload_test.dart verifying recorded map pickup without restart and fallback to demo map; 250 tests green, flutter analyze clean.
Next: On-device testing of loop record -> live navigate reload; integrate teammate widgets on NavigateScreen.
Blocked: Nothing.

## Sat 10 Oct, 11:10
Done: Prompt 2 (Sign Reading): Implemented MlKitSignReader in lib/perception/mlkit_sign_reader.dart (Latin + Devanagari OCR via google_mlkit_text_recognition). Added ScanScreen in lib/app/screens/scan_screen.dart with camera capture, tracker.pauseTurns(true/false) lifecyle guard, text recognition + PlaceMatcher evaluation, "You're at <place>" or "Couldn't read that, try again", on-route anchoring, and automatic re-planning when off-route. Wired "Scan sign" button on NavigateScreen. Added test/perception/mlkit_sign_reader_test.dart and test/app/scan_screen_test.dart (10 printed sign simulations match 10/10). 201 tests pass, analyze clean.
Next: On-device check of sign scan with camera; adopt teammate’s shared widgets on Navigate screen once theme PR is merged.
Blocked: Nothing.

## Sat 10 Oct, 10:55
Done: Removed lib/app/theme.dart and reverted screen styling per plan update so teammate owns theme.dart, shared widgets, and Home/Destination restyling. Kept all functional real sensors wiring, D22 map loading, D23 start selector, Gemma warm-up/AI-ready indicator, and mic button. 190 tests pass, analyze clean.
Next: Test real sensors on device; adopt teammate’s shared widgets on Navigate screen (huge arrow, 40+ instruction, bottom trail card) once merged.
Blocked: Nothing.

## Sat 10 Oct, 10:45
Done: Branched t3/real-sensors from main (de5f654). Real sensors: wiring.sensorEvents now merges real SensingSource (native EventChannel) with simulated events; simulation off by default (widget.simulate flag). D22: wiring.reloadActiveMap() loads maps/latest.json from app documents. D23: effectiveCurrentPlaceId defaults to the last place-kind node; "You are at" selector on destination list. Gemma warm-up with AI ready/warming indicator in AppBar. Mic button wired to SpeechInput. Theme in lib/app/theme.dart (dark, high contrast, large touch targets). Replay button hidden until real traces. 190 tests green, analyze clean.
Next: Build debug APK, install on iQOO, test real sensors + Gemma warm-up + mic button. Push PR for review.
Blocked: Nothing.

## Sat 10 Oct, 09:25
Done: Built self-contained offline tools/map_desk.html (MapGraph layout, loop mismatch warning, canvas renderer, place/alias editor, JSON download) and tools/sample_map.json; verified layout math and loop closure in Node.js (heading 0 up, heading 90 left).
Next: Visual check of map_desk.html in a browser; integrate with MapBuilder export when Teammate 2 PR lands.
Blocked: Nothing for tools.

## Sat 10 Oct, 08:20
Done: BUG 2b vibration timing fixed — turns vibrate exactly once per leg when steps <= turnNowSteps ("turn now"), arrive once on arrival, straight never; per-leg state maintained in navigate_screen. 131 tests green, analyze clean.
Next: Physical on-device check of vibration pulse timing at turning thresholds.
Blocked: Teammate 2 PR #2 (SensingSource) for live sensor stream.

## Sat 10 Oct, 04:00
Done: COMMIT 1 (SIMULATED stays on arrival, debug buttons behind dev toggle), COMMIT 2 (bugs 1-4 fixed with regression tests: zero-leg guard, turn vibrations, mid-route "I am here", concise speech), COMMIT 3 (sensorEvents stream in wiring), COMMIT 4 (destination resolver box with thinking state). 129 tests green, analyze clean.
Next: On-device phone checks for speech clarity/calm rate, physical vibration patterns, and Gemma resolver response.
Blocked: Teammate 2 PR #2 (SensingSource) to swap sensorEvents to live hardware stream.

## Sat 10 Oct, 02:00
Done: STEP 2 — Replay screen consumes trace events via StepDetector/TurnDetector interfaces (wiring.stepDetector, wiring.turnDetector); REPLAY label always visible (AppBar + banner); empty/missing-meta/malformed-line traces handled gracefully. STEP 3 — start-place guard, zero-leg route guard, unknown destination error screen. STEP 4 — replay_test.dart (5 tests: REPLAY always visible, empty trace, missing meta, malformed line, full replay), destination_and_navigation_test.dart (SIMULATED label test, turn angle sign test for leg boundaries). 98 tests green, analyze clean, debug APK builds.
Next: Phone test with real .jsonl traces once Teammate 2's PR #2 merges; add export if time permits.
Blocked: Teammate 2 PR #2 (SensingSource / MapBuilder) for live sensor streams and real recorded traces.

## Sat 10 Oct, 01:50
Done: Merged origin/main; wired real engine (RoutePlanner, RouteTracker, RouteGuide); added SIMULATED label, calculated turns, start place and zero-leg guards, D19 ValueNotifier/moving dot in TrailView, and Replay mode with .jsonl trace parser. 98 tests green, analyze clean.
Next: Test on phone and verify replay with real recorded traces once Teammate 2's sensing spike lands.
Blocked: Teammate 2 PR #2 (sensing spike / MapBuilder) for live recording and real sensor streams.

## Sat 10 Oct, 00:35
Done: Prompt 1 (app shell, permissions, navigation, TrailView, speaker) and crash guards verified on iQOO 15 (I2501); 30 tests green, analyze clean.
Next: Prompt 2 (MlKitSignReader in lib/perception/ and scan screen) once core engine lands.
Blocked: Ifzal PR #1 (core engine) to replace fakes with real RouteTracker/RouteGuide.

## Fri 9 Oct, hour 0
Done: cloned repo, accepted Android licenses, built APK, branch t3/app-shell created.
Next: Prompt 1 app shell.
Blocked: nothing.
