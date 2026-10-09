# Task board

The captain ticks tasks at sync points, and only when the "done when" check passes on
the iQOO phone. **[RL]** = suits Red Light (phone only).
**Demo = record a trail, mark places, navigate back** (see `DEMO.md`).

## Hour 0 (now)

- [ ] **Ifzal:** hour-0 commit per `docs/SETUP.md` (project, shared debug key, packages,
  manifest, contracts, tuning, fakes, status files, CI). Done when CI is green and the
  APK installs on the iQOO.
- [ ] **Ifzal:** Gemma file onto the iQOO; record the path in `DECISIONS.md`.
- [ ] **All:** clone the repo, pair Office Kit, laptops never sleep.
- [ ] **Ifzal:** ask the organisers the questions in `DECISIONS.md`.

## Tonight: spikes, then the core loop

- [ ] **Ifzal:** core engine (`RoutePlanner`, `PlaceMatcher`, `Tracker`, `Guide`) with tests,
  including navigating back along a recorded trail.
- [ ] **Teammate 2:** sensing spike. Done when 20 real steps show as 18–22, and left and
  right turns show as about +90 and −90.
- [ ] **Teammate 3:** app shell, permissions, voice and vibration, and `trail_view.dart`
  drawing a fake map with a moving dot.
- [ ] **Teammate 2:** `MapBuilder` + record screen: start, live trail drawing (using T3's
  `TrailView`), "Mark place" with a typed name, stop and save. Done when a 30-step loop
  draws roughly the right shape.
- [ ] **Ifzal + Teammate 3:** navigate screen: pick a marked place, then arrow, steps,
  voice, vibration and the dot moving on `TrailView`. Done when someone records a loop
  and is guided back to the start.
- [ ] **G2 (Sat 8 am) [RL]:** a person who didn't build it records a loop and navigates
  back without help.

## Saturday

- [ ] **Ifzal:** Gemma `DestinationResolver` for spoken requests, with the speech input.
- [ ] **Teammate 2 [RL]:** 10 traced test walks; replay tests; tune turn thresholds.
- [ ] **Teammate 3:** replay mode labelled "Replay"; scan any printed text to anchor
  (bonus); export the trail for Office Kit.
- [ ] **Teammate 3 [RL]:** first backup video.
- [ ] **Ifzal [RL]:** pitch and Q&A drill.
- [ ] **G3 (Sat 6 pm):** feature cut.

## Saturday night to Sunday

- [ ] **Teammate 3:** map desk (view only) on the laptop.
- [ ] **All:** no crash on permission refused, no step detector, model missing, no
  speech recogniser.
- [ ] **Ifzal:** README with architecture, credits, who built what, and the note that
  planning docs were written before the event.
- [ ] **G4 (Sun 6 am):** code freeze. Then rehearse: 5 pitches, 10 demo runs.
