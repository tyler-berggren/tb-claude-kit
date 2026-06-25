-- VIBE-AUDIT.db schema v1
-- Self-learning audit database for the vibe-audit skill.
-- Tracks scan patterns, findings, dispositions, suppressions, and Bayesian effectiveness.

CREATE TABLE IF NOT EXISTS schema_version (
  version INTEGER NOT NULL,
  applied_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
);
INSERT INTO schema_version (version) VALUES (1);

CREATE TABLE IF NOT EXISTS runs (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  started_at   TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
  completed_at TEXT,
  scope        TEXT NOT NULL DEFAULT 'full',
  git_sha      TEXT,
  git_branch   TEXT,
  summary      TEXT,
  brain_milestone_id INTEGER
);

CREATE TABLE IF NOT EXISTS patterns (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  slug         TEXT NOT NULL UNIQUE,
  category     TEXT NOT NULL,
  layer        INTEGER NOT NULL DEFAULT 1,
  name         TEXT NOT NULL,
  description  TEXT,
  detection    TEXT,
  severity     TEXT NOT NULL DEFAULT 'warning',
  origin       TEXT NOT NULL DEFAULT 'builtin',
  lifecycle    TEXT NOT NULL DEFAULT 'stable',
  enabled      INTEGER NOT NULL DEFAULT 1,
  created_at   TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
  updated_at   TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
  true_positive_count  INTEGER NOT NULL DEFAULT 0,
  false_positive_count INTEGER NOT NULL DEFAULT 0,
  deferred_count       INTEGER NOT NULL DEFAULT 0,
  precision    REAL NOT NULL DEFAULT 0.5,
  times_fired  INTEGER NOT NULL DEFAULT 0,
  runs_fired   INTEGER NOT NULL DEFAULT 0,
  total_runs   INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS findings (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id       INTEGER NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
  pattern_id   INTEGER NOT NULL REFERENCES patterns(id),
  file_path    TEXT,
  line_number  INTEGER,
  fingerprint  TEXT NOT NULL,
  severity     TEXT NOT NULL,
  title        TEXT NOT NULL,
  detail       TEXT,
  code_snippet TEXT,
  disposition  TEXT NOT NULL DEFAULT 'pending',
  disposition_reason TEXT,
  disposition_at TEXT,
  brain_entry_id INTEGER,
  first_seen_run_id INTEGER,
  occurrence_count  INTEGER NOT NULL DEFAULT 1,
  created_at   TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
);

CREATE INDEX IF NOT EXISTS idx_findings_fingerprint ON findings(fingerprint);
CREATE INDEX IF NOT EXISTS idx_findings_run_id ON findings(run_id);
CREATE INDEX IF NOT EXISTS idx_findings_pattern_id ON findings(pattern_id);
CREATE INDEX IF NOT EXISTS idx_findings_disposition ON findings(disposition);

CREATE TABLE IF NOT EXISTS suppressions (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  pattern_id   INTEGER REFERENCES patterns(id),
  file_glob    TEXT,
  path_regex   TEXT,
  content_regex TEXT,
  context_rule TEXT,
  reason       TEXT NOT NULL,
  source       TEXT NOT NULL DEFAULT 'user',
  enabled      INTEGER NOT NULL DEFAULT 1,
  times_applied INTEGER NOT NULL DEFAULT 0,
  created_at   TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
  created_from_finding_id INTEGER REFERENCES findings(id),
  expires_at   TEXT
);

CREATE TABLE IF NOT EXISTS context_memories (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  fact         TEXT NOT NULL,
  affects_patterns TEXT,
  action       TEXT NOT NULL DEFAULT 'suppress',
  created_at   TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
  active       INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS recurrence_chains (
  fingerprint    TEXT PRIMARY KEY,
  first_run_id   INTEGER NOT NULL REFERENCES runs(id),
  last_run_id    INTEGER NOT NULL REFERENCES runs(id),
  total_occurrences INTEGER NOT NULL DEFAULT 1,
  consecutive_runs  INTEGER NOT NULL DEFAULT 1,
  is_regression  INTEGER NOT NULL DEFAULT 0,
  last_disposition TEXT
);

CREATE VIEW IF NOT EXISTS v_pattern_effectiveness AS
SELECT
  p.id, p.slug, p.name, p.category, p.severity, p.lifecycle,
  p.true_positive_count AS tp, p.false_positive_count AS fp,
  p.precision, p.times_fired, p.total_runs,
  CASE WHEN p.total_runs = 0 THEN 0.0
       ELSE ROUND(1.0 * p.runs_fired / p.total_runs, 3)
  END AS hit_rate,
  CASE WHEN p.true_positive_count + p.false_positive_count < 5 THEN 'insufficient_data'
       WHEN p.precision >= 0.7 THEN 'effective'
       WHEN p.precision >= 0.3 THEN 'noisy'
       ELSE 'mostly_false_positives'
  END AS effectiveness_grade
FROM patterns p WHERE p.enabled = 1
ORDER BY p.precision DESC;

CREATE VIEW IF NOT EXISTS v_systemic_weaknesses AS
SELECT
  rc.fingerprint, p.slug, p.name, f.file_path,
  rc.total_occurrences, rc.consecutive_runs, rc.is_regression
FROM recurrence_chains rc
JOIN findings f ON f.fingerprint = rc.fingerprint AND f.run_id = rc.last_run_id
JOIN patterns p ON p.id = f.pattern_id
WHERE rc.consecutive_runs >= 3 OR rc.is_regression = 1
ORDER BY rc.consecutive_runs DESC;
