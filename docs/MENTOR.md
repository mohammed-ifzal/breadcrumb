# Mentor round, Sat 10 Oct 10:00

The mentor's questions and our answers, then the feedback we got. Use these answers in
the Q&A drill (`PITCH.md`).

## Questions and answers

**Where am I? How does the app know where I start?**
The walk starts at a known place: where the trail was recorded, or a place the user
picks. From there the app tracks passively: steps and turns from the phone's own
sensors, and every corner on the trail is a snap point that corrects drift. No scanning
is needed at any point.

**Can you trust OCR on a sign?**
Sign scanning is an optional correction, never required. A reading counts only if it
matches a place on the map (`PlaceMatcher`); anything else, including a misread, is
ignored. OCR never chooses a position on its own.

**Floor plans already exist. Why record a trail?**
A floor plan shows where things are, not how to get there from where you stand. Most
Indian metro stations and hospitals have no digital indoor map at all. Ours needs one
walk by one person.

**Which floor am I on?**
Where the phone has a barometer, the floor change can be detected. The iQOO 15 has none,
so on this phone it is one tap. Routing across floors works (D24): "Take the escalator
to Floor N."

**Scanning is friction.**
Agreed, so it is never required. Steps, turns and corner snapping do the work.

**What is the load on the device?**
The step and motion sensors cost almost nothing. Gemma runs only on demand, about 1 s
per request on the GPU. The camera runs only on demand. AR guidance is only a possible
future "last 20 metres" mode. Measured numbers go in `BENCHMARKS.md` (coming).

## Feedback

- The map looked sloppy.
- Record a clean map of this floor.
- Show the full floor plan and the route on it.
