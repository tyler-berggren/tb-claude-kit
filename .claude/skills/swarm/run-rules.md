## Run rules (the agent protocol)

Copied into SWARM.md at setup; binding for every spawned agent.

- **Never ask the user anything.** Facing a judgment call, including a design, layout or wording one? Decide as a senior developer would, applying the decision protocol: (1) the plan and its decisions are authoritative → (2) the SWARM.md decision record → (3) brain DB decisions → (4) the codebase's conventions and the smallest reasonable reading of the item. Build it so it works, keep going, and record it under `Calls`. A call the owner overrules later becomes a fix slice, which beats a stalled swarm.
- **At a genuine fork, decide and build lean.** When it is truly unclear which way best reaches the goal, still pick one, but keep follow-on work to a minimum: make it functional end to end and stop there, with no polish, extensions or dependent work stacked on it until a later pass needs them. Tokens spent building what may be un-built are waste. Mark the call `uncertain`.
- **The one exception is a critical issue:** an action not pre-approved in SWARM.md that is irreversible or outward-facing (deleting shared data, notifying people, spending money, touching production), a security, privacy or permissions exposure, or reversing a decision the owner explicitly made. Do not take it and do not wait: finish what does not depend on it, and report it under `Critical`. The orchestrator parks the unit and notifies the owner. When unsure, it is not critical.
- **Verify UI in order, then stop.** (1) Code: types, tests, the logic that renders it. (2) Only if code cannot settle it, your own headless browser (`/look`, **Headless**): the page loads without errors, the changed control is there, the interaction works, and nothing overflows at a phone width. (3) If neither can verify it cheaply, record it under `Unverified` with what you could not check and why, and move on. Do not fight a page that will not render headless. Never verify in a headed browser: do not drive the owner's shared window, and do not launch a visible browser of your own.
- **Stay in your territory.** Read anything; edit only your unit's files. Never edit the plan file, `cowork/**` (brain, plans, swarm files), or `.claude/**` — your worktree's copies would conflict on merge. The orchestrator owns all bookkeeping.
- **Never make the owner approve a command.** A run is unattended, and some command shapes prompt the owner whatever the project allows. The common one: `cd <dir>` followed by `git` or `gh` in the same shell call. Use `git -C <path> …` for every git command and the host CLI's repository flag (`gh … --repo <owner>/<name>`), with absolute paths for scripts and files, so no `cd` is needed. When a tool truly needs a working directory, use `env -C <dir> <command>` or give the `cd` a shell call of its own. Also avoid command substitution (`$(…)`, backticks), process substitution, here-documents and `eval`: run the inner command in its own call, and write longer text to a file and pass the file. Scripts you write for your own unit follow the same rule. **The swarm agent types enforce this:** `bash-guard.py` in this skill's folder refuses those shapes before they can prompt and tells you the form to use. A refusal is not a failure: re-issue the command in that form, and never retry the refused shape.
- **Stay inside the machine budget.** Run every heavy step (a check, a test run, a type-check or build, a browser capture run) through the gate, `<the swarm skill's folder>/machine.sh run -- <command>`; your prompt gives the full path. A big step (a native app build, a production bundle build) takes the weight the project gives it. Start every long-running server through `machine.sh serve --tag <tag> -- <command>` (or the project's serve script, which does); exit 75 means someone else holds it: do everything else first, try once more, then record the check under `Unverified`. Start a simulator, emulator or other standing resource only when you hold its tag and only when you need it, and stop it when your brief says your lane ends with you. Run only the checks your change can affect: never a whole suite the project's checks do not ask for. Before you report, stop every server, watcher, browser and build daemon you started, by process id or port, never by a pattern that could match another unit's (see **Machine budget**).
- **Every turn re-reads your whole context, so count turns, not just tokens.** An agent's context starts near 100k tokens and grows past 300k, and each turn pays for all of it again (swarm 060: builders averaged about 300k a turn over 2,230 turns, and turns were half the run's cost).
  - **Batch independent work into one turn:** several reads, greps or checks as parallel tool calls in one message, or one shell call that runs a short sequence of commands.
  - **Read a file once, in the range you need,** with Read or Grep, not in a string of small `sed -n` calls. Don't re-read what is already in your context.
  - **Keep output short:** run tests with a quiet reporter, or keep the summary and failures (`| tail -n 40`); send long output to a file in your proof folder and read the part you need.
- **Never wait on a long job turn by turn.** Start a load, download, backfill or build that will run more than a few minutes detached, with its log in your proof folder, and confirm it started and wrote its first output. Then either:
  - wait once, in the background, on its end (a single `Monitor` or background `until` wait on the log's last line), and do your other work meanwhile; or
  - when it would outlast the rest of your work, finish and report it under `Done` as **still running**, with its process id, its log's path, and the lines that mark success and failure. The orchestrator follows it from there.

  Never poll it with `sleep`, `tail`, `wc` or `ps` turn after turn: each poll re-reads your whole context (swarm 060's unit W spent 94 of its 321 turns polling, at about 365k tokens each).
- **Work only in your own worktree.** Your first step is creating your assigned branch there from the integration sha in your prompt (`git switch -c <branch> <sha>`). Never `cd` into, check out in, or write to the primary checkout (the owner's IDE) or another unit's worktree. The brain's absolute path is for reading `swarm_holds`, nothing else.
- **Commit your work** on your assigned branch, in coherent chunks with real messages. Never stage `cowork/` paths.
- **Verify before reporting done.** Run your brief's verification criteria and the project's checks yourself. Report honestly: what passed, what you couldn't verify, what you decided, what a human should look at. The structured final report is your only channel out, and it has five sections:
  - `Done`
  - `Calls`: each with the options, why this one, whether it is `uncertain` (built lean), what switching would cost, and what depends on it
  - `Unverified`: UI or behaviour that neither code nor a headless browser could check, each with the URL when there is one, what could not be checked, and why
  - `Critical`: what must not ship without the owner, and why (empty for almost every unit)
  - `Blocked`

  The orchestrator copies `Calls`, `Unverified` and `Critical` into the plan's review block, and a ship agent puts `Unverified` into the PR notes.
- **Respect resource tags.** If your brief carries none, do not touch shared external state (live DBs, deploys) at all.
- **Honour review holds.** The owner may be reviewing in a parallel session that has borrowed some of
  the shared state (**Review flow**). Right before any step that uses a tagged resource's shared
  state, check for an open hold on that tag:
  `sqlite3 <brain> "SELECT holder, detail FROM swarm_holds WHERE run_id = <run> AND tag = '<tag>' AND released_at IS NULL"`.
  - **Steps that count:** starting a dev server on a fixed port, resetting or migrating a database.
  - **While held:** carry on with everything that does not need it, and do the held step last.
  - **If that step is all that is left:** re-check every minute until the hold is released.
  - **Never stop, restart or reuse a process you did not start**, even when it holds the port you need.

Orchestrator-side:

- **Only the orchestrator merges, and only after review.** No unit branch reaches the integration branch unreviewed.
- **Resource locks are absolute** — never dispatch into a held tag, even if the code territories are disjoint.
- **Keep `swarm_runs` / `swarm_units` current at every transition** — it's what a resume session reconstructs the world from.
- **Every time written to a run log comes from the clock** (`date -u +%H:%MZ` at the moment of
  writing), never from memory: a remembered time drifts by hours across a long session.
- **Long waits never run in the foreground.** A poll loop (`while/until … sleep`) holds its agent
  until a tool timeout kills it. Waits run in the background and notify on completion, or belong to
  the run's watcher.
- **A unit's long job outlives the unit.** A unit that reports a job **still running** is reviewed and
  merged on what it has done. The orchestrator then follows the job with one background wait on the
  success or failure line its report names, never by keeping an agent alive to poll it, and lists the
  job in REPORT.md's loose ends until it ends. A failure line is a finding for a fix agent.
- **The orchestrator's turns cost the same way.** Batch independent bookkeeping (the brain, the run
  log, the plan's checkboxes) into as few turns as it takes, and keep command output short.
- **Re-read the plan from disk before every write.** The owner can edit it at any time, most often by marking review items, and a write from a stale copy erases their marks.
- **Honour review holds yourself.** A database reset, a check that starts a server, a batch step: check `swarm_holds` first, exactly as units do.
- **Keep the run inside the machine budget** (**Machine budget**): dispatch no more than `swarm.maxAgents` builders, read `machine.sh pressure` before every dispatch and hold new units while memory is short, put the gate's full path in every dispatch, sweep each unit's worktree after its report or when it is stopped, start no standing resource at preflight, and route your own heavy steps through the gate too.
- **Failures degrade, never halt.** One failed unit skips its dependents and the rest of the swarm continues. The report tells the user what's left.
