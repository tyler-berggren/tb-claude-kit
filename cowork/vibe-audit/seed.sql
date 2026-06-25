-- Seed builtin patterns for VIBE-AUDIT.db
-- Generic patterns applicable to any project. Add project-specific patterns per project.

-- Layer 1: Code scan patterns
INSERT INTO patterns (slug, category, layer, name, description, severity, origin, lifecycle) VALUES
  ('monolith-critical', 'monolith', 1, 'Monolith file (>1000 lines)', 'Source file too large for AI agents to work with effectively. Must be split.', 'critical', 'builtin', 'stable'),
  ('monolith-warning', 'monolith', 1, 'Monolith file (>600 lines)', 'Source file getting unwieldy. Resist further growth.', 'warning', 'builtin', 'stable'),
  ('monolith-watch', 'monolith', 1, 'Large file (>400 lines)', 'Large enough to note. No action unless growing fast.', 'info', 'builtin', 'stable'),
  ('sql-injection-template-literal', 'sql-injection', 1, 'SQL injection via template literal', 'Template literal with SQL keywords and ${} interpolation outside .bind()/.prepare()', 'critical', 'builtin', 'stable'),
  ('sql-injection-string-concat', 'sql-injection', 1, 'SQL injection via string concatenation', 'String concatenation into SQL query', 'critical', 'builtin', 'stable'),
  ('sql-injection-shell-sqlite3', 'sql-injection', 1, 'SQL injection in shell sqlite3', 'Shell sqlite3 command with unescaped variable interpolation', 'warning', 'builtin', 'stable'),
  ('secrets-hardcoded-source', 'secrets', 1, 'Hardcoded secrets in source', 'API keys, tokens, or passwords hardcoded in source files (not .env)', 'critical', 'builtin', 'stable'),
  ('secrets-provider-patterns', 'secrets', 1, 'Provider key patterns', 'AWS AKIA, OpenAI sk-, or other provider key patterns in source', 'critical', 'builtin', 'stable'),
  ('dep-audit-critical', 'dependencies', 1, 'npm audit critical/high', 'Critical or high severity npm audit findings', 'critical', 'builtin', 'stable'),
  ('shell-missing-set-e', 'shell-safety', 1, 'Missing set -e in shell script', 'Shell script without set -e or set -euo pipefail at the top', 'warning', 'builtin', 'stable'),
  ('shell-unquoted-vars', 'shell-safety', 1, 'Unquoted variable in shell', 'Unquoted $VAR in rm/mv/cp/cd commands', 'warning', 'builtin', 'stable'),
  ('vibe-unused-imports', 'vibe-code', 1, 'Unused imports', 'Imported symbol not referenced elsewhere in file', 'info', 'builtin', 'stable'),
  ('vibe-orphan-files', 'vibe-code', 1, 'Orphan source files', 'Source file not imported by any other file', 'info', 'builtin', 'stable'),
  ('vibe-todo-fixme', 'vibe-code', 1, 'TODO/FIXME/HACK comments', 'Unfinished AI work markers in source code', 'info', 'builtin', 'stable'),
  ('duplication-structural', 'duplication', 1, 'Structural code duplication', 'Same function signature appearing in 3+ files', 'warning', 'builtin', 'stable'),
  ('duplication-type-defs', 'duplication', 1, 'Duplicate type definitions', 'Identical interface/type defined in multiple files', 'info', 'builtin', 'stable'),
  ('cors-permissive', 'cors', 1, 'Permissive CORS (Allow-Origin: *)', 'Access-Control-Allow-Origin: * in production code', 'critical', 'builtin', 'stable'),
  ('webhook-no-signature', 'webhooks', 1, 'Webhook without signature verification', 'Webhook endpoint accepting POST without HMAC/signature validation', 'warning', 'builtin', 'stable'),
  ('frontend-secrets', 'secrets', 1, 'Secrets in frontend/client code', 'sk_live_, sk-proj-, service_role keys in client-visible code', 'critical', 'builtin', 'stable'),
  ('debug-routes-production', 'vibe-code', 1, 'Debug routes in production', '/debug, /test, /_dev routes still active in production code', 'warning', 'builtin', 'stable'),
  ('mass-assignment', 'auth', 1, 'Mass assignment vulnerability', 'Unfiltered request body passed directly to database writes', 'critical', 'builtin', 'stable'),
  ('missing-rate-limiting', 'rate-limiting', 1, 'Missing rate limiting', 'Auth or API endpoints without rate limit checks', 'warning', 'builtin', 'stable');

-- Builtin suppressions (common intentional patterns)
INSERT INTO suppressions (pattern_id, file_glob, reason, source) VALUES
  ((SELECT id FROM patterns WHERE slug = 'sql-injection-shell-sqlite3'), '.claude/skills/*', 'Brain skill SQL uses system-generated IDs, not user input', 'builtin'),
  ((SELECT id FROM patterns WHERE slug = 'monolith-critical'), 'scripts/*', 'Seed scripts and generated config files excluded from monolith checks', 'builtin'),
  ((SELECT id FROM patterns WHERE slug = 'monolith-critical'), '*.d.ts', 'Type declaration files excluded from monolith checks', 'builtin'),
  ((SELECT id FROM patterns WHERE slug = 'monolith-critical'), '.claude/skills/**/*.md', 'Skill definition files excluded from monolith checks', 'builtin');
