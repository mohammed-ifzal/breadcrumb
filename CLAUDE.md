@AGENTS.md

## Claude Code notes (Ifzal, captain)

- Use Sonnet by default. Use `/model opusplan` for design work (Opus plans, Sonnet
  executes). Use Opus only for hard debugging. Don't use Fable here: on Pro it bills
  outside plan limits.
- Use plan mode (`Shift+Tab`) for anything that touches more than two files. Edit the
  plan before approving it.
- One task per session. When it's done, add the handoff at the top of
  `docs/status/ifzal.md`, then `/clear`.
- Use subagents for exploring package docs or reading many files, so the main context
  stays clean.
- To review a teammate's pull request before merging, use a fresh subagent: "Review
  this diff against `docs/CONTRACTS.md` and `AGENTS.md`. Report only contract breaks,
  ownership violations or missing tests, not style."
- Before every Red Light, start `claude remote-control` in the repo so the session can
  be steered from the Claude app. It needs the Pro login; it does not work with
  OpenRouter or any `ANTHROPIC_BASE_URL` gateway.
- When compacting, always keep the list of modified files, failing tests, the next
  step, and any decision not yet written to `docs/DECISIONS.md`.
