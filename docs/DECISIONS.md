# Decisions

Newest entries go at the top. Once a decision is written here, nobody re-argues it
without new evidence.

| # | Date | Decision | Why |
| --- | --- | --- | --- |
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
| Step detector present? | | steps counted / real steps | |
| Turn detection | | angles seen for 90-degree turns | |
| ML Kit on signs | | signs read correctly / total | |
| Offline speech recogniser | | | |
