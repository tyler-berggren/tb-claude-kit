-- Seed context for a new project
-- Edit these entries to match your project's subsystems and patterns.
-- The scan engine discovers files and relationships automatically —
-- context entries help it classify and describe what it finds.

-- Project metadata (edit these)
INSERT INTO context (key, value, source) VALUES
  ('project.name', 'My Project', 'user'),
  ('project.description', 'Brief description of what this project does', 'user'),
  ('project.type', 'monorepo', 'user');

-- Subsystem definitions (add one per top-level directory that represents a logical unit)
-- Format: subsystem.<path> = description
-- Example entries (replace with your own):
--
-- INSERT INTO context (key, value, source) VALUES
--   ('subsystem.api', 'Backend API server — REST endpoints, auth, database access.', 'user'),
--   ('subsystem.web', 'Frontend web app — React/Vue/Svelte SPA.', 'user'),
--   ('subsystem.shared', 'Shared libraries — types, utils, constants used across subsystems.', 'user'),
--   ('subsystem.scripts', 'Build and maintenance scripts.', 'user'),
--   ('subsystem.docs', 'Documentation site.', 'user');

-- Architectural patterns (add notable patterns specific to your project)
-- Format: pattern.<name> = description
-- Example entries:
--
-- INSERT INTO context (key, value, source) VALUES
--   ('pattern.module_federation', 'Micro-frontends loaded via Module Federation at runtime.', 'user'),
--   ('pattern.event_sourcing', 'Domain events stored in event store, projections rebuilt from events.', 'user');
