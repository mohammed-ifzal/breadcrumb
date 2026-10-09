# Demo: record a trail, then follow it back (works anywhere, no signs)

**We don't depend on the venue.** No taped sheets, no fixed map, no signs. The demo
happens in front of the judge, at our table, in under 2 minutes.

## The story (the pitch stays the same)

"Underground, in a hospital, in a car park: GPS stops working. Breadcrumb lets one walk
become a map. Watch."

## The 90-second table demo

1. **Record (30 s).** A teammate holds the phone and walks a loop around nearby tables:
   about 30 steps and 2 turns. The trail draws itself live on the phone, mirrored to the
   laptop over USB so the judge sees it big. Halfway, they tap **Mark place** and say
   "Food counter". At the far end, they mark "Stage side".
2. **Ask (10 s).** The judge says "Take me to where I can get coffee." Gemma, on the phone
   in aeroplane mode, picks **Food counter** from the marked places. Plain word matching
   can't do that.
3. **Follow (40 s).** The judge holds the phone. A big arrow, "about 12 steps", voice and
   vibration guide them, and the dot moves along the trail. At the corner, the turn
   snaps the dot onto the junction.
4. **Arrive (10 s).** "Food counter is here." Three short vibrations.

If there's no room to walk, record a 10-step L-shape beside the table and navigate it.

## Why this is a strong demo

- The judge sees a map being made from nothing, which shows the technical depth.
- The judge chooses the destination by voice, which shows the on-device AI.
- The judge walks it themselves, which proves it's real.
- It works the same on a stage, in a corridor or at our table.

## Bonus moments (only if built)

- **Scan to correct:** point the camera at any printed text on the trail, such as a team
  table card. If it was marked during recording, the dot snaps there.
- **Map desk:** the trail file goes to the laptop through Office Kit and is drawn big.
- **Real-world framing slide:** a car park ("find my car"), a hospital ("back to the
  ward"), a metro ("back to the exit").

## Pre-demo checklist

- [ ] Phone battery above 60%, Do Not Disturb on, brightness and volume up
- [ ] Aeroplane mode on
- [ ] Gemma warmed up; record screen open
- [ ] USB mirroring to the laptop working (Office Kit USB, or scrcpy)
- [ ] The loop route has been walked once in the last hour
- [ ] Backup video on the phone and the laptop

## Measuring accuracy (Saturday)

Record a 40-step loop, then navigate back to the start 10 times with 3 or more walkers.
Note how many steps off the end point is.

| Walk | Walker | Steps off at arrival | Notes |
| --- | --- | --- | --- |
| 1 | | | |

## Fallback ladder

| If this fails | Do this |
| --- | --- |
| Turn detection misses | Shorter loop with sharp 90° turns; or tap "I'm here" at the corner |
| Gemma won't load | Tap the destination from the list of marked places |
| Speech fails in noise | Tap the destination |
| Too loud | Earphones, plus vibration and the arrow |
| App crashes | Replay mode: a recorded trail plays through the same engine, labelled "Replay" |
| Everything fails | The 60-second backup video |
