# Benchmarks

Measured on the phone, never estimated. Newest run at the top.

## AI tiers and generated aliases (D30) on the iQOO 15, Sun 11 Oct 00:40

**Setup:** branch `ifzal/ai-tier`, debug APK of `lib/ai/debug_main.dart` with
`--dart-define=BENCH=tiers`, iQOO I2501 (15.6 GB RAM, so `DeviceTier.full`). Gemma 4 E2B
on GPU: load 2671 ms + warm-up 465 ms. Aeroplane mode was off, but nothing in the path
uses the network.

**Method:** the same 40 requests (`lib/ai/benchmark.dart`), 3 rounds per mode, on the
demo map with **its hand-typed aliases removed** (names only: Start, Food counter, Stage
side), which is what a fresh recording gives. Then `AliasSuggester` asks Gemma once per
place (3 calls, 666-732 ms each) and `applyAliases` stores what passes validation:

- Start: beginning, entry point, shuru, आरंभ, शुरुआत
- Food counter: food, kitchen, food station, khana counter, खाना काउंटर, खाद्य काउंटर
- Stage side: stage, स्टेज

| | Matcher only (names) | Matcher + aliases (basic tier) | Matcher + aliases + Gemma (full tier) |
| --- | --- | --- | --- |
| Correct | 45 / 120 | 63 / 120 | **90 / 120** |
| English | 0 / 45 | 9 / 45 | 27 / 45 |
| Hindi / Hinglish | 0 / 30 | 9 / 30 | 18 / 30 |
| Must be null | 45 / 45 | 45 / 45 | 45 / 45 |
| **False positives** | **0** | **0** | **0** |
| Wrong place | 0 | 0 | 0 |
| Missed | 75 | 57 | 30 |
| Latency, median (all 120) | 0.08 ms | 0.17 ms | 488 ms |
| Gemma answers (102 of 120): median / p90 | - | - | 529 / 1977 ms |

Gemma answer times by group: "none" (must be null) about 470 ms, English place about
1.4 s, Hindi place about 1.9 s. Matcher-only modes are timed in microseconds.

**What aliases add:** "where's the stage", "take me to the stage", "take me back to the
stage area", "स्टेज कहाँ है", "stage kidhar hai" and "mujhe stage pe jaana hai" now
resolve with no model, so they also work on a basic-tier phone. Gemma's aliases name the
place, not what people go there for: none of coffee, tea, snacks, lunch or show came
back, so requests like those still need Gemma.

**Still missed by the full tier** (all 3 rounds): snacks, where can I get coffee, lunch,
where is the show, where are the speeches happening, where's the main event, खाना कहाँ
मिलेगा, chai kahan milegi, nashta kahan hai, show kahan ho raha hai. Gemma replied
"none" to each; none went to the wrong place. The 10 Oct run (hand aliases "canteen" and
"खाना काउंटर") got 96 / 120 because it also resolved "snacks" and "where can I get
coffee".

**Alias prompt experiments** (same map; "aliases" = the basic-tier column):

| Alias prompt | Aliases kept (start / food / stage) | Basic tier | Full tier | False positives (basic / full) | Wrong place (basic / full) |
| --- | --- | --- | --- | --- | --- |
| v1: plain list, no filler filter | shuru, ..., darwaza, room, kuchh, wahan / khana counter, where is it / stage area, stage spot, ... | 45 / 120 | 87 / 120 | **6 / 9** | **15 / 15** |
| v2: v1 + "no question words" + filler words trimmed in code | start point, shuru, entry, ... / food, khaana, food stall, khaana chahiye / stage, stage access, stage view | 63 / 120 | 90 / 120 | 0 / 0 | 0 / 0 |
| **v3 (kept): "what they want there" + a Ticket counter example**, filler filter | as listed above | 63 / 120 | 90 / 120 | 0 / 0 | 0 / 0 |

With v1, the Food counter alias "where is it" caught "where is the washroom" (false positive) and "where is the show" (wrong place), and Start's "wahan" / "kuchh" caught "bathroom kahan hai" and several Hinglish food requests, so the filler
filter (`fillerWords` in `lib/ai/alias_suggester.dart`) is in code, not left to the
prompt. v3 is kept for its cleaner Hindi aliases. topK 40 / temperature 0.8 gave the same
aliases as topK 1, so the session stays greedy.

**Reproduce:**

```
flutter build apk --debug -t lib/ai/debug_main.dart --dart-define=BENCH=tiers
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb logcat -s flutter | grep BENCH
```

The debug APK replaces the main app (same package); reinstall it afterwards with
`flutter build apk --debug` and `adb install -r`.

## Destination resolving on the iQOO 15, Sat 10 Oct 04:20

**Setup:** branch `ifzal/voice`, debug APK of `lib/ai/debug_main.dart` built with
`--dart-define=BENCH=both`. Gemma 4 E2B (`.litertlm`, D18 path) on flutter_edge_ai
2.1.1 + flutter_edge_ai_litertlm 1.10.1. **Backend: GPU.** Load 2468 ms, then warm-up
488 ms (other launches the same night: 2344 / 2439 ms load, 488–546 ms warm-up).

**Method:** the 40 requests in `lib/ai/benchmark.dart` for the demo map (Start, Food
counter, Stage side): 15 English, 10 Hindi or Hinglish, 15 that must return null. Each
request goes through the full `GemmaDestinationResolver` (PlaceMatcher first, then
Gemma, then the place-ID check). 3 rounds per mode, the two modes interleaved round by
round on one loaded model. There is a 2 s pause before each request, which stands in
for the gap between two spoken requests; the timing covers `resolve()` only.
Answer time = Gemma answers only (117 of 120 per mode; the other 3 are
"where is the canteen", answered by PlaceMatcher in 0 ms).

| | New chat per request (before) | One chat per map, history cleared (after) |
| --- | --- | --- |
| Correct | 96 / 120 | 96 / 120 |
| English | 33 / 45 | 33 / 45 |
| Hindi / Hinglish | 18 / 30 | 18 / 30 |
| Must be null | 45 / 45 | 45 / 45 |
| **False positives** | **0** | **0** |
| Wrong place | 0 | 0 |
| Missed (null for a real place) | 24 | 24 |
| Answer time, median | 2863 ms | **1173 ms** |
| Answer time, p90 | 4432 ms | **2363 ms** |
| Slowest | 6805 ms | 4807 ms |

Median answer time by group, after: English 1209 ms, Hindi 1225 ms, null 362 ms.

**Why it is faster:** opening a LiteRT-LM conversation with the `choose_place` tool takes
about 1650 ms (`createConversation (FFI): 1654ms` in logcat). LiteRT-LM has no reset, so
`clearHistory()` still opens a new conversation, but `GemmaService` now does that right
after an answer is returned, not when the next request arrives. Two requests less than
about 1.7 s apart would still wait for it. A different map, or a renamed place, makes a
new chat.

**Misses** (the same 8 requests, all 3 rounds, both modes; topK 1 is deterministic):
"lunch", "where is the show", "where are the speeches happening", "where's the main
event", "खाना कहाँ मिलेगा", "chai kahan milegi", "nashta kahan hai", "show kahan ho raha
hai". Gemma replied "none" to each one; none of them went to the wrong place.

**Prompt experiments** (reuse mode, 3 rounds each, no phrases hard-coded):

| System instruction | Correct | False positives | Median |
| --- | --- | --- | --- |
| Original (kept) | 96 / 120 | 0 | 1173 ms |
| v2: "each place is named for what is there", mentions Hinglish and eat / drink / watch | 90 / 120 | 0 | 497 ms |
| v3: original + "Hindi may be written in English letters" + "only when no listed place could reasonably offer it, say none" | 90 / 120 | 0 | 1232 ms |

Both rewrites lost "snacks", "where can I get coffee" or "I'm hungry", so the original
prompt stays. No must-be-null request returned a place in any run.

**Speech (same phone):** speech_to_text lists these on-device languages, so offline
recognisers exist for **en-IN: yes** and **hi-IN: yes**. The full list: cmn_CN, cmn_TW,
en_AU, en_CA, en_IN, en_IE, en_SG, en_GB, en_US, fr_BE, fr_CA, fr_FR, fr_CH, de_AT,
de_BE, de_DE, de_CH, hi_IN, id_ID, it_IT, it_CH, ja_JP, ko_KR, pl_PL, pt_BR, ru_RU,
es_ES, es_US, th_TH, tr_TR, vi_VN. The phone has two recognition services: Android System
Intelligence (on-device) and Google's TTS service.

**Correction (10 Oct 09:00):** that list is what the on-device recogniser *supports*, not
what is installed. Spoken test 1 (Ifzal): both buttons stopped after a moment, or showed
"Listening" and stopped after 2-3 s without hearing anything. Logcat with the new `SPEECH`
event log, en-IN and hi-IN: `listening` -> `notListening` -> `done` ->
`error_language_unavailable (permanent)` within 25-100 ms, so neither pack is installed
on the iQOO. The old code also lost that error (it came after `done`), and a 2 s
`pauseFor` that speech_to_text counts from the tap would cut off anyone slower than 2 s
to start speaking. Both are fixed in `lib/ai/speech_input.dart`; the packs must be
downloaded on the phone once (Settings > On-device speech recognition). Spoken test 2:
pending.

**Reproduce:**

```
flutter build apk --debug -t lib/ai/debug_main.dart --dart-define=BENCH=both
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb logcat -s flutter | grep BENCH
```

Keep the app in the foreground. While another app (for example vivo Remote Control) is
on top, the benchmark did not start (seen on 10 Oct).
