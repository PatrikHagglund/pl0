## Ledger

Maintain a single Ledger for this workspace in
`.agents/LEDGER.md`. The ledger is the canonical session briefing designed to
survive context compaction; do not rely on earlier chat text unless it’s
reflected in the ledger.

### How it works
- At the start of every assistant turn: read `LEDGER.md`. Update it before and after the work.
- Update `LEDGER.md` whenever any of these change: 
  decisions, constraints/assumptions, progress state (Done/Now/Next), or
  important tool outcomes.
  - Only erase prior ledger content if there is a strong need; normally preserve existing facts and append or
    minimally edit to reflect new information.
- Also `README.md` should be read and continually updated. It contains guidance
  for both agents and humans.
- Keep it short and stable: facts only, no transcripts. Prefer bullets. Mark
  uncertainty as `UNCONFIRMED` (never guess).
- If you notice missing recall or a compaction/summary event: refresh/rebuild
  the ledger from visible context, mark gaps `UNCONFIRMED`, ask up to 1–3
  targeted questions, then continue.

### In replies
- Begin with a brief “Ledger Snapshot” (Now/Next + Open
  Questions). Print the full ledger only when it materially changes or when
  the user asks.

### `LEDGER.md` format (keep headings)
- Goal:
- Key decisions:
- Additional decisions/constraints/assumptions
- Open questions (UNCONFIRMED if needed):
- State:
- Next:
- Now:
  - Working set (current focus only; replace/prune as "Now" changes):
- Done (prune when exceeding 30 items):
