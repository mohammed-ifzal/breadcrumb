# Benchmarks

Measured on the phone, never estimated. Newest run at the top.

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
