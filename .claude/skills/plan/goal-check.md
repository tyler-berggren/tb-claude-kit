# Goal check: the plan's goal, read with fresh eyes

A long session drifts. Each side task is reasonable when it starts, and the session that took it on
is the worst judge of whether it still serves the goal: it remembers every reason it had. The goal
check gives that judgement to an agent that has none of the session's context, reading only what
the plan and the project's own records say.

Part of **Autopilot** (`autopilot.md`): on whenever autopilot is on.

## The goal block

Every plan carries `## Goal` directly under its title and banners, before `## Handoff`:

```markdown
## Goal
**Goal:** <the outcome for the owner, one sentence, in their words>
**Done when:** <a measurable finish line: a count, a state, a date>
**Measure:** <how to read progress now: a query, a command, a count in the plan>
**Pace:** <latest reading, its date, and the rate since the plan opened> (updated by each goal check)
**Not this plan:** <what looks related and is out of scope, one line>
```

- **Generate** writes it with the plan. **Resume** adds it at R3 when it is missing, drafted from the
  plan's opening and asked in that batch only if the goal cannot be read from the plan.
- The goal and the finish line are the owner's: change them only on their word, and say so in the
  plan's log. The session keeps **Pace** current.

## When it runs

- **At each milestone** the plan names (a phase closed, a unit of the plan's work finished: a county
  loaded, a release out).
- **Before taking a new Work ahead item** when the last check is more than four hours old.
- **At least once a day** while the session is alive: the autopilot heartbeat runs it on the first
  wake after 24 hours without one.
- **When the owner asks** ("are we on track?", "check the goal").

Never more than once in four hours except at a milestone or when asked.

## How it runs

Spawn a fresh agent, **never a fork** (a fork inherits the session's reasoning, which is the thing to
leave out): the Agent tool, general-purpose, foreground. Give it only the brief below, filled in. Do not
add your own view of what has gone well or badly; it reads the record.

```text
You are checking whether a plan is on track toward its goal. You have no context but this brief and
the files and commands it names. Read them; do not trust any summary of them, including this one.

Plan file: <path>
Last goal check: <date-time, or "none"> (its note is in the plan's ## Goal checks)
Since then: `git log --since="<last check>" --stat -- <the plan's paths>` and the plan's own dated
log lines (Review, ledger, Work ahead) since that time.
Measure: <the Measure line, as a command you can run read-only>

Answer, in at most 12 lines:
1. The measure now, against the last check's reading and the plan's start. Run it yourself.
2. Where the time since the last check went: on the goal, supporting it (a fault that blocked it),
   or off it. Name each piece of work in a few words and give it one of the three.
3. Work ahead items that no longer serve the goal, or are ordered against it.
4. The one thing that would move the measure most next.
5. A verdict: on track, drifting (time going to work that does not move the measure), or stalled
   (the measure has not moved and nothing in the queue will move it).
Be blunt. Do not soften a verdict because the off-goal work was well done.
```

## What the session does with it

1. **Write it in the plan** under `## Goal checks` (below `## Work ahead`), newest first: the date, the
   verdict, the measure, and the agent's points 2-4 in a line each. Keep the last five; fold older
   ones into one line each.
2. **Update Pace** in the goal block from point 1.
3. **Act on it in the same turn.** Reorder or trim Work ahead as point 3 says. An item the check
   called off-goal is kept only with a written reason beside it in Work ahead; otherwise it leaves
   (to the plan's improvement list, not deleted).
4. **Lead the next status with the verdict**, one line: "Goal check: drifting: 2 of the last 9 hours
   moved the count; next is the Placer load."
5. **Two drifting or stalled verdicts in a row** go to the owner in the status as a question about
   the goal or the queue (and a push notification). Autopilot does not stop for it.
