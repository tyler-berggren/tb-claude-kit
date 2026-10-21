#!/usr/bin/env python3
"""Gather the evidence for /report: one period and the equal period before it.

Usage: gather.py [period] [--out <file>]

period: N or Nd (last N days, default 7), week | month | quarter (last 7 / 30 / 90 days),
YYYY-MM (a calendar month), qN, qN-YYYY or YYYY-qN (a calendar quarter), since YYYY-MM-DD.

Reads `report` from .claude/kit.json (see the skill for the keys). Writes the evidence as
markdown to --out (default .claude/state/report/evidence.md) and prints a short summary.
Read-only everywhere else: it queries the brain, git and GitHub, and runs the configured
metric commands.
"""
import datetime as dt
import json
import os
import re
import sqlite3
import subprocess
import sys
from collections import Counter

EVIDENCE_BUDGET = 60000  # characters of PR or commit bodies, shared across the period


def die(msg):
    print(f"report: {msg}", file=sys.stderr)
    sys.exit(2)


def month_start(y, m):
    return dt.datetime(y + (m - 1) // 12, (m - 1) % 12 + 1, 1)


def parse_period(arg, now):
    a = (arg or "7").strip().lower()
    named = {"week": 7, "month": 30, "quarter": 90}
    if a in named or re.fullmatch(r"\d+d?", a):
        days = named.get(a) or int(a.rstrip("d"))
        start = now - dt.timedelta(days=days)
        label = {7: "weekly", 30: "monthly", 90: "quarterly"}.get(days, f"last-{days}-days")
        return start, now, start - dt.timedelta(days=days), start, label, f"the last {days} days"
    m = re.fullmatch(r"(\d{4})-(\d{2})", a)
    if m:
        y, mo = int(m.group(1)), int(m.group(2))
        start, end = month_start(y, mo), month_start(y, mo + 1)
        name = start.strftime("%B %Y")
        return start, min(end, now), month_start(y, mo - 1), start, a, name
    m = re.fullmatch(r"(?:q([1-4])(?:-(\d{4}))?|(\d{4})-q([1-4]))", a)
    if m:
        q = int(m.group(1) or m.group(4))
        y = int(m.group(2) or m.group(3) or now.year)
        start, end = month_start(y, 3 * q - 2), month_start(y, 3 * q + 1)
        return start, min(end, now), month_start(y, 3 * q - 5), start, f"{y}-q{q}", f"Q{q} {y}"
    m = re.fullmatch(r"since\s+(\d{4}-\d{2}-\d{2})", a)
    if m:
        start = dt.datetime.strptime(m.group(1), "%Y-%m-%d")
        span = now - start
        return start, now, start - span, start, "progress", f"since {start:%B %-d}"
    die(f"unknown period '{arg}' (try 7, 30d, month, quarter, 2026-09, q3, since 2026-10-01)")


def sh(cmd, cwd=None, env=None):
    r = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True,
                       shell=isinstance(cmd, str))
    return r.returncode, r.stdout, r.stderr


def iso(d):
    return d.strftime("%Y-%m-%dT%H:%M:%S")


def utc(d):
    return d.astimezone(dt.timezone.utc)


def area(path):
    parts = path.split("/")
    if len(parts) > 2 and parts[0] in ("apps", "packages", "services", "libs", "crates"):
        return f"{parts[0]}/{parts[1]}"
    return parts[0] if len(parts) > 1 else "(root)"


def lead(body, n):
    """The opening of a body, preferring a Goal or Summary section."""
    body = re.sub(r"<!--.*?-->", "", body or "", flags=re.S)
    m = re.search(r"^#+\s*(goal|summary|why)\b.*?$(.*?)(?=^#+\s|\Z)", body, re.S | re.I | re.M)
    text = (m.group(2) if m else body).strip()
    text = re.sub(r"\s+", " ", text)
    return text[:n] + ("…" if len(text) > n else "")


# --- brain -------------------------------------------------------------------

def brain(db, s, e):
    if not os.path.exists(db):
        return None
    c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    a, b = iso(s), iso(e)
    created = "replace(created_at,' ','T') >= ? AND replace(created_at,' ','T') < ?"
    out = {}
    out["milestones"] = c.execute(
        f"SELECT id, title, substr(coalesce(body,''),1,400) FROM logs WHERE type='milestone' AND {created} ORDER BY created_at",
        (a, b)).fetchall()
    out["tasks_done"] = c.execute(
        "SELECT id, title, coalesce(pillar,'') FROM logs WHERE type='task' AND completed_at >= ? AND completed_at < ? ORDER BY completed_at",
        (a, b)).fetchall()
    for t in ("decision", "insight"):
        out[t] = c.execute(
            f"SELECT id, title, substr(coalesce(body,''),1,240) FROM logs WHERE type=? AND {created} ORDER BY created_at",
            (t, a, b)).fetchall()
    out["sessions"] = c.execute(
        "SELECT started_at, summary FROM sessions WHERE replace(started_at,' ','T') >= ? AND replace(started_at,' ','T') < ? AND coalesce(summary,'') != ''",
        (a, b)).fetchall()
    out["session_count"] = c.execute(
        "SELECT count(*) FROM sessions WHERE replace(started_at,' ','T') >= ? AND replace(started_at,' ','T') < ?",
        (a, b)).fetchone()[0]
    return out


def brain_next(db):
    if not os.path.exists(db):
        return [], []
    c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    focus = c.execute(
        "SELECT id, type, title FROM logs WHERE focus=1 AND status='active'").fetchall()
    hot = c.execute(
        "SELECT id, title, coalesce(pillar,'') FROM logs WHERE type='task' AND status='active' AND tier IN ('hot','warm') ORDER BY tier='hot' DESC, priority DESC, created_at DESC LIMIT 25").fetchall()
    return focus, hot


# --- repos -------------------------------------------------------------------

def merged_prs(repo, gh_repo, logins, s, e, with_bodies):
    """Merged PRs in [s, e) by the configured logins (everyone when none)."""
    fields = "number,title,mergedAt,files" + (",body" if with_bodies else "")
    found = {}
    for login in (logins or [None]):
        cmd = ["gh", "pr", "list", "--repo", gh_repo, "--state", "merged", "--limit", "1000",
               "--search", f"merged:{s:%Y-%m-%d}..{e:%Y-%m-%d}", "--json", fields]
        if login:
            cmd += ["--author", login]
        code, out, err = sh(cmd, cwd=repo)
        if code != 0:  # GitHub's search API drops the odd request (502); one retry
            code, out, err = sh(cmd, cwd=repo)
        if code != 0:
            return None, err.strip()
        for pr in json.loads(out or "[]"):
            m = dt.datetime.fromisoformat(pr["mergedAt"].replace("Z", "+00:00"))
            if utc(s) <= m < utc(e):
                found[pr["number"]] = pr
    return sorted(found.values(), key=lambda p: p["mergedAt"]), None


def commits(repo, ref, authors, s, e):
    cmd = ["git", "-C", repo, "log", ref, "--no-merges", f"--since={iso(s)}", f"--until={iso(e)}",
           "--format=%x1e%h%x1f%ad%x1f%s%x1f%b", "--date=short", "--name-only"]
    for a in authors or []:
        cmd.append(f"--author={a}")
    code, out, err = sh(cmd)
    if code != 0:
        return None, err.strip()
    rows = []
    for chunk in out.split("\x1e")[1:]:
        head, _, files = chunk.partition("\n")
        parts = (head + "\x1f\x1f\x1f").split("\x1f")
        body_and_files = chunk.split("\x1f", 3)[3] if chunk.count("\x1f") >= 3 else ""
        body, _, file_block = body_and_files.partition("\n\n")
        rows.append({"sha": parts[0], "date": parts[1], "title": parts[2], "body": body.strip(),
                     "files": [{"path": f} for f in file_block.split("\n") if f.strip()]})
    return rows, None


def repo_work(r, authors, s, e, with_bodies):
    path = r.get("path", ".")
    if not os.path.isdir(path):
        return {"path": path, "error": "not found (is the drive mounted?)"}
    if r.get("github"):
        items, err = merged_prs(path, r["github"], authors.get("github"), s, e, with_bodies)
        kind = "merged changes"
    else:
        items, err = commits(path, r.get("ref", "HEAD"), authors.get("git"), s, e)
        kind = "commits"
    if err:
        return {"path": path, "error": err}
    areas = Counter()
    for it in items:
        for a in {area(f["path"]) for f in it.get("files") or []}:
            areas[a] += 1
    return {"path": path, "name": r.get("name", path), "kind": kind, "items": items, "areas": areas}


# --- metrics -----------------------------------------------------------------

def run_metrics(metrics, s, e, ps, label):
    out = []
    env = dict(os.environ, REPORT_START=iso(s), REPORT_END=iso(e), REPORT_PRIOR_START=iso(ps),
               REPORT_START_UTC=iso(utc(s)), REPORT_END_UTC=iso(utc(e)),
               REPORT_PRIOR_START_UTC=iso(utc(ps)),
               REPORT_DAYS=str(round((e - s).total_seconds() / 86400)))
    days = env["REPORT_DAYS"]
    for m in metrics or []:
        win = m.get("window")
        if win and win.rstrip("d") != days:
            out.append((m, None, f"skipped: this metric only covers {win}, the report covers {days} days"))
            continue
        code, stdout, stderr = sh(m["command"], env=env)
        out.append((m, stdout.strip() if code == 0 else None, None if code == 0 else stderr.strip()[-600:]))
    return out


# --- main --------------------------------------------------------------------

def main():
    args = sys.argv[1:]
    out_path = ".claude/state/report/evidence.md"
    if "--out" in args:
        i = args.index("--out")
        out_path = args[i + 1]
        del args[i:i + 2]
    now = dt.datetime.now().astimezone().replace(tzinfo=None, microsecond=0)
    s, e, ps, pe, label, human = parse_period(" ".join(args), now)
    local = dt.datetime.now().astimezone().tzinfo
    s, e, ps, pe = (d.replace(tzinfo=local) for d in (s, e, ps, pe))

    try:
        kit = json.load(open(".claude/kit.json"))
    except (OSError, ValueError):
        kit = {}
    cfg = kit.get("report", {})
    authors = cfg.get("authors", {})
    repos = cfg.get("repos") or [{"path": "."}]
    db = cfg.get("brain", "cowork/brain/BRAIN.db")

    cur = [repo_work(r, authors, s, e, True) for r in repos]
    prev = [repo_work(r, authors, ps, pe, False) for r in repos]
    b_cur, b_prev = brain(db, s.replace(tzinfo=None), e.replace(tzinfo=None)), brain(db, ps.replace(tzinfo=None), pe.replace(tzinfo=None))
    focus, hot = brain_next(db)
    metrics = run_metrics(cfg.get("metrics"), s, e, ps, label)

    n_items = sum(len(r.get("items") or []) for r in cur) or 1
    per = max(150, EVIDENCE_BUDGET // n_items)

    L = []
    w = L.append
    w(f"# Report evidence: {human}\n")
    w(f"- Period: {s:%Y-%m-%d %H:%M} to {e:%Y-%m-%d %H:%M} ({label})")
    w(f"- Prior equal period: {ps:%Y-%m-%d %H:%M} to {pe:%Y-%m-%d %H:%M}")
    last = min(e, now.replace(tzinfo=e.tzinfo))
    title = {"weekly": "Weekly report", "monthly": "Monthly report",
             "quarterly": "Quarterly report"}.get(label, "Progress report")
    w(f"- Title: {title}: {s:%a %m/%d/%y} - {last:%a %m/%d/%y}")
    w(f"- Suggested file: cowork/reports/{now:%Y-%m-%d}_{label}-report.md")
    w(f"- Authors: {json.dumps(authors) if authors else 'everyone'}")
    w(f"- Audience rule: {cfg.get('audience') or '(none set)'}\n")

    w("## Counts (this period / prior period)\n")
    w("| Measure | This period | Prior period |\n|---|---|---|")
    for c, p in zip(cur, prev):
        if "error" in c or "error" in p:
            w(f"| {c.get('name', c['path'])} | error: {c.get('error') or p.get('error')} | |")
            continue
        w(f"| {c['name']}: {c['kind']} | {len(c['items'])} | {len(p['items'])} |")
        w(f"| {c['name']}: areas touched | {len(c['areas'])} | {len(p['areas'])} |")
    if b_cur and b_prev:
        for k, name in (("milestones", "brain milestones"), ("tasks_done", "tasks completed"),
                        ("decision", "decisions recorded"), ("insight", "findings recorded"),
                        ("session_count", "working sessions")):
            a, b = b_cur[k], b_prev[k]
            w(f"| {name} | {a if isinstance(a, int) else len(a)} | {b if isinstance(b, int) else len(b)} |")
    w("")

    for c, p in zip(cur, prev):
        if "error" in c:
            continue
        w(f"## {c['name']}: areas touched (changes per area, this period / prior)\n")
        for a, n in sorted(c["areas"].items(), key=lambda x: -x[1]):
            w(f"- {a}: {n} / {p.get('areas', {}).get(a, 0) if 'error' not in p else '?'}")
        w(f"\n## {c['name']}: {c['kind']} this period\n")
        for it in c["items"]:
            ref = f"#{it['number']}" if "number" in it else it["sha"]
            when = (it.get("mergedAt") or it.get("date") or "")[:10]
            areas = ", ".join(sorted({area(f['path']) for f in it.get('files') or []}))
            w(f"- {when} {ref} **{it['title']}** [{areas}]")
            text = lead(it.get("body"), per)
            if text:
                w(f"  {text}")
        if "error" not in p:
            w(f"\n## {c['name']}: {c['kind']} in the prior period (titles only, for the comparison)\n")
            for it in p["items"]:
                areas = ", ".join(sorted({area(f['path']) for f in it.get('files') or []}))
                w(f"- {it['title']} [{areas}]")
        w("")

    if b_cur:
        sections = (("milestones", "Brain milestones"), ("decision", "Decisions recorded"),
                    ("insight", "Findings recorded"), ("tasks_done", "Tasks completed"))
        for k, name in sections:
            w(f"## {name}\n")
            for row in b_cur[k]:
                w(f"- #{row[0]} {row[1]}" + (f" — {re.sub(chr(10), ' ', row[2])}" if row[2] and k != "tasks_done" else ""))
            w("")
        if b_cur["sessions"]:
            w("## Session summaries\n")
            for st, summ in b_cur["sessions"]:
                w(f"- {st[:10]}: {summ}")
            w("")
        w("## Open now (for What's next)\n")
        for row in focus:
            w(f"- focus #{row[0]} ({row[1]}) {row[2]}")
        for row in hot:
            w(f"- task #{row[0]} {row[1]}" + (f" [{row[2]}]" if row[2] else ""))
        w("")

    w("## Metrics\n")
    if not metrics:
        w("(none configured)")
    for m, value, note in metrics:
        w(f"### {m['name']}\n")
        if m.get("explain"):
            w(f"How to read it: {m['explain']}\n")
        w(f"Command: `{m['command']}`\n")
        if value is not None:
            w("```\n" + value + "\n```\n")
        else:
            w(f"Not available: {note}\n")

    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with open(out_path, "w") as f:
        f.write("\n".join(L) + "\n")

    print(f"period: {human} ({s:%Y-%m-%d} to {e:%Y-%m-%d}); prior {ps:%Y-%m-%d} to {pe:%Y-%m-%d}")
    for c, p in zip(cur, prev):
        if "error" in c:
            print(f"{c['path']}: ERROR {c['error']}")
        else:
            prior = f"ERROR {p['error']}" if "error" in p else len(p["items"])
            print(f"{c['name']}: {len(c['items'])} {c['kind']} (prior {prior}), {len(c['areas'])} areas")
    if b_cur:
        print(f"brain: {len(b_cur['milestones'])} milestones, {len(b_cur['tasks_done'])} tasks done, "
              f"{len(b_cur['decision'])} decisions, {len(b_cur['insight'])} findings")
    for m, value, note in metrics:
        print(f"metric {m['name']}: {'ok' if value is not None else note}")
    print(f"evidence: {out_path} ({sum(len(x) for x in L)} chars)")


if __name__ == "__main__":
    main()
