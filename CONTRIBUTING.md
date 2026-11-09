# Working on the kit

This repository is public, and it is also a template: `install.sh` copies its `CLAUDE.md`,
`.claude/settings.json` and a few seed files into every new project. Everything committed here
ships to everyone who uses the kit, so it holds the **product only**: skills, scripts, hooks and docs.

## Keep your own working state in a private repo

Developing the kit with the kit means plans, research, a brain, memory and a `kit.json` for this
repo. They are yours, not the product's. Keep them in a private config repo, and let
`scripts/kit-config` link them in:

```bash
bash install.sh --config ~/dev/my-claude-config     # once per machine
~/.claude-kit/scripts/kit-config status             # what is linked where
~/.claude-kit/scripts/kit-config save               # commit and push the config repo
```

[docs/install.md, "Your own config"](docs/install.md#your-own-config-one-private-repo-every-machine)
shows the manifest. For this repo, the entries are `{kit}/.claude/kit.json`, `{kit}/cowork/plans`,
`{kit}/cowork/research`, `{kit}/cowork/brain/BRAIN.airsqlite` and `{kit-memory}`. The `.gitignore`
here already ignores all of them, so `git add -A` can't pick them up.

When a session opens in the kit's own checkout, the session-start hook says this repo is public and
where your private state lives. If no config repo is linked, it warns instead.

## Rules for every commit

- **Product files only.** Never force-add an ignored path.
- **Generic names in examples:** `/Volumes/External`, `~/dev/my-project`, `<you>`. Never your drives,
  clients, projects or email.
- **`CLAUDE.md` is a template.** New projects copy it, so keep its mantra empty here. A session's
  notes about this repo go in its memory, which lives in your config repo.

## The private-word guard

Add `"guard": "<path to a words file>"` to your config repo's `kit-config.json` and run
`kit-config link`. That installs `scripts/private-guard` as this checkout's pre-commit hook, and it
refuses any commit whose added lines contain one of your words. The list stays in your private repo:

```text
# one word or phrase per line, case-insensitive
MyExternalDrive
client-name
you@example.com
```

`git commit --no-verify` skips it, for the rare deliberate exception.
