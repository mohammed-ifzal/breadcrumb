# Decisions

Newest entries go at the top. Once a decision is written here, nobody re-argues it
without new evidence.

| # | Date | Decision | Why |
| --- | --- | --- | --- |
| D23 | 10 Oct | Stop on the record screen auto-adds a place "End of walk" at the final position (`MapBuilder.addPlace('End of walk', [])` just before `finish()`), unless a place was marked with no steps since. Navigate's "You are at" defaults to the latest map's last place (the last `kind: place` node in walk order), with a selector to change it. Written in CONTRACTS under MapGraph. | The demo walker ends the loop where Navigate starts, so the start must already be right without a tap; an unmarked end would leave Navigate starting from the first place instead. The selector covers starting anywhere else. The no-steps guard avoids a zero-step corridor |
| D22 | 10 Oct | The record screen saves the finished map to `<app documents>/maps/latest.json`, overwriting it each time. Navigate loads `latest.json` if it exists, otherwise the bundled demo map. Written in CONTRACTS under MapGraph. | The demo records a fresh loop and then navigates it, so the walk just recorded must be what Navigate opens, with no picker; the demo map keeps Navigate working before anything has been recorded |
| D21 | 10 Oct | Two new tuning constants: `maxMotionGapMs` = 200 (motion samples with a bigger gap reset turn integration) and `turnSnapDegrees` = 45 (`MapBuilder` rounds each recorded turn angle to the nearest multiple). CI frees runner disk before building. | A gap in motion samples would integrate a stale yaw rate into a false turn; snapping keeps recorded loops square so the trail and route instructions stay clean. CI's `flutter build apk` ran out of disk on the LiteRT-LM libraries |
| D20 | 10 Oct | Add `flutter_edge_ai_litertlm` pinned to exactly 1.10.1 next to `flutter_edge_ai` 2.1.1, registered with `FlutterEdgeAi.initialize(inferenceEngines: [LiteRtLmEngine()])`. Gemma is installed with `.fromFile(path)` (registers the pushed file, no copy). `DestinationResolver` = `GemmaDestinationResolver` in `lib/ai/`: PlaceMatcher first, then one tool `choose_place(place_id)`; only an ID of a non-junction place (never `"_here"`) is accepted, with score `matchThreshold`; text replies, errors and a `gemmaTimeoutMs` (20 s) timeout give `null`. | flutter_edge_ai 2.x core ships no engine, so `.litertlm` cannot load without it; 1.10.1 needs `flutter_edge_ai ^2.1.1` and is older than the 1.11.0 published the day before. The build hook downloads native libraries at build time only; nothing runs over the network at runtime |
| D19 | 10 Oct | `MapBuilder` gains `MapGraph snapshot()`: the map so far, including the open corridor ending at a temporary node `"_here"` (kind junction). Pure Dart. The record screen calls it after every step, turn and mark and pushes it to `TrailView` through a `ValueNotifier<MapGraph>`; `TrailView` draws `"_here"` as the moving dot. Trace files are named `<date>-<walker>-<map>-<micros>.jsonl`. The trace `meta` field `stepSource` is `"hardware"` or `"accel"`. | D15 makes the live trail core, so the record screen needs the partial map; the micros suffix stops two walks on the same day overwriting each other; the stepSource values name what actually produced the steps |
| D18 | 9 Oct | Gemma model on the iQOO (option A): `/data/local/tmp/llm/gemma-4-E2B-it.litertlm`, 2588147712 bytes (matches `D:\models` on the captain's laptop). GemmaService loads it by that absolute path. | Google's on-device LLM pattern; survives app reinstalls and uninstalls |
| D17 | 9 Oct | Detector inputs are `onMotion(int t, double accel)` and `onMotion(int t, double yawRate)`; fakes take the map in their constructor | CONTRACTS.md named no input type; primitives avoid a new shape, and Dart interfaces can't require constructors |
| D16 | 9 Oct | Flutter 3.47.7 (Dart 3.13.5) on every laptop and CI; Android build on AGP 9.1.0, Gradle 9.3.1, Kotlin 2.4.0 (the 3.47 template). Pins that resolved: `flutter_edge_ai` 2.1.1, `google_mlkit_text_recognition` 0.17.1, `speech_to_text` 7.5.0, `flutter_tts` 4.2.5, `sensors_plus` 7.1.1. Unpinned, as locked: `camera` 0.12.1, `file_picker` 13.1.0, `path_provider` 2.1.6, `vibration` 3.2.1. `permission_handler` is pinned to exactly 12.0.3. `pubspec.lock` is committed. | ML Kit 0.17.1 and speech_to_text 7.5.0 need Dart 3.12+. `permission_handler` 13.x pulls `permission_handler_android` 14.x, which compiles against API 37; the SDK installs that as `android-37.0` and AGP 8.11 and 9.1 both fail to find `android-37`, so 12.0.3 (Android side 13.0.1, API 35) it is |
| D15 | 9 Oct | Demo = record a trail live, mark places, then navigate back. No venue signs, no hand-written map. Record mode and the live trail view are core, not stretch. | The venue has no signs and taping may not be allowed; this works anywhere |
| D14 | 8 Oct | One status file per person in `docs/status/` | A shared status file causes merge conflicts |
| D13 | 8 Oct | Version 1 maps come from one walk; merging walks is a stretch goal | Each walk has its own heading frame |
| D12 | 8 Oct | One shared debug keystore is committed | Builds from different laptops and CI would otherwise refuse to install over each other, and uninstalling wipes the model |
| D11 | 8 Oct | Kotlin streams raw data only; step and turn detection is pure Dart. Names are `RoutePlan` and `RoutePlanner`. | Retunable from traces; avoids clashing with Flutter's `Route` and `Router` |
| D10 | 8 Oct | Office Kit is used only through its own features: file transfer, clipboard, Remote PC, mirroring | It has no developer API |
| D9 | 8 Oct | Build in levels L0 to L4; L0 must work by the first evaluation round | There is always something demoable |
| D8 | 8 Oct | One floor, corridor graph, no backend, no accounts | Scope that fits 48 hours |
| D7 | 8 Oct | Step and turn sensing through our own Kotlin EventChannel | `sensors_plus` and `pedometer` lack per-step and rotation-vector streams |
| D6 | 8 Oct | ML Kit is the sign reader; Gemma resolves spoken destinations. Gemma sign naming is a stretch goal. | ML Kit is fast and bundled; Gemma's image time is unknown |
| D5 | 8 Oct | `flutter_edge_ai` pinned to exactly 2.1.1 (re-check at hour 0); `flutter_gemma` 1.11.4 is the fallback | Renamed from `flutter_gemma` and published the day before the event |
| D4 | 8 Oct | `AGENTS.md` is the main instruction file; `CLAUDE.md` imports it | Codex, Antigravity and Jules read `AGENTS.md` natively |
| D3 | 8 Oct | Every AI output must pass `PlaceMatcher` to an existing place ID | AI perceives, code decides |
| D2 | 8 Oct | Demo signs are in English and Hindi | ML Kit reads Latin and Devanagari, not Kannada |
| D1 | 5 Oct | Breadcrumb, Mobility track | Fits the track; the judge walks the demo |

## Answers from organisers (fill in during hour 1)

| Question | Answer |
| --- | --- |
| Red Light windows and split | |
| Can laptops run agents during Red Light, steered from the phone? Are cloud agents allowed? | |
| Evaluation rounds: times and what is checked | |
| Submission deadline, repo lock, platform; are planning docs OK? | |
| Phones per team; ADB and sideloading allowed? | One iQOO 15 per person (3) |
| AI credits: provider and amount | |
| Venue Wi-Fi allows device-to-device connections? | |

## Spike results (fill in at G1)

| Spike | Result | Numbers | Fallback chosen |
| --- | --- | --- | --- |
| Gemma 4 on the iQOO | **Pass** (10 Oct, aeroplane mode, `flutter_edge_ai` 2.1.1 + `flutter_edge_ai_litertlm` 1.10.1, D20). Loads from the D18 path (option A works, option B not needed). Backend **GPU** (OpenCL), no CPU fallback. Presets: "where can I get coffee" -> Food counter via Gemma, **pass** (first prompt version gave null; the system prompt now says a request may ask for something you can get at a place); "take me back to the stage" -> Stage side via Gemma, **pass**; "मुझे खाने की जगह जाना है" -> Food counter via Gemma, **pass**; "take me to the moon" -> null, **pass**. | Load 2758 ms + warm-up 539 ms (screen on; the very first load also compiles GPU programs and took far longer, with the screen asleep). Answers: coffee 6059 ms, stage 5739 ms, Hindi 5264 ms, moon 4118 ms. About 4 s of each is `createConversation` building the tool grammar; generation is 0.3-1.3 s. | Not needed; tap-a-place stays as the UI fallback when the answer is null |
| Step detector present? | Yes; hardware-only displayed count | Slow: 20 / 20 / 20 for 20 real steps; fast: reported 10–15% undercount | Accel fallback only when hardware is unavailable |
| Turn detection | Left/right and sway trials pass (Talha reported) | Left: +89, +88, +91 degrees; right: -88, -87, -88.4 degrees; ~20-degree sway: no false turn | None |
| ML Kit on signs | | signs read correctly / total | |
| Offline speech recogniser | | | |

### Talha's physical sensing spike — 10 Oct 2026

- Phone: iQOO I2501 (Android `ro.product.model`); adb device `10BFBJ1L2J001GG`.
- Hardware step detector: yes; `android.hardware.sensor.stepdetector` and `android.hardware.sensor.stepcounter` features verified on the device.
- 20 real steps, slow: **20 / 20 / 20** (Talha reported).
- 20 real steps, normal: **about 19 to 21 per trial**; Talha recalled **20 / 20 / 20**. These are approximate figures reported by Talha, not recorded per-trial measurements.
- 20 real steps, fast: **about 17 to 18 per trial**; Talha recalled **17 / 18 / 17** (about 10–15% undercount). These are approximate figures reported by Talha, not recorded per-trial measurements. The displayed count is hardware-only, with no hardware/accel fusion.
- Immediate versus after five seconds: Talha reports that fast counts were read immediately and were **unchanged after five seconds**; this is an approximate recollection, not a recorded per-trial comparison.
- Earlier first-round counts: **20 / 18 / 17**, retained for honesty.
- 90-degree left x3: **+89, +88, +91 degrees** (Talha reported).
- 90-degree right x3: **-88, -87, -88.4 degrees** (Talha reported).
- Sway about 20 degrees: **no false turn** (Talha reported).
- Hold: Talha reports holding the phone normally at approximately **lower chest height, slightly above the waist**; position is approximate and was not measured.
- Trace: `traces/spike_walk_talha.jsonl` is from the **first session**; the later **nine-trial retest was not recorded to a separate trace file**. It was pulled from the newest device file `2026-10-09-T2-sensing_spike-1791578862394701.jsonl`. Walking with a right turn, a left turn, and another right turn, with matching tester marks. **2,274 valid JSON lines**: 1 meta, 2,232 motion samples (`yawRate` and `accel`), 38 hardware step events, 3 marks; no separate derived-turn records. Time span: **44.620 seconds**, t=1,071,365..1,115,985 ms; file size **191,291 bytes**. Replaying the current TurnDetector rules gives **-87.24, +92.82, -70.75 degrees**; these are this recorded walk's results, separate from the reported 90-degree trial series above. Raw hardware events do not establish the number of real footfalls.
- Native change: `SensingChannel.kt` was edited so a failed optional step sensor no longer unregisters gyro and accel (or gravity); it emits `stepDetector:false` once and leaves motion sensing running.
- Open item: `maxMotionGapMs = 200` remains local to sensing code; captain to add `const int maxMotionGapMs = 200;` to `lib/core/tuning.dart`, then T2 can use that shared constant.
- Verification: cadence regression tests preserve all 20 synthetic steps at 333, 400 and 1,000 ms intervals in hardware and fallback paths; stationary motion/turn tests add no steps. This is software evidence, not proof that the physical fast-step undercount is fixed. Protected fallback settings remain unchanged: `accelPeakThreshold = 11.5` m/s2 and `accelPeakMinGapMs = 300` ms.
