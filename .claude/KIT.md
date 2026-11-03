# Kit conventions

This project runs on TB Claude Kit. The session-start hook loads this file into every session, so it
is current in every linked project the moment the kit changes. Project specifics live in CLAUDE.md.

## Brain

All project knowledge lives in `cowork/brain/BRAIN.db` (SQLite, FTS5). `/brain` is the interface;
`cowork/brain/USAGE.md` has the schema and queries.

- **The DB is the only copy.** There is no markdown export: query the DB, or run `/brain` for a view.
- **Entry types:** note, decision, question, insight, task, milestone.
- **Tiers** are computed, never set by hand: hot (focus, plan momentum) > warm (important or recent) >
  cold (active) > archived (done).
- **Tags** are normalized on every write: comma-split, trimmed, lowercase, sorted, deduped.
- **Decisions are permanent.** A changed decision is a new entry that supersedes the old one.
- **Plans** are numbered files in `cowork/plans/`, linked to tasks via `meta.plan_id` ('003', never 3).
  **Research** is numbered folders in `cowork/research/`, indexed in the brain.
- **BRAIN.db is git-ignored.** Projects that want it in git list it under `sqlite_tracking` in
  `.claude/kit.json`; `/commit` then writes readable NDJSON snapshots beside it, and the hook rebuilds
  a missing DB from them.

## Mantra

The mantra is your own note to the next session: patterns, non-obvious knowledge, tricky areas, current
momentum and working assumptions that the rest of CLAUDE.md does not cover. It lives in CLAUDE.md,
between the line `<!-- BEGIN:mantra -->` and the line `<!-- END:mantra -->`, and nowhere else.

- Edit it in place with the Edit tool. Match the WHOLE marker lines, never the first place the marker
  text appears: prose may quote it.
- **Budget: about 4,000 characters.** Rewrite, never append. Cut what is stale, what CLAUDE.md or the
  code now says, and anything a fresh session would rediscover in a minute.
- Not a changelog or status report. Git history is the mantra's history.

## Standing rules

- **Mantra review at session start.** When the hook lists entries since the last session, check them
  against the mantra. If they surfaced something a fresh session would need, update the mantra before
  starting work, without asking. Skip it if the work was routine.
- **Compound lesson.** Before wrapping up a substantive session, ask whether a reusable lesson emerged.
  If one did, write it as a brain insight tagged `lesson`: one sentence stating the rule, then Why and
  How to apply. If nothing novel was learned, skip it.
- **Long-running jobs.** Whenever you start a background job you expect to run 5+ minutes (Bash
  run_in_background, nohup, a long script or batch), invoke the /pbar skill immediately after launching
  it, without being asked. Hand back its command as a single absolute path in its own fenced code
  block, as the last thing in your reply. Re-print that same block whenever the user might need to
  restart the display: every status update, restart, crash, resume, or turn that ends with the job
  still running.
- **Project rules.** Every skill reads `rules.<skill>` from `.claude/kit.json` and applies it.
