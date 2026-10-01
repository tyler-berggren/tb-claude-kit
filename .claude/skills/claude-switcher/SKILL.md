---
name: claude-switcher
description: Check which Claude accounts this machine has, who is signed in to each and which VS Code profile uses which, and set up a new one — so a second (or third) Claude account is a VS Code profile switch away. `/claude-switcher` checks; `/claude-switcher add <name>` sets one up.
argument-hint: "[check | add <name>]"
user_only: true
---

# Claude Switcher

Several Claude accounts on one machine, picked by **VS Code profile**. Typical reasons: a personal
plan and an employer's, a client that requires its own account, or a second account for the same
work when one runs out of usage.

This skill works on the **whole machine**, not just the project it runs from.

| Argument | What happens |
|---|---|
| *(none)* or `check` | Show every account, who is signed in, which profile and folders use it, and what is off. Changes nothing. |
| `add <name>` | Set up a new account: its folder, its VS Code profile, its login. |

## How it works

- **An account is a folder.** Claude Code keeps one login, one settings file and one session
  history per config folder. `~/.claude` is the default account; `~/.claude-<name>` is another.
  The `CLAUDE_CONFIG_DIR` variable picks the folder.
- **A VS Code profile picks the folder.** The profile's own settings set `CLAUDE_CONFIG_DIR` for
  the Claude panel and for the VS Code terminal. So "which account" becomes "which profile".
- **VS Code remembers a profile per folder.** A project reopens in the profile it was last in.
  Switching account is `Profiles: Switch Profile`, then `Developer: Reload Window`.

Everything mechanical is in one script, `~/.claude-kit/scripts/claude-switcher`. It stores
nothing of its own: it reads the account folders and VS Code's files every time.

## Procedure

### Check (every mode starts here)

```bash
~/.claude-kit/scripts/claude-switcher
```

Relay the result as a short table (account, signed in as, VS Code profile, folders), then the
**Needs attention** and **Notes** lines in plain words with the fix for each. `<- this session`
marks the account this Claude session is on; say it outright, since "which account am I on right
now" is usually the real question.

In `check` mode, stop here. Fix nothing without being asked.

### Add an account

1. **Settle three things**, asking only for what the request did not already say:
   - **Name**: short, lowercase (`work`, `acme`). The folder becomes `~/.claude-<name>`.
   - **Profile name**: the VS Code profile. Defaults to the account name.
   - **Shared or separate history**: *shared* when it is a second account for the **same** work
     (both see one session list and the same memories; only the login differs). *Separate* when
     the accounts must not see each other's work, such as a client's or an employer's.

2. **Have the user create the VS Code profile.** Only they can; it is a VS Code screen:
   `Profiles: Create Profile`, the exact name, **copy from** the profile they normally use (that
   carries extensions and settings across).

3. **Create the account and point the profile at it:**

   ```bash
   ~/.claude-kit/scripts/claude-switcher add <name> --profile "<Profile>" [--share-history <account>]
   ```

   Safe to re-run; it reports `[ok]` for what is already in place. `[todo]` means the profile
   does not exist yet (step 2). `[manual]` means that profile's settings file has comments, so
   the script left it alone: add the two settings it prints by hand.

4. **Have the user sign in, in a real terminal** (Terminal.app, not the VS Code panel and not
   this session, because it opens a browser and waits):

   ```bash
   ~/.claude-kit/scripts/claude-switcher login <name>
   ```

5. **Have the user switch the project's window**: in the window that has the project folder
   open, `Profiles: Switch Profile` → the new profile, then `Developer: Reload Window`.

6. **Check again** and confirm the new account shows the right email, the profile, and the
   project folder. VS Code writes the folder-to-profile link to disk lazily, so "no folder
   opened in it yet" straight after a switch is not a problem by itself.

## What goes wrong (all of these happened)

- **Signing in from the VS Code panel lands in the wrong folder.** It reported "failed to
  retrieve auth status after login" and had in fact replaced the *default* account's login with
  the new one. Sign in from a terminal, always. The tell is one email signed in to two accounts,
  which the check reports. To undo it: `claude-switcher login default` with the right account.
- **A new, empty window on the profile shows the wrong session list.** The list is per folder,
  so a window with no folder open lists the home folder's sessions. Switch the profile in the
  project's own window.
- **Switching profile without reloading.** A Claude process already running keeps the account it
  started on. Reload the window.
- **One folder cannot be open in two windows**, so one folder is on one account at a time. To
  have both open side by side, open the folder in one profile and the project's
  `.code-workspace` file in the other; VS Code treats them as different things.
- **Hidden and archived sessions are remembered per profile**, even with shared history.
- **A terminal outside VS Code** knows nothing about profiles and uses the default account.
  Use `~/.claude-kit/scripts/claude-switcher run <name>` there.
- **Each account has its own settings, plugins and MCP sign-ins.** `add` copies `settings.json`
  once; after that they drift apart unless edited together. Sign-in-based MCP servers need
  `/mcp` once per account.

## Rules

- **Never sign in or out on the user's behalf**, and never read, copy or print anything from an
  account's `.claude.json` beyond the signed-in email. Logins live in the system keychain; leave
  them there.
- **Never delete an account folder.** It holds session history. If one should go, say which
  folder and let the user remove it.
- **Leave a process wrapper alone.** If the check notes `claudeCode.claudeProcessWrapper` is set,
  the project has its own account routing; do not change or remove it.
- **`check` changes nothing.**

---

## Project overrides

If `.claude/kit.json` has a `rules."claude-switcher"` entry, read it and apply it as an additional
instruction for this skill. Absent file or key means no overrides — that is the normal case.

```bash
jq -r '.rules."claude-switcher" // empty' .claude/kit.json 2>/dev/null
```
