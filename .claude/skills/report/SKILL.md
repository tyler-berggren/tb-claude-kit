---
name: report
description: Write a plain-language progress report for management, stakeholders and peers on the work done over a period (default the last 7 days), from the brain and git history. Outcomes and measured results, never developer artifacts; momentum shown only as a comparison with the period before.
argument-hint: "[7 | 30d | week | month | quarter | 2026-09 | q3 | since 2026-10-01]"
---

# Report

One report, readable by anyone, on what the work over a period achieved. The readers are managers,
stakeholders and peers, not developers: they care about what changed for the people using the
product and for the business, and whether things are moving. The skill reads developer evidence
(merged pull requests, commits, the brain) and translates it; none of that evidence appears in the
text.

## Input

The argument is the period. Default `7`.

| Argument | Period | Compared with |
|---|---|---|
| `N`, `Nd` | the last N days | the N days before |
| `week`, `month`, `quarter` | the last 7, 30, 90 days | the same length before |
| `2026-09` | that calendar month (to now, if current) | the month before |
| `q3`, `q3-2026`, `2026-q3` | that calendar quarter | the quarter before |
| `since 2026-10-01` | that date to now | the same length before |

## Project settings

`report` in `.claude/kit.json`. Every key is optional.

```json
"report": {
  "authors": { "git": ["Ada Lovelace"], "github": ["ada"] },
  "repos": [{ "path": ".", "name": "The product", "github": "org/repo", "ref": "HEAD" }],
  "brain": "cowork/brain/BRAIN.db",
  "metrics": [{ "name": "Checkout conversion", "command": "scripts/conversion.sh", "window": "7d",
                "explain": "how to read the output" }],
  "audience": "who reads it, and what it must never mention"
}
```

- **`authors`**: whose work counts. Omitted means everyone's. `git` filters commits by author,
  `github` filters merged pull requests by login.
- **`repos`**: where the work is. Default is this repo. With `github` set, the evidence is merged
  pull requests (title, files and the body's Goal or Summary); without it, commits on `ref`.
- **`metrics`**: commands whose output the report may quote. These are the measured outcomes,
  such as speed, usage, revenue or reliability. Each runs with `REPORT_START`, `REPORT_END`,
  `REPORT_PRIOR_START` and `REPORT_DAYS` in its environment. If `window` is set, the metric runs
  only when the period has that length; a fixed-window query is never quoted for a different
  period. `explain` tells you how to read the output.
- **`audience`**: who reads it and what is off limits. Follow it exactly. It outranks everything
  below.

## Procedure

### 1. Gather

```bash
python3 -I .claude/skills/report/gather.py <period>
```

The script prints a summary and writes `.claude/state/report/evidence.md`. That file holds:

- the period and the prior period;
- a counts table for both periods;
- the areas the changes touched;
- every change in the period with the opening of its description, and the prior period's titles;
- the brain's milestones, decisions, findings, completed tasks and what is open now;
- each metric's raw output.

Read all of it. If a repo errors (an unmounted drive, no `gh` login), say so in the report's
sources and continue with what you have; never fill a gap from memory.

### 2. Find the story

Group the changes into **three to six themes** by what they did for people, not by the area of
code they touched. Twenty changes that each made one app open faster are one theme. Then sort
each change into one of two kinds:

- **Visible.** A person using the product would notice it: something faster, new, fixed or
  easier. These carry the report.
- **Groundwork.** Plumbing, cleanup, measurement or preparation that nobody sees directly. It
  gets one or two lines in total, saying what it makes possible, never a list.

For each theme, find its measured outcome in the metrics if there is one. A theme with a number
leads; a theme without one is described plainly and never given an invented figure.

Findings and decisions from the brain feed **What we learned**, but only those a reader outside
the work would care about: something that changed direction, explained a result, or found a
problem. Notes about process, tooling or how the work was organised are left out.

### 3. Write

Write `cowork/reports/YYYY-MM-DD_<label>-report.md` (the date is today; the label is in the
evidence header, e.g. `2026-10-21_weekly-report.md`). **Be brief**: about 500 words for a week and
900 at most for a quarter. One or two sentences per theme; cut any sentence that repeats a number
already given.

```markdown
# <Title from the evidence header>: <ddd MM/DD/YY> - <ddd MM/DD/YY>

## TL;DR
- <At most five bullets, one line each. The most important outcomes with their numbers, and
  anything that went the wrong way. Someone who reads only this knows how the period went.>

## What changed for people

### <Theme, in the reader's words>
<One or two sentences: what changed, for whom, and the measured result if there is one.>

## Groundwork
<One sentence on the invisible work and what it makes possible.>

## What we learned
- <A finding that changed direction or explains a result, in one sentence.>

## The numbers

| | <This period> | <Prior period> |
|---|---|---|
| <Outcome measure, in plain words> | <value> | <value> |

<One line on what the numbers measure and their limits, such as sample size.>

## What's next
1. <The next outcome being worked toward, in order of priority.>
```

The title's dates are the period's first and last day, written ddd MM/DD/YY
(`Mon 10/12/26 - Wed 10/21/26`), never as a phrase like "the week to 21 October". No sources section and no HTML: the report is
plain markdown.

### 4. Check before saving

Read the draft against each rule and fix what fails:

1. **No developer artifacts.** No pull request, issue or ticket numbers; no commit, line or file
   counts; no branch, package, function or file names; no tool names that only engineers know. A
   reader who has never seen the codebase can follow every sentence.
2. **Every number comes from the evidence.** Each figure is in the evidence file, exactly as
   given or rounded. Nothing is estimated, extrapolated or remembered.
3. **No flourish.** No adjective or adverb that a number does not back up: no "massive",
   "significant", "huge", "dramatically", "exciting". Say what happened and let the number carry it.
4. **Momentum only from the comparison.** Say something improved, accelerated or held steady
   only when the prior-period column shows it. Name a measure that got worse just as plainly, in
   the headline if it matters. A report that reads better than the data has failed.
5. **Counts are outcomes.** The numbers table counts what readers care about: measured results,
   people reached, parts of the product that changed for users. Never the volume of engineering
   activity.
6. **The audience rule holds.** Nothing it rules out appears anywhere.
7. **No help requests and no hours worked.** The report covers what was achieved, not effort or
   blockers.
8. **Short.** The TL;DR has five bullets at most, the word count is near the target, and no
   figure is stated twice except between the TL;DR and the numbers table.

### 5. Record and hand over

Log the report in the brain:

```sql
INSERT INTO logs (type, title, body, tags, meta)
VALUES ('note', 'Report: <ddd MM/DD/YY> - <ddd MM/DD/YY>', '<the TL;DR bullets>', 'report',
        json_object('file', 'cowork/reports/<file>', 'period_start', '<start>', 'period_end', '<end>'));
```

Then give the user the file path and the TL;DR. Start that message with one line naming the
audience as you understood it.

## Rules

- **Read-only.** The skill writes the report file, its evidence file and the brain note, and
  nothing else. It never posts, sends or publishes the report.
- **The audience rule outranks the template.** If it says a topic is private, that topic is left
  out even when it is most of the period's work, and the report says less rather than hint at it.
- **A thin period stays thin.** If little shipped, the report is short and says so plainly.

## Project overrides

If `.claude/kit.json` has a `rules."report"` entry, read it and apply it as an additional
instruction for this skill. Absent file or key means no overrides — that is the normal case.

```bash
jq -r '.rules."report" // empty' .claude/kit.json 2>/dev/null
```
