-- BRAIN.db schema
-- Project knowledge database for the brain skill system.
-- Stores decisions, tasks, questions, insights, notes, milestones, session logs, and mantra.

CREATE TABLE IF NOT EXISTS logs (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at      TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
  type            TEXT NOT NULL CHECK (type IN ('note', 'decision', 'question', 'insight', 'task', 'milestone')),
  title           TEXT NOT NULL,
  body            TEXT,
  tags            TEXT,
  status          TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'done', 'blocked', 'dropped', 'superseded')),
  parent_id       INTEGER REFERENCES logs(id),
  meta            TEXT,
  priority        INTEGER,
  pillar          TEXT,
  focus           INTEGER NOT NULL DEFAULT 0,
  importance      INTEGER NOT NULL DEFAULT 5,
  tier            TEXT NOT NULL DEFAULT 'warm' CHECK (tier IN ('hot', 'warm', 'cold', 'archived')),
  completed_at    TEXT,
  supersedes      INTEGER REFERENCES logs(id),
  superseded_by   INTEGER REFERENCES logs(id)
);

CREATE INDEX IF NOT EXISTS idx_logs_type_status ON logs(type, status);
CREATE INDEX IF NOT EXISTS idx_logs_pillar ON logs(pillar);
CREATE INDEX IF NOT EXISTS idx_logs_parent_id ON logs(parent_id);
CREATE INDEX IF NOT EXISTS idx_logs_focus ON logs(focus) WHERE focus = 1;
CREATE INDEX IF NOT EXISTS idx_logs_tier ON logs(tier);

CREATE VIRTUAL TABLE IF NOT EXISTS logs_fts USING fts5(
  title, body, tags,
  content='logs',
  content_rowid='id'
);

-- Keep FTS index in sync
CREATE TRIGGER IF NOT EXISTS logs_ai AFTER INSERT ON logs BEGIN
  INSERT INTO logs_fts(rowid, title, body, tags) VALUES (new.id, new.title, new.body, new.tags);
END;
CREATE TRIGGER IF NOT EXISTS logs_ad AFTER DELETE ON logs BEGIN
  INSERT INTO logs_fts(logs_fts, rowid, title, body, tags) VALUES ('delete', old.id, old.title, old.body, old.tags);
END;
CREATE TRIGGER IF NOT EXISTS logs_au AFTER UPDATE ON logs BEGIN
  INSERT INTO logs_fts(logs_fts, rowid, title, body, tags) VALUES ('delete', old.id, old.title, old.body, old.tags);
  INSERT INTO logs_fts(rowid, title, body, tags) VALUES (new.id, new.title, new.body, new.tags);
END;

CREATE TABLE IF NOT EXISTS sessions (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  started_at      TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
  ended_at        TEXT,
  agent           TEXT,
  goals           TEXT,
  summary         TEXT,
  key_files       TEXT,
  pid             INTEGER
);

CREATE TABLE IF NOT EXISTS journal (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at      TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
  session_id      TEXT,
  content         TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS mantra (
  content         TEXT,
  updated_at      TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
);
