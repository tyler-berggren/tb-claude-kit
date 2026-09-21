---
name: 1password
description: Set up, check, or migrate 1Password secret management for this project — bootstrap service accounts, convert plaintext .env to op:// references, troubleshoot resolution.
argument-hint: "[setup | check | migrate | troubleshoot]"
---

# 1Password Secret Management

Manage project secrets through 1Password using the `oprun` wrapper and per-vault service accounts.

## Subcommands

| Command | What it does |
|---------|-------------|
| `/1password` | Auto-detect: if not configured, run setup; if configured, run check |
| `/1password setup` | Full setup: configure kit.json, bootstrap a service account, create vault items, rewrite .env |
| `/1password check` | Verify the current configuration works — vault access, .env resolution, .mcp.json references |
| `/1password migrate` | Convert an existing plaintext .env to op:// references (creates vault items, rewrites .env) |
| `/1password troubleshoot` | Diagnose why secrets aren't resolving |

## Procedure

### 1. Read current state

```bash
# kit.json secrets config
jq -r '.secrets // empty' .claude/kit.json 2>/dev/null

# Current .env (check for plaintext vs op:// references)
head -30 .env 2>/dev/null || echo "no .env"

# Service account in Keychain
VAULT=$(jq -r '.secrets.vault // empty' .claude/kit.json 2>/dev/null)
[ -n "$VAULT" ] && security find-generic-password -a "$USER" -s "op-sa-$VAULT" >/dev/null 2>&1 && echo "Keychain: op-sa-$VAULT found" || echo "Keychain: op-sa-$VAULT NOT found"

# oprun availability
~/.claude-kit/scripts/oprun check 2>&1 || true
```

Determine the subcommand from the user's argument, or auto-detect:
- No `secrets` block in kit.json → suggest **setup**
- Has `secrets` but .env has plaintext values → suggest **migrate**
- Fully configured → run **check**

### 2. Setup

**Only if the user asked for setup or the auto-detect suggests it.**

Ask the user which 1Password vault to use. If they don't know, list available vaults:

```bash
env -u OP_SERVICE_ACCOUNT_TOKEN op vault list --format json 2>&1 | python3 -c "
import sys, json
for v in json.loads(sys.stdin.read()):
    print(f'  {v[\"name\"]} ({v[\"id\"]})')
"
```

Then:

1. Add `secrets` block to `.claude/kit.json`:
   ```json
   "secrets": {
     "vault": "<vault-name>",
     "account": "my.1password.com"
   }
   ```

2. Check if a service account already exists for this vault:
   ```bash
   security find-generic-password -a "$USER" -s "op-sa-<vault>" >/dev/null 2>&1 && echo "EXISTS" || echo "NEEDS BOOTSTRAP"
   ```

3. If no service account exists, bootstrap one:
   ```bash
   ~/.claude-kit/scripts/op-sa-bootstrap "<vault>" --account my.1password.com
   ```
   This requires Touch ID — tell the user to approve the prompt.

4. Verify:
   ```bash
   ~/.claude-kit/scripts/oprun check
   ```

5. If there's a plaintext `.env`, proceed to **migrate** automatically.

### 3. Migrate

**Convert plaintext .env values to op:// references.**

For each secret in `.env` that is NOT already an `op://` reference and is NOT a plain identifier
(account IDs, hostnames, ports, URLs, project names):

1. Check if the value already exists as an item in the vault:
   ```bash
   ~/.claude-kit/scripts/oprun op item list --vault "<vault>" --format json
   ```
   Search by title match or by field value match.

2. If no existing item, create one:
   ```bash
   env -u OP_SERVICE_ACCOUNT_TOKEN op item create \
     --vault "<vault>" \
     --category "API Credential" \
     --title "<service-name>" \
     "<field_name>=<value>" \
     --format json
   ```
   Use the comment or variable name context to pick a descriptive title.

3. Rewrite the `.env` line to use the `op://` reference:
   ```
   VAR_NAME=op://<vault>/<item-id>/<field_name>
   ```

4. Also check `.mcp.json` for plaintext keys in server `env` blocks. Common shared keys
   (Brave, Firecrawl, Perplexity) may already have items in a shared vault — check before creating
   duplicates.

5. After rewriting, verify resolution:
   ```bash
   ~/.claude-kit/scripts/oprun get <VAR_NAME>
   ```

**What stays plaintext:** Account IDs, hostnames, ports, S3 endpoints, project names, email
addresses, non-secret configuration. The rule: if the value appears in documentation or config
files and wouldn't be useful to an attacker on its own, it stays plain.

### 4. Check

Verify the full chain works:

```bash
# 1. kit.json has secrets config
jq -r '.secrets.vault' .claude/kit.json 2>/dev/null

# 2. Service account can reach the vault
~/.claude-kit/scripts/oprun check

# 3. Every op:// reference in .env resolves
~/.claude-kit/scripts/oprun -- printenv 2>&1 | head -5

# 4. .mcp.json references resolve (if any)
grep -o 'op://[^"]*' .mcp.json 2>/dev/null | while read ref; do
  ~/.claude-kit/scripts/oprun op read "$ref" >/dev/null 2>&1 && echo "  OK: $ref" || echo "  FAIL: $ref"
done
```

Report: vault name, auth method, number of references resolved, any failures.

### 5. Troubleshoot

Run diagnostics in order:

```bash
# 1. Is op CLI installed?
which op && op --version

# 2. Is kit.json configured?
jq '.secrets' .claude/kit.json 2>/dev/null || echo "No secrets config in kit.json"

# 3. Is there a Keychain entry?
VAULT=$(jq -r '.secrets.vault' .claude/kit.json 2>/dev/null)
security find-generic-password -a "$USER" -s "op-sa-$VAULT" >/dev/null 2>&1 \
  && echo "Keychain entry exists" || echo "NO Keychain entry — run: ~/.claude-kit/scripts/op-sa-bootstrap $VAULT"

# 4. Can the service account reach the vault?
~/.claude-kit/scripts/oprun check 2>&1

# 5. Can a specific reference resolve?
grep -m1 'op://' .env 2>/dev/null | cut -d= -f2 | while read ref; do
  ~/.claude-kit/scripts/oprun op read "$ref" >/dev/null 2>&1 \
    && echo "Reference resolves: $ref" || echo "FAILED to resolve: $ref"
done
```

Common failure modes:
- **"no .claude/kit.json above $PWD"** → add `secrets` block to kit.json
- **"no Keychain item"** → run `op-sa-bootstrap <vault>`
- **"Service Account Deleted"** → token was revoked; re-run `op-sa-bootstrap <vault> --rotate`
- **"did not answer within Ns"** → macOS TCC dialog blocking; dismiss it, or the service account token is wrong
- **"expected the token to see 1 vault, it sees N"** → service account has multiple vault access; recreate with single vault
- **Reference fails but oprun check passes** → item ID may be wrong, or field name doesn't match; verify with `oprun op item get <item-id> --vault <vault>`

## Rules

- **Never print resolved secret values** — use `head -c N` or mask them. The point of 1Password is that secrets stay out of transcripts.
- **Never modify the `oprun` or `op-sa-bootstrap` scripts** — they live in the kit and are shared across all projects.
- **Reference items by ID, not title** — `op://vault/<item-id>/field` costs 1 API call; `op://vault/Item Title/field` costs 3. Item IDs are the 26-character alphanumeric strings returned by `op item create/list`.
- **One vault per project** — the service account model is one token per vault. A project that needs secrets from two vaults should consolidate into one, or use the desktop-app path for the secondary vault.
- **Plain values stay plain** — account IDs, hostnames, project names, and non-secret config do not belong in 1Password. Only credentials, tokens, and keys get `op://` references.
- **Ask before creating items** — confirm the vault and item names with the user before writing to 1Password, especially when migrating an existing .env with many secrets.

---

## Project overrides

If `.claude/kit.json` has a `rules."1password"` entry, read it and apply it as an additional
instruction for this skill. Absent file or key means no overrides — that is the normal case.

```bash
jq -r '.rules."1password" // empty' .claude/kit.json 2>/dev/null
```
