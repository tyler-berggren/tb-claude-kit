# Vibe Audit Procedure

Safety net for vibe-engineered codebases. The AI wrote the code, the human approved it — this catches what slipped through. Two layers: code scan and architecture guardrails. All findings are brainstormed with the user before committing to the brain as actionable entries.

**No report files.** The brain is the report. Findings become tasks and questions. The audit milestone captures the summary. Delta tracking is structural: prior audit entries that are done = fixed, new scan matches = new, still-open entries = unchanged.

## Input

Optional argument: `$ARGUMENTS`

Dispatch:
- Empty -> full audit (both layers)
- `security` or `sec` -> Layer 1 security checks only
- `monolith` or `size` -> Layer 1 monolith scan only
- `shell` -> Layer 1 shell script safety only
- `deps` -> Layer 1 dependency health only
- Any other text -> full audit, highlight findings related to the argument

---

## PHASE 1 — SCAN (automated, no interaction)

Run all applicable scan steps without asking. Collect findings into a working list. Do NOT write to the brain yet.

### Step 0 — Load prior audit state

**VIBE-AUDIT.db** lives at `cowork/vibe-audit/VIBE-AUDIT.db`. If it doesn't exist, create it from `cowork/vibe-audit/schema.sql` and `cowork/vibe-audit/seed.sql`:
```bash
sqlite3 cowork/vibe-audit/VIBE-AUDIT.db < cowork/vibe-audit/schema.sql
sqlite3 cowork/vibe-audit/VIBE-AUDIT.db < cowork/vibe-audit/seed.sql
```

Load active patterns from VIBE-AUDIT.db:
```sql
SELECT id, slug, category, layer, name, severity, lifecycle, precision,
  true_positive_count, false_positive_count
FROM patterns WHERE enabled = 1 AND lifecycle != 'deprecated'
ORDER BY layer, category;
```

Load suppressions:
```sql
SELECT id, pattern_id, file_glob, path_regex, content_regex, reason
FROM suppressions WHERE enabled = 1
AND (expires_at IS NULL OR expires_at > datetime('now', 'localtime'));
```

Load context memories:
```sql
SELECT id, fact, affects_patterns, action FROM context_memories WHERE active = 1;
```

Create a run record:
```sql
INSERT INTO runs (scope, git_sha, git_branch)
VALUES ('<scope>', '<git rev-parse HEAD>', '<git branch --show-current>');
```
Save the returned run ID for use throughout the audit.

Also load brain DB state:

Find the most recent vibe-audit milestone:
```sql
SELECT id, created_at, body FROM logs
WHERE type = 'milestone' AND tags LIKE '%vibe-audit%'
ORDER BY created_at DESC LIMIT 1;
```

Load open findings from prior audits:
```sql
SELECT id, type, title, body, tags, status FROM logs
WHERE tags LIKE '%vibe-audit%' AND type IN ('task', 'question')
AND status IN ('active', 'blocked')
ORDER BY importance DESC;
```

If no prior audit exists, this is the baseline run — no delta comparison.

### Step 1 — Layer 1: Code Scan

Scan all source files. Exclude `node_modules/`, `dist/`, `.next/`, `build/`, generated files, and `cowork/` markdown.

#### 1a. Monolith files

```bash
find . -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.py' -o -name '*.sh' \) \
  ! -path '*/node_modules/*' ! -path '*/dist/*' ! -path '*/.next/*' ! -path '*/build/*' ! -path '*/cowork/*' \
  -exec wc -l {} + | sort -rn | head -40
```

**Tiers:**
- **Critical (>1000 lines):** Too large for AI agents to work with effectively. Must be split.
- **Warning (>600 lines):** Getting unwieldy. Resist further growth.
- **Watch (>400 lines):** Large enough to note. No action unless growing fast.

For each flagged file: current line count, brief purpose (read first ~30 lines), decomposition suggestion (Critical only).

**Intentional exclusions — do NOT flag:**
- Seed scripts, generated/config files, test fixtures, type declarations (`.d.ts`), lock files, skill definition files (`.claude/skills/**/*.md`)

#### 1b. SQL injection

**What to flag:**
- Template literals containing SQL keywords (`SELECT`, `INSERT`, `UPDATE`, `DELETE`, `PRAGMA`, `CREATE`, `ALTER`, `DROP`) with `${` interpolation NOT inside `.bind()` or `.prepare()`
- String concatenation into SQL: `+ "SELECT`, `+ 'INSERT`
- Shell `sqlite3` commands with unescaped variable interpolation in the query string
- Manual escaping patterns (`.replace(/'/g, "''")`)

**Known intentional patterns to suppress:**
- Schema migration DDL in `scripts/` — not user-input-driven
- Brain skill SQL with hardcoded values or system-generated IDs (not user input)

**Real risks to flag:**
- Any SQL where the interpolated value originates from user input, HTTP request, external API response, or MCP tool input

#### 1c. Secrets hygiene

```bash
# API keys, tokens, secrets outside .env files
grep -rn --include='*.ts' --include='*.js' --include='*.json' --include='*.sh' \
  -E '(api[_-]?key|secret|token|password|credential).*[=:].*[A-Za-z0-9_-]{20,}' \
  --exclude-dir=node_modules --exclude-dir=.git --exclude='*.env*' .

# AWS, Cloudflare, and common provider key patterns
grep -rn --include='*.ts' --include='*.js' --include='*.json' \
  -E '(AKIA[0-9A-Z]{16}|sk-[a-zA-Z0-9]{20,}|CF_API_TOKEN)' \
  --exclude-dir=node_modules --exclude-dir=.git .
```

**Flag:**
- Keys/tokens hardcoded in source files (not `.env`)
- Credentials in committed configs other than `.env`
- Plaintext secrets anywhere

#### 1d. Dependency health

```bash
# Audit each directory that has a package.json
find . -name 'package.json' -not -path '*/node_modules/*' -not -path '*/dist/*' | while read pkg; do
  dir=$(dirname "$pkg")
  echo "=== $dir ==="
  (cd "$dir" && npm audit --json 2>/dev/null || echo "no lockfile / no audit")
done

# Check for suspicious postinstall scripts
grep -r '"postinstall"' node_modules/*/package.json 2>/dev/null | head -20
```

#### 1e. Shell script safety

Scan all `.sh` files:

```bash
find . -name '*.sh' ! -path '*/node_modules/*' -print
```

For each script, check:
- Missing `set -e` or `set -euo pipefail` at the top
- Unquoted variable expansions: `$VAR` instead of `"$VAR"` (especially in `rm`, `mv`, `cp`, `cd`)
- Unsafe temp file creation (not using `mktemp`)
- `eval` with variable arguments
- Missing input validation for script arguments

#### 1f. Vibe-code artifacts

Patterns specific to AI-generated code that slipped through review:

```bash
# TODO/FIXME/HACK comments left by AI
grep -rn --include='*.ts' --include='*.tsx' --include='*.js' --include='*.py' -E '(TODO|FIXME|HACK|XXX):?' \
  --exclude-dir=node_modules .
```

Check for:
- Unused imports (imported but never referenced in the file)
- Orphan source files (exist in `src/` but not imported anywhere)
- TODO/FIXME comments that represent unfinished AI work
- Overly complex abstractions (files with many exports but few consumers)

#### 1g. Code duplication

Identify duplicated logic across the codebase that should be centralized into shared helpers.

**What to flag:**
- **Critical**: Same logic (>10 lines) copy-pasted in 3+ locations — extract to shared module
- **Warning**: Same pattern (5-10 lines) in 2+ locations — candidate for shared helper
- **Info**: Similar but not identical patterns that could benefit from a shared abstraction

**What NOT to flag:**
- Test fixtures or seed data with similar structure
- Boilerplate required by frameworks
- Patterns that are simple enough that a shared abstraction would be over-engineering (1-2 line expressions)

#### 1h. CORS configuration

```bash
grep -rn 'Access-Control-Allow-Origin.*\*' --include='*.ts' --include='*.js' --exclude-dir=node_modules .
```

Flag `Access-Control-Allow-Origin: *` in production code. Verify CORS origins are explicitly allowlisted.

#### 1i. Frontend secrets

```bash
grep -rn 'sk_live_\|sk-proj-\|service_role\|SUPABASE_SERVICE_ROLE' --include='*.ts' --include='*.tsx' --include='*.js' --exclude-dir=node_modules .
```

Flag live API keys in any client-visible code.

#### 1j. Debug routes in production

```bash
grep -rn '"/_dev\|"/debug\|"/test/' --include='*.ts' --include='*.js' --exclude-dir=node_modules .
```

Flag test/debug endpoints that are reachable in production.

#### Step 1 epilogue — Record findings in VIBE-AUDIT.db

After all scan steps complete, for each finding:

1. **Compute fingerprint**: Use pattern slug + file path + surrounding context to create a stable identifier
2. **Check suppressions**: Skip if any suppression rule matches (pattern + file glob)
3. **Check prior dispositions**: If this fingerprint was `false_positive` in the most recent prior run, auto-suppress with note
4. **Insert into findings**:
```sql
INSERT INTO findings (run_id, pattern_id, file_path, line_number, fingerprint, severity, title, detail, code_snippet)
VALUES (<run_id>, <pattern_id>, '<file>', <line>, '<fingerprint>', '<severity>', '<title>', '<detail>', '<snippet>');
```

5. **Update pattern stats** after scan:
```sql
UPDATE patterns SET total_runs = total_runs + 1 WHERE enabled = 1 AND lifecycle != 'deprecated';
UPDATE patterns SET times_fired = times_fired + <count>, runs_fired = runs_fired + 1
WHERE id = <pattern_id>; -- for each pattern that fired
```

### Step 2 — Layer 2: Architecture Guardrails

Walk the guardrail checklist in `cowork/vibe-audit/GUARDRAILS.md`. For each item, verify the current state and note gaps.

---

## PHASE 2 — BRAINSTORM (interactive)

**Do not skip this phase. Do not auto-commit findings to the brain.**

### Step 3 — Present findings (enhanced with VIBE-AUDIT.db data)

Query VIBE-AUDIT.db for pattern effectiveness to enrich the presentation:
```sql
SELECT slug, precision, true_positive_count, false_positive_count, effectiveness_grade
FROM v_pattern_effectiveness WHERE tp + fp > 0;
```

Organize all findings from Phase 1 into a clear summary:

```
## Scan Results

### Layer 1 — Code
[For each category with findings]
**Category:** N findings
- Finding 1 — severity, file:line, what's wrong, why it matters
- Finding 2 — ...

### Layer 2 — Architecture Guardrails
- Implemented: N items
- Gaps: N items (list each)
- Not yet applicable: N items
- Missing: N items (list each)

### Delta from Last Audit
- Fixed (prior findings now done): N
- New (not seen before): N
- Unchanged (still open): N
```

### Step 4 — Discuss

This is a conversation, not a report. For each finding:

- **Is this real?** Some grep matches are false positives. Some "missing" guardrails aren't applicable yet. Ask the user.
- **Is this already mitigated?** Context matters. The user may know about defenses the scan can't see.
- **How severe is this actually?** The scan assigns severity mechanically. The user knows which code paths are in production vs prototype.
- **Should this be a task or a question?** Tasks have clear remediation. Questions need more investigation first.

**VIBE-AUDIT.db-enhanced discussion:**
- Show pattern effectiveness alongside findings: "This pattern has 70% precision across N runs — it's usually real"
- Auto-dismiss with explanation when a pattern has >80% false positive rate on the matching file type
- Flag regressions prominently: "This finding was fixed after a prior run but has reappeared — regression"
- When user marks a finding as false positive, propose a suppression rule: "Create a suppression for [pattern] on [file glob]?"

Push back on dismissals that seem risky. Agree with dismissals that make sense. This is two engineers reviewing findings at a whiteboard.

### Step 5 — User confirms

After discussion, get explicit confirmation on which findings enter the brain. For each confirmed finding, agree on:
- Type: `task` (clear fix) or `question` (needs investigation)
- Title: concise, actionable
- Severity/importance: 1-10 scale
- Pillar: which area of the project
- Tags: always include `vibe-audit`, plus relevant tags

---

## PHASE 3 — COMMIT TO BRAIN AND VIBE-AUDIT.db

### Step 6a — Record dispositions in VIBE-AUDIT.db

For each finding discussed in Phase 2, record the disposition:

```sql
UPDATE findings SET
  disposition = '<confirmed|false_positive|wont_fix|deferred>',
  disposition_reason = '<reason from discussion>',
  disposition_at = datetime('now', 'localtime')
WHERE id = <finding_id>;
```

Update Bayesian counters on the pattern:
```sql
-- For confirmed findings:
UPDATE patterns SET
  true_positive_count = true_positive_count + 1,
  precision = (1.0 + true_positive_count + 1) / (2.0 + true_positive_count + 1 + false_positive_count)
WHERE id = <pattern_id>;

-- For false positive findings:
UPDATE patterns SET
  false_positive_count = false_positive_count + 1,
  precision = (1.0 + true_positive_count) / (2.0 + true_positive_count + false_positive_count + 1)
WHERE id = <pattern_id>;
```

### Step 6b — Write confirmed findings to brain

For each confirmed finding, create a brain entry:

```sql
INSERT INTO logs (type, title, body, tags, importance, pillar, status, created_at, meta)
VALUES ('<type>', '<title>', '<description + context + recommended fix>',
  '<tags,vibe-audit>', <importance>, '<pillar>', 'active',
  datetime('now', 'localtime'),
  json_object('from_audit', <audit_milestone_id>));
```

Every entry must:
- Include `vibe-audit` in tags (for delta tracking on next run)
- Have `meta.from_audit` pointing to this audit's milestone ID (for lineage)
- Have a body with enough context that a future session can act on it without re-scanning

### Step 7 — Log audit milestone and finalize run

Log brain milestone:
```sql
INSERT INTO logs (type, title, body, tags, importance, tier, status, created_at)
VALUES ('milestone',
  'Vibe Audit — <date>',
  '<summary: what was scanned, key findings, delta from last audit, confirmed entries created>',
  'milestone,vibe-audit',
  7, 'hot', 'active',
  datetime('now', 'localtime'));
```

Finalize the VIBE-AUDIT.db run record:
```sql
UPDATE runs SET
  completed_at = datetime('now', 'localtime'),
  summary = json_object(
    'total_findings', <total>,
    'new', <new_count>,
    'fixed', <fixed_count>,
    'unchanged', <unchanged_count>,
    'confirmed', <confirmed_count>,
    'false_positive', <fp_count>
  ),
  brain_milestone_id = <milestone_id>
WHERE id = <run_id>;
```

### Step 8 — Housekeeping

Recalculate tiers and regenerate `cowork/brain/BRAIN.md` digest.

Print final summary:

```
**Vibe Audit complete**

Layer 1 (code): X findings confirmed
Layer 2 (guardrails): X gaps flagged

Delta: N fixed, N new, N unchanged
Milestone logged as #<id>
```
