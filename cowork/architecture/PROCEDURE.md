# CTO Procedure

Re-runnable architecture observatory. Three phases: scan the codebase structure, synthesize AI-powered summaries and diagrams, generate a self-contained HTML document. Each run stores structured data in CTO.db for delta tracking across runs.

## Input

Optional argument: `$ARGUMENTS`

Dispatch:
- Empty or `full` → full run (all three phases)
- `scan` → Phase 1 only (structural analysis, populate DB)
- `output` → Phase 3 only (regenerate HTML from existing DB data, skip scan and synthesis)
- `delta` → Show delta report from last two runs (no new scan)

---

## PHASE 1 — SCAN (automated, no interaction)

Structural analysis of the codebase. No AI calls. Populates CTO.db with components, relationships, and metrics.

### Step 0 — Initialize

**CTO.db** lives at `cowork/architecture/CTO.db`. If it doesn't exist, create it:
```bash
sqlite3 cowork/architecture/CTO.db < cowork/architecture/schema.sql
sqlite3 cowork/architecture/CTO.db < cowork/architecture/seed.sql
```

Load project context:
```sql
SELECT key, value FROM context WHERE active = 1 ORDER BY key;
```

Create a run record:
```sql
INSERT INTO runs (git_sha, git_branch, project_root)
VALUES ('<git rev-parse --short HEAD>', '<git branch --show-current>', '<pwd>');
```
Save the returned run ID for use throughout.

### Step 1 — Directory discovery

Walk the repo to identify subsystems and their boundaries.

```bash
# Find all package.json files (potential subsystem roots)
find . -name 'package.json' -not -path '*/node_modules/*' -not -path '*/dist/*' -maxdepth 3

# Find deploy configs (adapt to your stack)
# Cloudflare: find . -name 'wrangler.toml' -not -path '*/node_modules/*'
# Docker: find . -name 'Dockerfile' -not -path '*/node_modules/*'
# Serverless: find . -name 'serverless.yml' -not -path '*/node_modules/*'

# Find entry points
find . -name 'index.ts' -o -name 'index.js' -o -name 'main.py' -o -name 'main.go' \
  | grep -v node_modules | grep -v dist
```

For each discovered subsystem:
1. Check if a context entry exists (`subsystem.<path>`) — use its description
2. If no context entry, infer the role from directory contents:
   - Has deploy config (wrangler.toml, Dockerfile, etc.) → `service` role
   - Has `src/commands/` or `bin/` → `cli` role
   - Has `src/pages/` or `src/routes/` → `app` role
   - Has `package.json` only → `library` role
   - Has tests only → `test` role
3. Insert a component for the subsystem directory itself

### Step 2 — File-level component discovery

For each subsystem, discover individual source files. Adapt the file extensions to the project's language:

```bash
# TypeScript/JavaScript
find <subsystem_path> -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
  | grep -v node_modules | grep -v dist | grep -v '.d.ts' | grep -v '.test.' | grep -v '.spec.'

# Python
find <subsystem_path> -name '*.py' | grep -v __pycache__ | grep -v '.test_'

# Go
find <subsystem_path> -name '*.go' | grep -v '_test.go'

# Rust
find <subsystem_path> -name '*.rs'
```

For each file:
1. Count lines: `wc -l < <file>`
2. Count exports: language-specific (grep `^export ` for TS, `^def ` for Python, `^func ` for Go)
3. Count imports: language-specific (grep `^import ` for TS/Python, `^import ` for Go)
4. Infer role from filename and location:
   - `index.*` or `main.*` in subsystem root → `entrypoint`
   - Files in `commands/` or `cmd/` → `cli-command`
   - Files in `pages/` or `routes/` → `page` or `route`
   - Files in `test/` or `tests/` → skip
   - Config files → `config`
5. Insert into `components` table

### Step 3 — Import graph

Parse import statements to build the dependency graph. Adapt regex to the project's language:

```bash
# TypeScript/JavaScript — relative imports
grep -rn "^import .* from ['\"]\./" --include='*.ts' --include='*.js' <subsystem_path> \
  | grep -v node_modules | grep -v dist

# Python
grep -rn "^from \.\|^import " --include='*.py' <subsystem_path> | grep -v __pycache__
```

For each import:
1. Extract the imported path
2. Resolve relative paths to actual files
3. Look up source and target component IDs
4. Insert into `relationships` with type='imports'

After all imports are parsed, compute fan_in and fan_out:
```sql
-- Fan out
INSERT INTO metrics (run_id, component_id, metric, value)
SELECT <run_id>, r.source_component_id, 'fan_out', COUNT(*)
FROM relationships r WHERE r.run_id = <run_id> AND r.type = 'imports'
GROUP BY r.source_component_id;

-- Fan in
INSERT INTO metrics (run_id, component_id, metric, value)
SELECT <run_id>, r.target_component_id, 'fan_in', COUNT(*)
FROM relationships r WHERE r.run_id = <run_id> AND r.type = 'imports'
GROUP BY r.target_component_id;
```

### Step 4 — Deploy topology

Detect what deploys where based on config files found in Step 1:

For each deploy config:
1. Extract service name, routes, ports, bindings
2. Create a component for the deploy target (role='deploy-target')
3. Insert relationships: subsystem → deploy target (type='deploys_to')
4. For service-to-service connections: insert relationships (type='service_binding' or 'api_call')

### Step 5 — Git intelligence

For each subsystem and top source files, gather git history:

```bash
# Change frequency (commits in last 90 days)
git log --oneline --since='90 days ago' -- <path> | wc -l

# Code age (days since last modification)
git log -1 --format=%at -- <path>

# Top contributors
git shortlog -sn --since='90 days ago' -- <path> | head -3
```

Insert metrics: `change_frequency`, `code_age_days`

For the top 50 most-changed files across the repo:
```bash
git log --name-only --pretty=format: --since='90 days ago' -- '*.ts' '*.js' '*.py' '*.go' \
  | grep -v '^$' | sort | uniq -c | sort -rn | head -50
```

### Step 6 — Cross-subsystem relationships

Detect how subsystems connect beyond direct imports:

```bash
# Service/API calls (adapt patterns to your project)
grep -rn 'fetch\|axios\|http\.get\|requests\.' --include='*.ts' --include='*.py' \
  --exclude-dir=node_modules .

# Environment-based service references
grep -rn 'env\.\|process\.env\.\|os\.environ' --include='*.ts' --include='*.py' \
  --exclude-dir=node_modules . | grep -i 'service\|api\|url\|host'
```

For each detected connection, insert into `relationships` with appropriate type.

### Step 7 — Update component history

```sql
INSERT INTO component_history (path, first_seen_run_id, last_seen_run_id, run_count, last_role, last_subsystem, last_loc)
SELECT path, <run_id>, <run_id>, 1, role, subsystem, loc FROM components WHERE run_id = <run_id>
ON CONFLICT(path) DO UPDATE SET
  last_seen_run_id = <run_id>,
  run_count = run_count + 1,
  last_role = excluded.last_role,
  last_subsystem = excluded.last_subsystem,
  last_loc = excluded.last_loc;
```

---

## PHASE 2 — SYNTHESIZE (AI-powered, subagent fan-out)

Uses the structured data from Phase 1 plus source file reading to produce human-readable summaries and diagrams.

### Step 8 — Subsystem summarization

Query distinct subsystems from the current run:
```sql
SELECT DISTINCT subsystem FROM components WHERE run_id = <run_id> AND subsystem IS NOT NULL;
```

For each subsystem, spawn a subagent (using the Agent tool) with this prompt template:

> You are analyzing the `<subsystem>` subsystem of a project. Read the key files listed below and produce a structured summary.
>
> **Key files to read:** <list entry points, configs, and top-3 files by LOC>
> **Known context:** <context entry for this subsystem if it exists>
> **Metrics:** <component count, total LOC, top files by LOC>
>
> Produce:
> 1. A 2-3 sentence description of what this subsystem does
> 2. Its primary responsibility (one phrase)
> 3. Key components (top 5 files with one-line descriptions)
> 4. External dependencies (npm packages, APIs, services it connects to)
> 5. How it connects to other subsystems
>
> Return as plain text, not JSON.

Store the description back:
```sql
UPDATE components SET description = '<AI summary>'
WHERE run_id = <run_id> AND path = '<subsystem_path>';
```

### Step 9 — Mermaid diagram generation

Generate diagrams at three C4 levels using data from CTO.db.

**Context diagram (L0):**
System boundary showing the project, its external actors, and external services it connects to. Build from subsystem descriptions and relationship data.

**Container diagram (L1):**
Per-subsystem boxes with component counts and LOC, connection arrows between subsystems. Include deploy targets.

**Component diagram (L2):**
One diagram per major subsystem showing internal file structure. Only include files with LOC > 50 or fan_in > 2 to keep diagrams readable.

Store diagram source in the `artifacts` table:
```sql
INSERT INTO artifacts (run_id, type, name, content)
VALUES (<run_id>, 'mermaid', '<diagram_name>', '<mermaid_source>');
```

### Step 10 — Data flow annotation

Trace major data flow paths through the relationship graph and produce human-readable descriptions. Store as artifacts.

---

## PHASE 3 — OUTPUT (HTML generation)

Generate a self-contained HTML document from CTO.db data.

### Step 11 — Build HTML

Generate `cowork/architecture/architecture.html` with:

**Page structure:**
1. Header with project name, run date, git SHA, run number
2. Executive Summary — context diagram, 1-paragraph description, key numbers
3. Architecture Overview — container diagram, per-subsystem cards
4. Deploy Topology — what ships where, binding details
5. Complexity Hotspots — top 15 files by complexity score
6. Git Intelligence — most-changed files, code age, contributor concentration
7. Delta Report — changes since prior run (or "First run — no prior data")

**Styling:**
- Dark theme: `background: #0a0a0a; color: #e0e0e0;`
- Cards with `border: 1px solid #222; border-radius: 12px; background: #111;`
- Tables with sticky headers, hover highlighting
- Mermaid.js from CDN with dark theme: `mermaid.initialize({ theme: 'dark' })`
- Responsive layout

### Step 12 — Finalize run

Update the run record:
```sql
UPDATE runs SET
  completed_at = datetime('now', 'localtime'),
  summary = json_object(
    'subsystem_count', <count>,
    'component_count', <count>,
    'total_loc', <total>,
    'relationship_count', <count>,
    'hotspot_top', '<top file by complexity>',
    'delta_new', <new_count>,
    'delta_removed', <removed_count>,
    'delta_changed', <changed_count>
  )
WHERE id = <run_id>;
```

### Step 13 — Generate dated markdown summary

Write a dated summary file to `cowork/architecture/YYYY-MM-DD_architecture-summary.md`. This is the git-diffable record of the architecture at this point in time. Include:

- Overview paragraph
- Subsystem table (path, files, LOC, one-line description)
- Deploy topology table
- Top 10 complexity hotspots
- Top 10 git hotspots (90 days)
- Key architectural patterns (from context table)
- Delta section (changes since prior run, or "baseline" for first run)

Print summary:
```
**Architecture scan complete**

Subsystems: N
Components: N (N new, N removed, N changed)
Total LOC: N
Relationships: N
Complexity hotspot: <top file>

Output: cowork/architecture/architecture.html
Summary: cowork/architecture/YYYY-MM-DD_architecture-summary.md
```

---

## Delta tracking

When a prior run exists, compute deltas automatically:

```sql
-- New components (first seen this run)
SELECT path, subsystem, role, loc FROM component_history
WHERE first_seen_run_id = <run_id>;

-- Removed components (last seen in a prior run, not this one)
SELECT path, last_subsystem, last_role, last_loc FROM component_history
WHERE last_seen_run_id < <run_id> AND last_seen_run_id = <run_id> - 1;

-- Changed components (LOC delta)
SELECT * FROM v_architectural_drift;

-- Subsystem growth
SELECT
  curr.subsystem,
  curr.total_loc AS current_loc,
  prev.total_loc AS previous_loc,
  curr.total_loc - prev.total_loc AS loc_delta
FROM v_subsystem_summary curr
LEFT JOIN (
  SELECT subsystem, SUM(loc) AS total_loc
  FROM components WHERE run_id = <run_id> - 1
  GROUP BY subsystem
) prev ON prev.subsystem = curr.subsystem
WHERE curr.total_loc != COALESCE(prev.total_loc, 0);
```

The delta report section in the HTML shows:
- New components with green indicators
- Removed components with red indicators
- Changed components with LOC delta arrows (↑↓)
- Subsystem growth comparison
