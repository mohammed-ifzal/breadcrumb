# Pitch

## 30 seconds (everyone memorises this)

"GPS gets you to the building. Then it stops working. Majestic metro moves 1.2 to 1.5
lakh people a day through a station so confusing that BMRCL has tendered for an agency to
redesign its signage. Underground, in a hospital or in a car park there is no GPS and
often no signal. Breadcrumb needs nothing but the phone. Walk a route once and the phone
draws the trail from your steps and turns; tap to mark places on the way. After that,
anyone can say 'find my car', 'back to the ward' or 'back to the exit' and be guided
there by arrow, voice and vibration, in aeroplane mode. Gemma 4 on the phone understands
the request. The AI perceives; tested code decides, so it can never invent a route.
Watch us map this room, then tell it where you want to go."

## 10 seconds

"Turn-by-turn navigation inside buildings where GPS stops working. One person walks the
building once; after that, anyone can be guided by voice, with no internet."

## 3 minutes

1. **Problem, 20 s.** Your first time changing lines at Majestic: 1.2–1.5 lakh people a
   day, no GPS underground, signs you may not be able to read.
2. **Solution, 20 s.** One volunteer walks the station once; after that, anyone gets
   voice directions, offline.
3. **Live demo, 90 s** (see `DEMO.md`). A teammate walks a loop around our table; the
   trail draws itself live, mirrored to the laptop. They tap **Mark place** at "Food
   counter" and "Stage side". The judge says "take me to where I can get coffee", Gemma
   picks Food counter, and the judge follows the arrow, voice and vibration while the
   dot moves along the trail. Use cases: a car park ("find my car"), a hospital ("back
   to the ward"), a metro ("back to the exit").
4. **How it works, 30 s.**
   - Steps and turns become a trail of corridors and junctions; position can't leave it,
     and every turn snaps it to the next junction.
   - Gemma 4 on the phone maps free-form requests (English and Hindi) to a marked place.
     Scanning printed text is a bonus anchor, not required.
   - The AI perceives; tested code decides. It can't invent a route.
5. **Why phone and Office Kit, 10 s.** No infrastructure and no signal needed. Maps move
   to a laptop through Office Kit for editing.
6. **Close, 10 s.** Waymap proved this works in all 98 Washington metro stations with
   professional mapping. We make it one walk with one phone.

## "What did you build?" (one sentence each; fill in on Saturday)

- **Ifzal:** "I built the navigation engine: routing, position tracking and place
  matching, plus the Gemma integration."
- **Teammate 2:** "I built the sensing: step and turn detection from the phone's
  sensors, the map recorder and the replay tests."
- **Teammate 3:** "I built the app: the live trail view, voice and vibration guidance,
  and the Office Kit map desk."

## Q&A bank

| Question | Answer |
| --- | --- |
| Doesn't Google Maps do indoors? | Only where venue owners upload floor plans, and it needs a location signal. We need neither. (Check the current state of Google indoor maps before you say this.) |
| Waymap already exists. | Yes, and it proves the method works. They map with lidar and charge transit authorities; we map with one walk on any phone. We don't claim better accuracy. |
| How accurate is it? | Our measured median and worst case (see `DEMO.md`). Drift resets at every turn, and at a scanned sign if that bonus is built. |
| A different walker has a different stride. | Turns and signs re-anchor the position, and instructions say "about". Mention a stride calibration walk only if we built it. |
| Why use an LLM at all? | Messy, multilingual requests ("where's the loo", Hindi) that keyword matching misses. It can only pick a place that exists on the map. |
| Why on-device? | Underground there is no signal. It's also private and has no network delay. |
| Stairs, lifts, several floors? | Version 1 is one floor. Floors are next. |
| Who keeps maps up to date? | Station staff or volunteers re-walk a changed corridor. A map is a small file shared offline. |
| Can a blind user point a camera at signs? | They don't need to. Turn snapping, voice and vibration handle most drift; sign scanning is for sighted users and helpers. |
| Who pays? | Like Waymap: stations and hospitals pay for mapping support; the app is free for users. |
| What's mocked? | Nothing in the demo path. Replay mode exists and is labelled on screen. |
| Isn't this the 2024 Backtracking research? | It uses the same recording idea, which validates us. We add a live trail view, on-device AI for free-form requests, voice in Indian languages, and sign re-anchoring as a bonus. |
| What did each of you build? | The three sentences above. |
