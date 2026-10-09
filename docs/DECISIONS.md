# Decisions

Newest entries go at the top. Once a decision is written here, nobody re-argues it
without new evidence.

| # | Date | Decision | Why |
| --- | --- | --- | --- |
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
| Phones per team; ADB and sideloading allowed? | |
| AI credits: provider and amount | |
| Venue Wi-Fi allows device-to-device connections? | |

## Spike results (fill in at G1)

| Spike | Result | Numbers | Fallback chosen |
| --- | --- | --- | --- |
| Gemma 4 on the iQOO | | load time, answer time | |
| Step detector present? | | steps counted / real steps | |
| Turn detection | | angles seen for 90-degree turns | |
| ML Kit on signs | | signs read correctly / total | |
| Offline speech recogniser | | | |
