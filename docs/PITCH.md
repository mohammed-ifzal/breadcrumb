# Pitch

## 30 seconds (everyone memorises this)

"GPS gets you to the building. Then it stops working. Majestic metro moves 1.2 to 1.5
lakh people a day through a station so confusing that BMRCL has tendered for an agency to
redesign its signage. Underground there is no GPS, often no signal, and signs only help
if you can see them and read the language. Breadcrumb fixes this with nothing but the
phone. One volunteer walks the station once, and the phone records every step, turn and
sign. After that, anyone can say 'take me to Platform 2' and get voice and vibration
directions, in aeroplane mode. On-device AI reads the signs, and Gemma 4 on the phone
understands the request. Plain, tested code does the routing, so it can never invent a route. Pick a
destination and try it."

## 10 seconds

"Turn-by-turn navigation inside buildings where GPS stops working. One person walks the
building once; after that, anyone can be guided by voice, with no internet."

## 3 minutes

1. **Problem, 20 s.** Your first time changing lines at Majestic: 1.2–1.5 lakh people a
   day, no GPS underground, signs you may not be able to read.
2. **Solution, 20 s.** One volunteer walks the station once; after that, anyone gets
   voice directions, offline.
3. **Live demo, 90 s.** The judge walks (see `DEMO.md`).
4. **How it works, 30 s.**
   - Three techniques: step and turn tracking, a map of corridors that position can't
     leave, and signs that snap it back.
   - On-device ML Kit reads the signs; Gemma 4 on the phone understands requests in
     English and Hindi.
   - Tested code makes every decision, so it can't invent a route.
5. **Why phone and Office Kit, 10 s.** No infrastructure and no signal needed. Maps move
   to a laptop through Office Kit for editing.
6. **Close, 10 s.** Waymap proved this works in all 98 Washington metro stations with
   professional mapping. We make it one walk with one phone.

## "What did you build?" (one sentence each; fill in on Saturday)

- **Ifzal:** "I built the navigation engine: routing, position tracking and place
  matching, plus the Gemma integration."
- **Teammate 2:** "I built the sensing: step and turn detection from the phone's
  sensors, the map recorder and the replay tests."
- **Teammate 3:** "I built the app: voice and vibration guidance, sign reading with the
  camera, and the Office Kit map desk."

## Q&A bank

| Question | Answer |
| --- | --- |
| Doesn't Google Maps do indoors? | Only where venue owners upload floor plans, and it needs a location signal. We need neither. (Check the current state of Google indoor maps before you say this.) |
| Waymap already exists. | Yes, and it proves the method works. They map with lidar and charge transit authorities; we map with one walk on any phone. We don't claim better accuracy. |
| How accurate is it? | Our measured median and worst case (see `DEMO.md`). Drift resets at every turn and every sign. |
| A different walker has a different stride. | Turns and signs re-anchor the position, and instructions say "about". Mention a stride calibration walk only if we built it. |
| Why use an LLM at all? | Messy, multilingual requests ("where's the loo", Hindi) that keyword matching misses. It can only pick a place that exists on the map. |
| Why on-device? | Underground there is no signal. It's also private and has no network delay. |
| Stairs, lifts, several floors? | Version 1 is one floor. Floors are next. |
| Who keeps maps up to date? | Station staff or volunteers re-walk a changed corridor. A map is a small file shared offline. |
| Can a blind user point a camera at signs? | They don't need to. Turn snapping, voice and vibration handle most drift; sign scanning is for sighted users and helpers. |
| Who pays? | Like Waymap: stations and hospitals pay for mapping support; the app is free for users. |
| What's mocked? | Nothing in the demo path. Replay mode exists and is labelled on screen. |
| Isn't this the 2024 Backtracking research? | It uses the same recording idea, which validates us. We add sign re-anchoring, voice in Indian languages and on-device AI. |
| What did each of you build? | The three sentences above. |
