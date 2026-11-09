# Installing and configuring

Modes, adoption of new kit files, memory, `kit.json`, and what a project holds after install.

## Two ways to install

The kit can either **travel with your repo** or **live outside it**. This is the main thing to
understand before adopting it across several projects.

| | **outside repo** (default) | **inside repo** |
|---|---|---|
| Kit files are | symlinks into `~/.claude-kit` | real files in your project |
| Git | meant to stay out of git — the installer prints the `.gitignore` lines, and [never writes them](#gitignore-is-yours) | tracked — travel with the repo |
| Updating | instant; edit the kit once, every project sees it. New kit files are [adopted on next session start](#automatic-adoption-of-new-kit-files) | re-run `install.sh`, with drift detection |
| Needs the kit present? | yes | only for the kit's own scripts in `~/.claude-kit/scripts/` (`oprun`, `sqlite-sidecar.sh`, `kit-chrome`, `claude-switcher`) |

**Choose with one question: does a machine without your kit checkout need this repo to work?**
If yes — a repo you hand to someone else, a cloud session, CI — use `inside`. Otherwise `outside`,
and stop thinking about propagation entirely.

```bash
bash ~/.claude-kit/install.sh                  # uses the mode in kit.json (default: outside)
bash ~/.claude-kit/install.sh --mode inside    # convert to vendored files
bash ~/.claude-kit/install.sh --mode outside   # convert back to symlinks
bash ~/.claude-kit/install.sh --dry-run        # report what would change, touch nothing
bash ~/.claude-kit/install.sh --yes            # auto-update drifted files, enable integrations
bash ~/.claude-kit/install.sh --replace        # outside mode: replace occupied paths with links (commit first)
bash ~/.claude-kit/install.sh --help
```

**Optional integrations.** An interactive run offers three: the Exa and Brave Search MCP servers
(it asks for the Brave key) and the Cloudflare plugin with its MCP servers. Saying yes adds
entries to `.mcp.json` and `.claude/settings.json`. With `--yes`, or when no one is at the
keyboard (an agent running it), all three are enabled without asking and drifted files are
reported with their diffs, not updated.

**Writing rules (once a machine).** An interactive run on a machine with no writing rules set up asks
for the folder holding your own writing sets and links it as `~/.claude/writing`; Enter for none is
remembered and never asked again. See [Writing rules](customization.md#writing-rules).

Conversion is lossless in both directions.

**Adopting an existing project.** Paths already holding real files are reported as `[occupied]`
and left alone — the installer never silently deletes your work. Content that's byte-identical to
the kit converts automatically. For anything that genuinely differs, either add it to `fork` (see
below) or commit it and re-run with `--replace`.

**On another machine.** Clone the kit anywhere, run `ln -s <path> ~/.claude-kit`, then
`bash ~/.claude-kit/install.sh` in each project. Nothing in any repo hardcodes a checkout location.
The installer finds the kit by `$TB_CLAUDE_KIT`, then `kitPath` in `kit.json`, then `~/.claude-kit`,
then the folder the script itself is in.

### Automatic adoption of new kit files

In outside mode, kit files are symlinks — so editing a skill in the kit is live everywhere
immediately. What never followed automatically was a *new* file: a skill that didn't exist when
you last installed needs a symlink and a `.gitignore` line, which meant re-running `install.sh`
in every project each time the kit grew.

The session-start hook now does that itself. On every session it compares the project against the
kit and links anything missing, and adds the new path to the kit's managed `.gitignore` block when
the project has one (see below). New skills are usable in the session that adopts them, and you're
told what happened:

```
🧰 Kit sync: linked .claude/skills/parse and updated .gitignore. Available this session.
```

It finds the kit without any configuration: in outside mode the hook is *itself* a symlink into
the kit, so it resolves its own path. No `$TB_CLAUDE_KIT`, no `kitPath`, nothing to keep in sync.
The list of what to adopt is every skill folder, agent and hook in the kit, plus the fixed paths
in `.claude/kit-manifest.txt` — a hand-maintained list that `install.sh` reads too, so both sides
work from one list. A new skill reaches every project the next time a session starts there.

**It only ever adds.** A symlink whose target disappeared upstream is reported, never deleted —
the hook can't tell "removed from the kit" from "checkout mid-rebase" or "external volume not
mounted", and deleting on an ambiguous signal is how you lose work. Removal is yours to do by
hand: delete the dangling link. `install.sh` never removes anything either; it reports leftovers.
The hook also heals a kit link that's missing its line in the managed `.gitignore` block, the
drift that otherwise shows up as a mystery untracked file.

It stays out of the way where it should: `fork` and `exclude` are honored, forked paths are never
given an ignore line, inside-mode projects are skipped entirely (their hook is a real file, so it
self-disables), and a missing or unparseable `kit.json` makes it bail rather than guess.

Re-running `install.sh` is still what you want for converting modes, updating project-owned
scaffolding, and drift detection.

### `.gitignore` is yours

`install.sh` never writes `.gitignore`. It used to, and one project found seventeen tracked skill
paths silently dropped from its index by an installer it ran to add one skill. Whether kit links
belong in git is a project decision, so the installer prints the lines an outside-mode project
needs and leaves the file alone.

To have the hook keep them current, put those lines between two marker lines,
`# BEGIN:tb-claude-kit` and `# END:tb-claude-kit`. From then on every newly adopted kit file gets
its line added inside that block. Without the block, a newly linked skill shows up as an
untracked file until you ignore it.

### Claude's memories live in the repo

Claude Code's auto-memory normally sits in the machine's config folder
(`~/.claude/projects/<path>/memory/`), in no repo, so it is lost with the machine and never
reaches your other machines. The kit keeps it in the project instead, at **`.claude/memory/`**,
committed and pushed with everything else:

- **The setting.** `.claude/settings.local.json` gets `autoMemoryDirectory`, pointing at that
  folder. That file is per machine and ignored by git. Claude Code honours the key there for a
  trusted project, and ignores it in the checked-in `settings.json`.
- **The migration.** Memories already in the config folder are copied across without overwriting
  anything. The old folder is kept, renamed `memory.moved-<time>`, beside a link to the new one.
  The config folder is `$CLAUDE_CONFIG_DIR` when you route accounts per folder, and `~/.claude`
  otherwise.
- **When it runs.** `install.sh` sets it up in both modes. The session-start hook adopts it for an
  outside-mode project on its next session and tells you in one line:
  `🧠 Memory: moved 12 memories into .claude/memory — commit them.` When everything is already
  in place it costs a few milliseconds and says nothing.
- **Public repos are left alone.** Memories hold personal notes, so when the repo's origin is a
  **public** GitHub repo, the kit sets nothing up and says why. It checks once, through `gh`, with
  a 5-second limit; if `gh` is missing or cannot answer, the repo is treated as not public. Opt in
  with `"memory": { "inRepo": true }`.
- **Turning it off.** Set `"memory": { "inRepo": false }`. That stops enforcing it and never undoes
  a setup; `install.sh` says what to remove by hand.
- **Cases it skips:**
  - a linked worktree, which shares its main checkout's memory;
  - a tracked `settings.local.json`, since it would carry this machine's path;
  - an inside-mode repo at session start (a collaborator's session should not move their memories
    into a shared repo — `install.sh` is the explicit way).

---

## Your own config: one private repo, every machine

The kit holds no one's configuration. Yours goes in a **private repo of your own**, holding config
and working state but no code. `scripts/kit-config` links it into place, so a new machine is two
clones and one command:

```bash
git clone https://github.com/<you>/tb-claude-kit.git ~/dev/tb-claude-kit       # or the public kit
git clone https://github.com/<you>/my-claude-config.git ~/dev/my-claude-config  # private
bash ~/dev/tb-claude-kit/install.sh --config ~/dev/my-claude-config
```

`--config` links `~/.claude-kit` to the kit when that link doesn't exist yet, then runs
`kit-config link`. It sets up the machine and touches no project. Each project is still installed
with `install.sh` from inside it, as above.

**What goes in it.** The repo's `kit-config.json` lists every entry and where it is linked:

```json
{
  "links": [
    {"from": "writing",   "to": "~/.claude/writing"},
    {"from": "disk.json", "to": "~/.config/claude-kit/disk.json"}
  ],
  "settings": "settings.fragment.json"
}
```

- **`~`** is your home folder. **`{kit}`** is the kit checkout. **`{kit-memory}`** is Claude Code's
  memory folder for the kit checkout.
- **Typical entries:**
  - your writing rules, `~/.claude/writing`;
  - your drive map, `~/.config/claude-kit/disk.json` (`/disk setup` writes it);
  - if you develop the kit itself, its working state: `{kit}/.claude/kit.json`, `{kit}/cowork/plans`,
    `{kit}/cowork/research` and `{kit}/cowork/brain/BRAIN.airsqlite` (the brain's snapshots).
    The kit's `.gitignore` already ignores all four, so nothing of yours can be committed to the kit.
- **`settings.fragment.json`** is merged into `~/.claude/settings.json`, never linked, because
  Claude Code rewrites that file. Hooks and permission rules are added when missing, and nothing of
  yours is removed. A `~/` in it becomes your home folder.

**Day to day:**
- `kit-config status` shows each entry as linked, missing or occupied.
- `kit-config adopt <from> <to>` moves an existing file or folder into the repo and links it back.
- `kit-config save` snapshots the kit's brain, then commits and pushes the repo.
- `link` never overwrites a real file: it reports `OCCUPIED` and leaves it alone.

Client projects keep their own brains and plans in their own repos (`sqlite_tracking`). The config
repo is for what belongs to you and the machine, not to any one project.

---

## Configuration — `.claude/kit.json`

One file per project holds both its mode and its customizations. Every key is optional; skills
fall back to sensible defaults when the file or a key is missing. See
[`kit.example.json`](kit.example.json) for the annotated full reference.

```json
{
  "kitVersion": 1,
  "mode": "outside",
  "fork": [],
  "exclude": [],

  "kill": {
    "ports": [3000, 5173, 8787],
    "portRanges": [[9615, 9634]],
    "patterns": ["my-custom-watcher"],
    "scopeToProjectPath": true
  },
  "commit": { "author": "Jane Dev <jane@example.com>" },
  "plan":     { "roots": ["cowork/plans", "cowork/projects/*/plans"],
                "issues": { "publish": "ahead", "assignee": "jane-dev", "neverLabels": ["agent-queue"] } },
  "research": { "roots": ["cowork/research"] },
  "swarm":    { "maxAgents": 6, "checks": ["npm run check"] },
  "memory":   { "inRepo": null },

  "rules": {
    "push": "If the post-commit hook reports undeployed changes, ask before pushing."
  }
}
```

Other keys are documented with the skill that reads them: `plan.issues` under [Plan](plan-and-swarm.md#plan-plan),
`swarm.*` under [Swarm](plan-and-swarm.md#swarm-swarm), `wiki.*` under [Wiki](skills.md#wiki-wiki), `secrets` under
[Secrets](skills.md#secrets-1password). Smaller ones:

- **`clearCache`** — `projectRoots` (where your projects live, default `~/dev`) and `staleDays`
  (default 30), for `/clear-cache`'s deep tier. A machine-wide `projectRoots` in `/disk`'s
  `~/.config/claude-kit/disk.json` takes precedence. `/disk` keeps all its settings in that file,
  because drives belong to the machine, not to a project.
- **`prune`** — `staleDays` (default 14) and `keep` (branch-name globs `/prune` never offers to remove).
- **`web`** — `roots` (where the built site is), `baseUrl` (the canonical origin) and `ignore`, for `/web`.
- **`subtrees`** — `{ "<name>": { "prefix": "app", "remote": "app", "branch": "main" } }`. With it,
  `/commit sub <name>` and `/push sub <name>` push that folder to its own repo after committing.
- **`report`** — for `/report`. `authors` (`git` names and `github` logins whose work counts; omit for
  everyone), `repos` (where the work is, each with an optional `github` slug so merged pull requests are
  read instead of commits), `metrics` (commands whose output the report may quote, given the period in
  `REPORT_START`/`REPORT_END` and their `_UTC` forms; `window` limits one to periods of that length) and
  `audience` (who reads it and what it must never mention).
- **`kitPath`** — where this project's kit checkout is, when it is not `~/.claude-kit`.

### `sqlite_tracking` — Git-friendly SQLite change tracking

Track changes to SQLite databases through git using the [AirSQLite](https://github.com/AirSQLite/AirSQLite) sidecar layout — a `{dbname}.airsqlite/` folder next to each `.db` file containing per-table snapshot files. One JSON line per row (including `_rowid`), sorted by rowid. Git tracks lines, not binary blobs, so each row change produces a clean, readable diff. The format is compatible with the AirSQLite VS Code/Cursor extension, which can read these snapshots for between-session reconciliation.

```json
{
  "sqlite_tracking": [
    {
      "db": "cowork/prospecting/PROSPECTS.db",
      "tables": ["prospects", "rejected", "contact_attempts"]
    }
  ]
}
```

- **`db`** — path to the `.db` file (relative to project root)
- **`tables`** — which tables to track (omit to track all non-internal tables)
- **`exclude`** — table-name globs to leave out, such as `["logs_fts*"]`

Sidecars are regenerated by `/commit` before staging, so `git add -A` picks them up naturally. Not a git hook — hooks don't clone, and a stale sidecar fails silently.

**Layout on disk:**
```
PROSPECTS.db
PROSPECTS.airsqlite/
  prospects.snapshot.ndjson
  rejected.snapshot.ndjson
  contact_attempts.snapshot.ndjson
```

**What it buys:**
- `git log -p -- PROSPECTS.airsqlite/prospects.snapshot.ndjson` — what each run found, what changed
- `git blame PROSPECTS.airsqlite/prospects.snapshot.ndjson` — when each record entered and which run found it
- Enrichment passes land as their own commits, so "where did this data come from" is answerable
- Compatible with AirSQLite's sidecar system — snapshots are readable by the extension for reconciliation

**The brain uses it by default.** `install.sh` adds `{ "db": "cowork/brain/BRAIN.db", "tables": ["logs"] }`,
and `BRAIN.db` itself is git-ignored. A fresh clone gets its brain back at the first session start:
the hook runs `sqlite-sidecar.sh restore`, which rebuilds a missing database from its schema and
snapshots (never in a linked worktree, where the brain is the main checkout's).

**When it fits:** tiny databases (hundreds to low thousands of rows), batch writes (1-3x/week), append-dominant patterns. The sidecar adds ~12% repo size overhead — negligible at this scale.

The script behind it, `~/.claude-kit/scripts/sqlite-sidecar.sh`, can also be run directly outside of `/commit`. It needs `jq`.

### `fork` vs `exclude`

Easy to confuse, and they do opposite things:

- **`fork`** — the path exists here and **your project owns it**. The kit never links, copies, or
  gitignores it. Use it when you need genuinely different behavior from the kit's version.
- **`exclude`** — the path **has no business existing here at all**. Never installed, in either
  mode. Use it to install a subset — say, a repo for a non-technical collaborator that shouldn't
  carry developer tooling. Excluding doesn't delete what's already there; the installer reports
  leftovers so removal stays deliberate.

### Where project-specific behavior belongs

In order of preference — reach for the first one that fits:

1. **A value** → `kit.json` (dev ports, commit author, plan directories)
2. **A short rule** → `kit.json` `rules.<skill>`, applied whenever that skill runs
3. **A procedure** → a project-owned skill with its own name, sitting alongside the kit's, or a
   project-owned subagent in `.claude/agents/` that a kit skill's rule points at (for example,
   the prior-art sweep `/plan`'s PR mode runs before a body is written). The installer never
   touches your own skills or agents.
4. **How Claude writes for a context** (client messages, a wiki) → a writing set: `.claude/writing/<name>.md`,
   or `kit.json` `writing.<name>` to adjust one of yours ([Writing rules](customization.md#writing-rules))
5. **`fork`** → last resort, when the kit's own behavior has to change

The ordering matters: JSON keeps overrides deliberately small, and a rule that won't fit
comfortably in a string is usually a sign it belongs in its own skill — or upstream in the kit.

---

## What's in a project after install

```
.claude/
  kit.json            # mode + configuration (yours)
  skills/             # kit skills, plus any you add
  agents/             # kit agent definitions (the /swarm tiers), plus any you add
  KIT.md              # the kit's conventions, injected into every session by the session-start hook
  hooks/              # session-start: syncs kit links, loads brain state and KIT.md, heals schema drift
                      # session-end: stamps the session's end time
                      # background-pbar: nudges /pbar after background Bash calls
  settings.json       # model (pinned to Opus with 1M context), permissions, hooks (yours)
  settings.local.json # this machine only: points Claude's memory at .claude/memory (yours, not in git)
  memory/             # Claude's memories for this project, committed with it
.vscode/              # settings.json, extensions.json — kit-managed (permission mode lives here)
cowork/
  brain/
    BRAIN.db          # knowledge base (SQLite + FTS5), git-ignored
    BRAIN.airsqlite/  # logs.snapshot.ndjson: the brain's readable copy in git (written by /commit)
  plans/              # NNN_YYYY-MM-DD_topic.md
  research/           # NNN_YYYY-MM-DD_topic/ — agent-*.md + SUMMARY.md
  reports/            # YYYY-MM-DD_<period>-report.md (created by /report)
  swarm/              # <plan_id>/ — SWARM.md + REPORT.md per swarmed plan (created by /swarm)
  architecture/       # CTO.db, generated architecture.html, dated summaries
  vibe-audit/         # VIBE-AUDIT.db, GUARDRAILS.md (yours)
  video/              # transcripts, scripts, caption-dictionary.json (yours)
wiki/                 # organic project documentation (yours, maintained by /wiki)
  README.md           # table of contents
  STYLE.md            # writing guide (yours — controls voice, audience, conventions)
scripts/
  wiki-build/         # static-site builder used by /wiki deploy (linked from the kit)
  puppeteer-server.cjs, artifact-bridge.cjs   # /look co-browser, /bridge server
CLAUDE.md             # project documentation, ending in the ## Mantra block (yours)
.mcp.json             # research MCP servers (yours — holds API keys)
```

Files marked *(yours)* are created once and never replaced. A later install may add a hook, a
permission or an MCP server entry to `settings.json` and `.mcp.json`; it leaves the rest of them
alone. Everything else is kit-managed.

### The brain DB

SQLite with FTS5 full-text search at `cowork/brain/BRAIN.db`.

**Entry types** — `note`, `decision` (permanent; supersede rather than edit), `question`,
`insight`, `task`, `milestone`.

**Tiers**, computed rather than set by hand:

- **hot** — focus items and plan-linked tasks with momentum
- **warm** — importance ≥ 6, or created in the last 14 days
- **cold** — everything else still active
- **archived** — done, dropped, superseded, or importance set to 0

`sessions` records when each Claude Code session started and ended, keyed by Claude Code's own
session id, so parallel sessions never close each other. The session-start hook lists what the
previous session added, and Claude checks it against the mantra.

The mantra is not in the DB. It is the `## Mantra` block at the end of `CLAUDE.md`, between the
`<!-- BEGIN:mantra -->` and `<!-- END:mantra -->` lines: one copy, loaded with CLAUDE.md, with
git as its history and a budget of about 4,000 characters. Its rules live in `.claude/KIT.md`.
Projects on the older layout (a `mantra` table, `MANTRA.md`, `BRAIN.md`, a committed `BRAIN.db`)
move over with `bash ~/.claude-kit/scripts/brain-migrate`; the hook offers it when it sees one.

Four more tables (`swarm_runs`, `swarm_units`, `swarm_unit_events`, `swarm_holds`) hold `/swarm`
execution state. `/swarm` adds any that are missing on its first run — see
[Swarm](plan-and-swarm.md#swarm-swarm).
