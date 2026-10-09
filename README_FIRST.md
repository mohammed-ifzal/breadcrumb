# Breadcrumb starter pack: read me first

These are **planning documents only, with no app code**, written before the event. The
CI workflow in `docs/SETUP.md` is standard GitHub Actions boilerplate. They
let three people and three AI tools start in hour 0 with the same context.

## What's inside

| File | For |
| --- | --- |
| `AGENTS.md` | Instructions every AI tool reads automatically (Codex, Antigravity, Jules) |
| `CLAUDE.md` | Claude Code: imports `AGENTS.md` and adds Claude-only notes |
| `docs/CONTEXT.md` | Everything decided in our planning chats: event, rules, scoring, facts, lessons |
| `docs/CONTRACTS.md` | The data shapes and interfaces that let us build in parallel |
| `docs/TASKS.md` | The task board, with a "done when" check for each task |
| `docs/status/` | One handoff log per person, so nobody's edits collide |
| `docs/DECISIONS.md` | Decisions, plus blanks for the organisers' answers and spike results |
| `docs/DEMO.md` | Demo script, props, measurement table, fallback ladder |
| `docs/PITCH.md` | 30-second, 10-second and 3-minute pitch, plus the Q&A bank |
| `docs/PROMPTS.md` | The first prompts for each person's agent |
| `docs/SETUP.md` | Tonight's laptop setup, remote control, Office Kit, hour-0 steps, CI |

## How to use it

1. **Tonight:** replace "Teammate 2" and "Teammate 3" with real names everywhere (find
   and replace). Everyone reads `docs/CONTEXT.md` and `docs/PITCH.md`, then does
   `docs/SETUP.md`.
2. **Hour 0:** the captain copies this folder into the new repo, commits it as
   "Planning docs prepared before the event (no app code)", and pushes.
3. **Every session:** start each agent with the first prompt in `docs/PROMPTS.md`.
4. **Disclosure:** mention in the README that these planning docs were prepared before
   the event.
