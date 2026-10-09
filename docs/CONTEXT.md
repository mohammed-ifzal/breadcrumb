# Breadcrumb: project context

This is the distilled version of the planning conversations in Claude (Aug–Oct 2026).
It holds the background an agent or teammate needs. Rules for agents are in `AGENTS.md`.
Facts were checked on 8 Oct 2026; anything unconfirmed is marked UNVERIFIED.

## Team

- **Team Groza:** Ifzal (captain, presenter), Teammate 2 and Teammate 3. Final-year
  engineering students from Mangalore.
- **Credentials, in this order:**
  1. Won Best GitHub Repository at a national 24-hour hackathon (April 2026) for
     EmployMe, a hyperlocal job app for India's informal workforce.
  2. Shortlisted for the final funding round of the MITE First Ideathon.
  3. Shortlisted at the iQOO Bengaluru City Battle 2026 with Parity, an offline Flutter
     app that checked a physical assembly against its spec sheet using on-device OCR.

## What went wrong at the City Battle (don't repeat it)

- One person's Claude Code built everything while two teammates had nothing to do.
- There was no reliable demo at the end, OCR misread things, and we lost hours to trial
  and error.
- Top teams used on-device models such as Gemma. We didn't.
- We couldn't explain the idea crisply to mentors.

## The event

- **iQOO Hackathon 2026 Grand Finale:** Bengaluru, 9–11 Oct 2026, Friday evening to
  Sunday evening, 48 hours. Organised by iQOO with Reskilll. The hour-by-hour schedule
  is not published.
- **Track:** Mobility (navigation, EVs, public transport, parking, travel experiences).
  This track is new at the Finale, so no City Battle team has built for it.
- **Judging:**

  | Criterion | Weight | Measured by |
  | --- | --- | --- |
  | End product | 30% | Jury |
  | Novelty and impact | 20% | Jury |
  | Creative phone use (camera, voice, on-device AI) | 15% | HackTracker device telemetry |
  | Technical depth | 15% | Jury |
  | Office Kit usage | 10% | HackTracker device telemetry |
  | Demo and presentation | 10% | Jury |

  HackTracker records actual phone and Office Kit usage, so these points can't be
  pitched; they are earned by working on the phone.
- **Red Light / Green Light:**
  - At the City Battles, 55% of build time was Red Light (phone only, via Office Kit)
    and 45% was Green Light (laptop allowed).
  - The Finale promises an "extended Red/Green format"; the split is not published.
  - An organiser blog says the laptop is "CLOSED as a build machine" in Red Light, but
    Office Kit includes Remote PC. Ask the organisers in hour 1.
- **Demo:** the demo must run on the iQOO phone. A local or open-source model earns
  extra credit.
- **Original work:** at the City Battle, teams built from a clean repo started at the
  event (UNVERIFIED as official wording for the Finale). Libraries are fine with
  credit. These planning docs were written before the event and contain no app code.
- **Device:** a loaner iQOO 15 is handed over at check-in. It stays in the venue.
- **City Battle schedule, as a guide only:** evaluation round 1 on Saturday evening,
  round 2 on Sunday morning, then Top 10 pitches. The Finale's checkpoints are unknown.

## Why Breadcrumb (and what we rejected)

| Rejected idea | Why |
| --- | --- |
| Nodu (bus route board reader) | Too simple |
| Setu (offline disaster mesh) | Too close to Hush, a Hyderabad entry |
| Glint (hidden-camera finder) | Too hard to demo reliably |
| Headroom (crowd crush warning) | Felt weak |
| Tripwire (scam call guard) | Google already ships it on Pixel |
| Bystander (crash first aid) | Doesn't fit the Mobility track |

Breadcrumb fits Mobility exactly, is phone-only by nature, and has a demo the judge
performs.

Known winners:

- Bengaluru: Tokito Companion, an AI interface for debugging physical circuits.
- Pune: Jammify and RightPosture.
- Hyderabad: Hush, an offline rescue listening mesh. That it won is UNVERIFIED.

## The problem (facts with sources)

- **Majestic metro interchange** carries 1.2–1.5 lakh passengers a day. Its signage is
  confusing enough that in April 2025 BMRCL floated tenders to redesign wayfinding.
  (newskarnataka.com, 19 Apr 2025)
- **Underground and inside large buildings** there is no GPS fix and often no mobile
  signal.
- **Waymap (UK)** runs phone-sensor navigation in all 98 Washington DC metro stations.
  It claims about 1 m accuracy (company claim, not independently tested). Stations were
  mapped with lidar plus the transit authority's maps, and authorities pay a mapping
  fee and a subscription. (govtech.com, zeroproject.org)
- **Backtracking (arXiv 2401.08021, 2024)** records routes as step counts joined by
  90-degree turns, the same idea as our recorder. It was tested with 7 blind
  participants; its code was not released. Cite it as validation.

## Pitch lines

- **30 seconds:** see `docs/PITCH.md`.
- **The one-sentence differentiator:** "Waymap proved this works with professional
  mapping; we make mapping one walk with one phone."
- **Engineering principle:** "The model perceives. Tested code decides. It can never
  invent a route."

## Technical facts (checked 8 Oct 2026)

**Gemma 4 E2B**

- Released 2 Apr 2026 under Apache-2.0.
- The `.litertlm` file is 2,583 MB
  (huggingface.co/litert-community/gemma-4-E2B-it-litert-lm).
- On the Snapdragon 8 Elite Gen 5 (in a Galaxy S26 Ultra), GPU decode runs at about
  52 tokens/s with 0.3 s to the first token. Image processing time is UNVERIFIED.
- Startup can take about 10 s, so warm it at app launch.

**`flutter_edge_ai` 2.1.1** (published 8 Oct 2026, formerly `flutter_gemma`)

- Supports Gemma 4, `.litertlm`, image and audio input, and function calling.
- Requires minSdk 30 and arm64 only.
- Install `.litertlm` files with `ModelFileType.litertlm`.
- No regex or JSON-constrained output, so validate every answer.
- LiteRT-LM GPU on Android needs `<uses-native-library>` entries for `libOpenCL.so` and
  `libvndksupport.so` (check the LiteRT-LM Android docs at hour 0).

**ML Kit text recognition** (`google_mlkit_text_recognition` 0.17.1)

- Works offline with the model bundled.
- Reads Latin and, with the add-on, Devanagari. It does **not** read Kannada.

**Sensors**

- Android's step detector has latency below 2 s. The step counter can lag up to 10 s.
  Both need the `ACTIVITY_RECOGNITION` permission.
- `sensors_plus` 7.1.1 has an accelerometer, gyroscope, magnetometer and barometer, but
  no step or rotation-vector sensors.
- `pedometer` gives no per-step stream, so don't use it.
- So we use a small Kotlin EventChannel.

**Speech** (`speech_to_text` 7.5.0)

- `onDevice: true` uses the offline recogniser if the phone has one; otherwise it fails.
- Availability on the iQOO 15 is UNVERIFIED.

**iQOO 15**

- Snapdragon 8 Elite Gen 5, Adreno 840 GPU, 12 or 16 GB RAM.
- OriginOS 6 on Android 16, with a gyroscope, accelerometer and e-compass.
- Spec sheets list no step detector (UNVERIFIED either way).

**Office Kit**

- Remote PC: control the laptop from the phone with a virtual touchpad and the phone
  keyboard. It works across networks, but the PC must stay awake.
- Also: mirror the phone to the PC, unlimited file transfer, a shared clipboard.
- The PC app needs x86 Windows 10+ or macOS 10.14.6+.
- **There is no developer API.**

## Claims we never make

- NPU acceleration (no Gemma 4 NPU build exists for this chip).
- Any programmatic Office Kit integration.
- Accuracy better than Waymap's.
- Anything working that we didn't show working.
- The "236 m with under 3 m drift" figure from an AI summary, which nobody verified.
