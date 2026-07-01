-- CTO.db schema v1
-- Re-runnable architecture observatory. Tracks components, relationships,
-- complexity metrics, and architectural drift across runs.

CREATE TABLE IF NOT EXISTS schema_version (
  version INTEGER NOT NULL,
  applied_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
);
INSERT INTO schema_version (version) VALUES (1);

-- Every execution of /cto
CREATE TABLE IF NOT EXISTS runs (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  started_at   TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
  completed_at TEXT,
  git_sha      TEXT,
  git_branch   TEXT,
  scope        TEXT NOT NULL DEFAULT 'full',
  project_root TEXT,
  summary      TEXT
);

-- Discovered architectural components (files, directories, deploy targets)
CREATE TABLE IF NOT EXISTS components (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id       INTEGER NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
  path         TEXT NOT NULL,
  name         TEXT NOT NULL,
  role         TEXT NOT NULL DEFAULT 'unknown',
  subsystem    TEXT,
  loc          INTEGER NOT NULL DEFAULT 0,
  export_count INTEGER NOT NULL DEFAULT 0,
  import_count INTEGER NOT NULL DEFAULT 0,
  description  TEXT,
  created_at   TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
);

CREATE INDEX IF NOT EXISTS idx_components_run_id ON components(run_id);
CREATE INDEX IF NOT EXISTS idx_components_subsystem ON components(subsystem);
CREATE INDEX IF NOT EXISTS idx_components_path ON components(path);

-- Relationships between components
CREATE TABLE IF NOT EXISTS relationships (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id                INTEGER NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
  source_component_id   INTEGER NOT NULL REFERENCES components(id) ON DELETE CASCADE,
  target_component_id   INTEGER NOT NULL REFERENCES components(id) ON DELETE CASCADE,
  type                  TEXT NOT NULL,
  detail                TEXT,
  created_at            TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
);

CREATE INDEX IF NOT EXISTS idx_relationships_run_id ON relationships(run_id);
CREATE INDEX IF NOT EXISTS idx_relationships_type ON relationships(type);

-- Per-component metrics per run
CREATE TABLE IF NOT EXISTS metrics (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id       INTEGER NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
  component_id INTEGER NOT NULL REFERENCES components(id) ON DELETE CASCADE,
  metric       TEXT NOT NULL,
  value        REAL NOT NULL DEFAULT 0,
  created_at   TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
);

CREATE INDEX IF NOT EXISTS idx_metrics_run_id ON metrics(run_id);
CREATE INDEX IF NOT EXISTS idx_metrics_component_id ON metrics(component_id);

-- Project-specific context that persists across runs
CREATE TABLE IF NOT EXISTS context (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,
  key      TEXT NOT NULL UNIQUE,
  value    TEXT NOT NULL,
  source   TEXT NOT NULL DEFAULT 'discovered',
  active   INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
);

-- Cross-run component tracking
CREATE TABLE IF NOT EXISTS component_history (
  path             TEXT PRIMARY KEY,
  first_seen_run_id INTEGER NOT NULL REFERENCES runs(id),
  last_seen_run_id  INTEGER NOT NULL REFERENCES runs(id),
  run_count        INTEGER NOT NULL DEFAULT 1,
  last_role        TEXT,
  last_subsystem   TEXT,
  last_loc         INTEGER NOT NULL DEFAULT 0
);

-- Generated diagrams and summaries per run
CREATE TABLE IF NOT EXISTS artifacts (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id   INTEGER NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
  type     TEXT NOT NULL,
  name     TEXT NOT NULL,
  content  TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
);

CREATE INDEX IF NOT EXISTS idx_artifacts_run_id ON artifacts(run_id);

-- Complexity hotspots: components ranked by combined LOC + fan_out + change_frequency
CREATE VIEW IF NOT EXISTS v_complexity_hotspots AS
SELECT
  c.id, c.path, c.name, c.subsystem, c.role, c.loc,
  COALESCE(fan_out.value, 0) AS fan_out,
  COALESCE(change_freq.value, 0) AS change_frequency,
  (c.loc * 0.4 + COALESCE(fan_out.value, 0) * 50 + COALESCE(change_freq.value, 0) * 10) AS complexity_score
FROM components c
LEFT JOIN metrics fan_out ON fan_out.component_id = c.id AND fan_out.metric = 'fan_out' AND fan_out.run_id = c.run_id
LEFT JOIN metrics change_freq ON change_freq.component_id = c.id AND change_freq.metric = 'change_frequency' AND change_freq.run_id = c.run_id
WHERE c.run_id = (SELECT MAX(id) FROM runs)
ORDER BY complexity_score DESC;

-- Architectural drift: components whose LOC changed between last two runs
CREATE VIEW IF NOT EXISTS v_architectural_drift AS
SELECT
  ch.path,
  ch.last_subsystem AS subsystem,
  ch.last_role AS role,
  ch.last_loc AS current_loc,
  prev.loc AS previous_loc,
  ch.last_loc - prev.loc AS loc_delta,
  CASE
    WHEN prev.loc = 0 THEN 'new'
    WHEN ch.last_loc = 0 THEN 'removed'
    WHEN ch.last_loc > prev.loc THEN 'grew'
    WHEN ch.last_loc < prev.loc THEN 'shrank'
    ELSE 'unchanged'
  END AS drift_type
FROM component_history ch
JOIN components prev ON prev.path = ch.path
  AND prev.run_id = (SELECT MAX(id) FROM runs WHERE id < (SELECT MAX(id) FROM runs))
WHERE ch.last_seen_run_id = (SELECT MAX(id) FROM runs)
  AND (ch.last_loc != prev.loc OR ch.last_role != prev.role)
ORDER BY ABS(ch.last_loc - prev.loc) DESC;

-- Subsystem summary: rollup by subsystem
CREATE VIEW IF NOT EXISTS v_subsystem_summary AS
SELECT
  c.subsystem,
  COUNT(*) AS component_count,
  SUM(c.loc) AS total_loc,
  AVG(c.loc) AS avg_loc,
  MAX(c.loc) AS max_loc,
  (SELECT COUNT(*) FROM relationships r WHERE r.run_id = c.run_id
    AND (r.source_component_id IN (SELECT id FROM components WHERE subsystem = c.subsystem AND run_id = c.run_id)
      OR r.target_component_id IN (SELECT id FROM components WHERE subsystem = c.subsystem AND run_id = c.run_id))
  ) AS relationship_count
FROM components c
WHERE c.run_id = (SELECT MAX(id) FROM runs)
GROUP BY c.subsystem
ORDER BY total_loc DESC;
