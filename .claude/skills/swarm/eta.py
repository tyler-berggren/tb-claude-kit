#!/usr/bin/env python3
"""Dynamic time estimates for a /swarm run, printed as a text block for a progress display.

Read-only. It reads the brain's swarm_units and swarm_unit_events (the status-change log the
swarm schema's triggers keep), learns how long each stage takes from history, and simulates the
rest of the run: every in-flight unit, every lane, and the whole run get an estimated finish.

The estimates sharpen as the run goes. Each stage's duration starts from a prior and is pulled
toward the observed median as samples arrive: est = (K*prior + n*median) / (K + n). Samples from
the current run count double, because this run's CI, repo and slice sizes are the best predictor.

Stages (status names from the swarm schema):
  build = entering `working` -> leaving it (to review, shipped, parked or merged)
  land  = entering `review` or `shipped` -> `merged`
`parked` time is waiting on the owner and is never counted as work. A parked unit and everything
that depends on it get no estimate: the display says what they wait on instead.

Usage: eta.py --db BRAIN.db --run ID [--slots 6] [--stack-in-lane] [--width 100]
  --stack-in-lane   a wait on a slice in the SAME lane is met once that slice is `shipped`
                    (PR-mode stacking); a cross-lane wait always needs `merged`.
"""
import argparse, sqlite3, statistics, heapq
from datetime import datetime, timezone

PRIOR = {"build": 1.0, "land": 0.75}   # hours, used until real samples exist
K = 2                                  # prior weight, in samples
DONE = {"merged", "skipped", "failed", "done"}
LANDING = {"review", "shipped"}


def ts(s):
    s = s.strip().replace(" ", "T")
    if s.endswith("Z"):
        s = s[:-1]
    d = datetime.fromisoformat(s[:19])
    return d.replace(tzinfo=timezone.utc)


def hours(a, b):
    return (b - a).total_seconds() / 3600


def fmt_h(h):
    if h is None:
        return "  --"
    if h < 1:
        return f"{max(1, round(h * 60)):>3}m"
    return f"{h:>4.1f}h" if h < 10 else f"{h:>4.0f}h"


def fmt_clock(now, h):
    t = now.timestamp() + h * 3600
    return datetime.fromtimestamp(t).strftime("%a %H:%M")


def samples(db, run):
    """Per-(stage, kind) duration samples in hours; current-run samples are listed twice."""
    kinds = dict(db.execute("SELECT unit_key || '@' || run_id, coalesce(kind,'') FROM swarm_units"))
    ev = {}
    for r, u, frm, to, at in db.execute(
            "SELECT run_id, unit_key, from_status, to_status, at FROM swarm_unit_events ORDER BY at"):
        ev.setdefault((r, u), []).append((to, ts(at)))
    out = {}
    for (r, u), seq in ev.items():
        kind = kinds.get(f"{u}@{r}", "")
        w = 2 if r == run else 1
        start = {}
        for to, t in seq:
            if to == "working":
                start["build"] = t
            elif "build" in start and to in LANDING | {"parked", "merged"}:
                out.setdefault(("build", kind), []).extend([hours(start.pop("build"), t)] * w)
            if to in LANDING and "land" not in start:
                start["land"] = t
            elif to == "merged" and "land" in start:
                out.setdefault(("land", kind), []).extend([hours(start.pop("land"), t)] * w)
    return out


class Model:
    def __init__(self, s):
        self.s = s

    def est(self, stage, kind):
        own = self.s.get((stage, kind), [])
        allk = [x for (st, _), xs in self.s.items() if st == stage for x in xs]
        base = statistics.median(allk) if len(allk) >= 3 else PRIOR[stage]
        pool = own if len(own) >= 3 else allk
        if not pool:
            return PRIOR[stage]
        prior = base if pool is own else PRIOR[stage]
        return (K * prior + len(pool) * statistics.median(pool)) / (K + len(pool))

    def spread(self, stage, kind):
        """80th-percentile / median ratio, for the 'could be' figure; 1.8 until there is data."""
        pool = self.s.get((stage, kind)) or [x for (st, _), xs in self.s.items() if st == stage for x in xs]
        if len(pool) < 5:
            return 1.8
        p = sorted(pool)
        med = statistics.median(p) or 0.01
        return max(1.0, min(4.0, p[int(len(p) * 0.8)] / med))

    def n(self, stage):
        return sum(len(v) for (st, _), v in self.s.items() if st == stage)


def simulate(units, model, now_state, slots, stack, scale=1.0):
    """Event-driven list schedule. Returns finish time (h from now) per unit, None if blocked."""
    finish, shipped_at = {}, {}
    running = []      # heap of (t_build_done, key)
    t = 0.0
    state = dict(now_state)   # key -> (status, elapsed_h)
    blocked = set()

    for k, (st, el) in state.items():
        u = units[k]
        if st in DONE:
            finish[k] = shipped_at[k] = 0.0
        elif st == "parked":
            blocked.add(k)
        elif st == "working":
            b = model.est("build", u["kind"]) * scale
            done = max(b - el, 0.1 * b)
            heapq.heappush(running, (done, k))
        elif st in LANDING:
            l = model.est("land", u["kind"]) * scale
            shipped_at[k] = 0.0
            finish[k] = max(l - el, 0.1 * l)

    def blocked_by(k, seen=None):
        seen = seen or set()
        for d in units[k]["deps"]:
            if d in blocked or (d in units and d not in seen and blocked_by(d, seen | {d})):
                return True
        return False

    for k in units:
        if k not in finish and k not in blocked and state[k][0] == "pending" and blocked_by(k):
            blocked.add(k)

    pending = [k for k in units if state[k][0] == "pending" and k not in blocked]

    def ready_time(k):
        u = units[k]
        best = 0.0
        for d in u["deps"]:
            if d not in units:
                continue
            same = stack and units[d]["lane"] == u["lane"]
            src = shipped_at if same else finish
            if d not in src:
                return None
            best = max(best, src[d])
        return best

    while pending or running:
        started = True
        while started and pending and len(running) < slots:
            started = False
            cands = [(ready_time(k), k) for k in pending]
            cands = [(r, k) for r, k in cands if r is not None and r <= t + 1e-9]
            if cands:
                _, k = min(cands)
                pending.remove(k)
                b = model.est("build", units[k]["kind"]) * scale
                heapq.heappush(running, (t + b, k))
                started = True
        if running:
            nxt = running[0][0]
            future = [r for r in (ready_time(k) for k in pending) if r is not None and r > t]
            if future and len(running) < slots and min(future) < nxt:
                t = min(future)
                continue
            t, k = heapq.heappop(running)
            shipped_at[k] = t
            finish[k] = t + model.est("land", units[k]["kind"]) * scale
        else:
            future = [r for r in (ready_time(k) for k in pending) if r is not None and r > t]
            if not future:
                break      # remaining pending units wait on something that never finishes
            t = min(future)
    return {k: finish.get(k) for k in units}, blocked


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", required=True)
    ap.add_argument("--run", type=int, required=True)
    ap.add_argument("--slots", type=int, default=6)
    ap.add_argument("--stack-in-lane", action="store_true")
    ap.add_argument("--width", type=int, default=100)
    a = ap.parse_args()

    db = sqlite3.connect(f"file:{a.db}?mode=ro", uri=True)
    now = datetime.now(timezone.utc)
    rows = db.execute(
        "SELECT unit_key, coalesce(lane,''), coalesce(kind,''), status, coalesce(depends_on,''), updated_at "
        "FROM swarm_units WHERE run_id=?", (a.run,)).fetchall()
    units, state = {}, {}
    last_change = {}
    for key, at in db.execute(
            "SELECT unit_key, at FROM swarm_unit_events WHERE run_id=? ORDER BY at", (a.run,)):
        last_change[key] = ts(at)
    for key, lane, kind, st, deps, upd in rows:
        units[key] = {"lane": lane or "-", "kind": kind, "deps": [d.strip() for d in deps.split(",") if d.strip()]}
        since = last_change.get(key) or (ts(upd) if upd else now)
        state[key] = (st, max(0.0, hours(since, now)))

    model = Model(samples(db, a.run))
    fin, blocked = simulate(units, model, state, a.slots, a.stack_in_lane)
    worst, _ = simulate(units, model, state, a.slots, a.stack_in_lane,
                        scale=(model.spread("build", "") + model.spread("land", "")) / 2)

    open_units = [k for k in units if state[k][0] not in DONE]
    est_open = [fin[k] for k in open_units if fin[k] is not None]
    nb, nl = model.n("build"), model.n("land")
    print(f"  ESTIMATE  build {fmt_h(model.est('build', '')).strip()} · land {fmt_h(model.est('land', '')).strip()} per unit"
          f"  (from {nb} build and {nl} land samples; sharpens as units finish)")
    if not open_units:
        print("  overall   all units finished")
        return
    if est_open:
        h = max(est_open)
        w = max(x for k, x in worst.items() if k in open_units and x is not None)
        print(f"  overall   ~{fmt_h(h).strip()} left  -> {fmt_clock(now, h)}   (slow case {fmt_h(w).strip()} -> {fmt_clock(now, w)})"
              + (f"   + {len(blocked)} unit(s) waiting on the owner, not counted" if blocked else ""))
    else:
        print("  overall   no estimate: everything open waits on the owner")

    # In-flight actions
    live = [k for k in open_units if state[k][0] in {"working"} | LANDING]
    if live:
        print("\n  in flight              stage   elapsed  expected  left")
        for k in sorted(live, key=lambda k: units[k]["lane"]):
            st, el = state[k]
            stage = "build" if st == "working" else "land"
            e = model.est(stage, units[k]["kind"])
            left = e - el
            flag = "  OVERDUE" if left < 0 else ""
            print(f"    {k:<6} {units[k]['lane'][:13]:<13} {stage:<6} {fmt_h(el)}   {fmt_h(e)}   {fmt_h(max(left, 0))}{flag}")

    # Lanes (phases)
    lanes = {}
    for k, u in units.items():
        lanes.setdefault(u["lane"], []).append(k)
    print("\n  lane            done   left  finish")
    for lane in sorted(lanes, key=lambda l: max([fin[k] or 0 for k in lanes[l]] or [0]), reverse=True):
        ks = lanes[lane]
        done = sum(state[k][0] in DONE for k in ks)
        if done == len(ks):
            continue
        if any(k in blocked for k in ks):
            waits = " ".join(sorted(k for k in ks if state[k][0] == "parked")) or "a parked unit"
            print(f"    {lane[:13]:<13} {done:>2}/{len(ks):<2}   --    waits on the owner ({waits})")
            continue
        h = max(fin[k] for k in ks if fin[k] is not None)
        print(f"    {lane[:13]:<13} {done:>2}/{len(ks):<2} {fmt_h(h)}  {fmt_clock(now, h)}")


if __name__ == "__main__":
    main()
