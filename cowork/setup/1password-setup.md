# 1Password Service Account Setup

Credentials are stored in 1Password. The `.env` file contains `op://` references that get resolved at runtime via `op run`. A Service Account token stored in macOS Keychain provides non-interactive auth — no biometric prompts — so deploys, CLI commands, and AI agent Bash tools all have access.

## Prerequisites

- 1Password desktop app installed with CLI integration enabled (Settings > Developer > Integrate with 1Password CLI)
- Access to your vault in 1Password

## Steps

### 1. Install the 1Password CLI

```bash
brew install --cask 1password-cli
op --version  # verify
```

### 2. Identify your account

```bash
op account list
```

Note your USER ID.

### 3. Create a Service Account

Go to my.1password.com > Developer > Service Accounts. Create one with access to the vault(s) your `.env` references.

### 4. Store the token in macOS Keychain

```bash
security add-generic-password -a "$USER" -s "op-service-account" -w "PASTE_TOKEN_HERE"
```

### 5. Create ~/.zshenv

This file runs in every shell (including non-interactive), so Claude Code and other tools get the token automatically.

```bash
cat >> ~/.zshenv << 'EOF'
export OP_SERVICE_ACCOUNT_TOKEN=$(security find-generic-password -s "op-service-account" -w 2>/dev/null)
EOF
```

If you have multiple 1Password accounts, also set your account ID:

```bash
cat >> ~/.zshenv << 'EOF'
export OP_ACCOUNT=YOUR_USER_ID
EOF
```

### 6. Verify

```bash
source ~/.zshenv
op run --env-file=.env -- printenv  # should show resolved values, not op:// URIs
```

## How it works

```
~/.zshenv loads on shell start
  -> reads Service Account token from macOS Keychain
  -> exports OP_SERVICE_ACCOUNT_TOKEN

op run --env-file=.env -- <command>
  -> reads .env, finds op:// references
  -> resolves them via Service Account token (no biometric)
  -> injects real values into the command's environment
```

## .env format

The `.env` file is safe to commit — it contains references, not secrets:

```bash
# Provider credentials (1Password: Vault / Item)
PROVIDER_API_KEY=op://Vault Name/Item Name/field_name
PROVIDER_SECRET=op://Vault Name/Item Name/credential

# Service tokens
GITHUB_TOKEN=op://Vault Name/GitHub Token/token
```

## Usage in skills and scripts

Wrap any command that needs credentials:

```bash
op run --env-file=.env -- npx wrangler deploy
op run --env-file=.env -- npm run deploy
op run --env-file=.env -- curl -H "Authorization: Bearer $API_TOKEN" https://...
```

Read a single secret directly:

```bash
op read "op://Vault Name/Item Name/field_name"
```

## Rotating the Service Account token

1. Regenerate on my.1password.com (Developer > Service Accounts)
2. Update macOS Keychain:

```bash
security add-generic-password -U -a "$USER" -s "op-service-account" -w "NEW_TOKEN"
```

The `-U` flag updates the existing entry.

## Rotating individual secrets

Update the secret in 1Password — `op run` resolves references at runtime, so no local changes needed.
