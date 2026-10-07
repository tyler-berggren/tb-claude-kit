#!/usr/bin/env python3
"""bash-guard.py — keeps a swarm agent from stopping the run on a permission prompt.

A PreToolUse hook for the Bash tool, declared in the swarm-* agent definitions. Some command
shapes make Claude Code ask the owner to approve the call whatever the project allows, and an
unattended run then sits until someone clicks. This hook refuses those shapes first: the agent
gets an error naming the form to use instead, at once, and nobody is asked.

Refused:
  cd-git   `cd`/`pushd` and `git` or `gh` in one call (the shape seen to prompt in every run)
  subst    command substitution: $(…) or backticks
  procsub  process substitution: <(…) or >(…)
  heredoc  a here-document: <<
  eval     eval

SWARM_BASH_GUARD_ALLOW is a comma-separated list of those names to let through (for a project
that has seen a shape run without a prompt); SWARM_BASH_GUARD=off turns the hook off.
Refusals are appended to $CLAUDE_PROJECT_DIR/.claude/state/logs/swarm-bash-guard.log.

The hook fails open: on any error of its own it lets the command run.
"""
import json
import os
import re
import sys
import time

ADVICE = {
    "cd-git": (
        "`cd` and `git`/`gh` in one Bash call makes Claude Code ask the owner to approve it. "
        "Use `git -C <path> …` and `gh … --repo <owner>/<name>`, absolute paths for files and "
        "scripts, and `env -C <dir> <command>` for a tool that needs a working directory."
    ),
    "subst": (
        "Command substitution ($(…) or backticks) can make Claude Code ask the owner to approve "
        "the call. Run the inner command in its own Bash call, read its output, and put the "
        "value in the next command."
    ),
    "procsub": (
        "Process substitution (<(…) or >(…)) can make Claude Code ask the owner to approve the "
        "call. Write the intermediate output to a file in your scratch directory instead."
    ),
    "heredoc": (
        "A here-document (<<) can make Claude Code ask the owner to approve the call. Write the "
        "text to a file with the Write tool and pass the file (`git commit -F <file>`, "
        "`gh pr create --body-file <file>`, `sqlite3 <db> < <file>` becomes `sqlite3 <db> \".read <file>\"`)."
    ),
    "eval": "`eval` can make Claude Code ask the owner to approve the call. Run the command directly.",
}

SEPARATORS = re.compile(r"&&|\|\||;|\||\n|&")
SHELL_C = re.compile(r"\b(?:bash|sh|zsh)\s+(?:-[a-zA-Z]*\s+)*-[a-zA-Z]*c\s+(['\"])(.*?)\1", re.S)
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=\S*$")
WRAPPERS = {"command", "builtin", "exec", "time", "nice", "nohup", "sudo", "then", "do", "else", "!", "{", "("}


def strip_quotes(cmd, keep_double):
    """Blank out quoted text. With keep_double, double-quoted text stays (the shell still
    expands $(…) and backticks inside it); single-quoted text always goes."""
    out, i, n = [], 0, len(cmd)
    while i < n:
        c = cmd[i]
        if c == "\\" and i + 1 < n:
            i += 2
            continue
        if c == "'":
            j = cmd.find("'", i + 1)
            i = n if j < 0 else j + 1
            out.append("''")
            continue
        if c == '"' and not keep_double:
            j = i + 1
            while j < n and cmd[j] != '"':
                j += 2 if cmd[j] == "\\" else 1
            i = j + 1
            out.append('""')
            continue
        out.append(c)
        i += 1
    return "".join(out)


def first_words(cmd):
    """The command word of each simple command in a (quote-stripped) command line."""
    words = []
    for segment in SEPARATORS.split(cmd):
        tokens = segment.strip().lstrip("({").split()
        while tokens and (ASSIGNMENT.match(tokens[0]) or tokens[0] in WRAPPERS):
            tokens.pop(0)
        if tokens:
            words.append(os.path.basename(tokens[0]))
    return words


def findings(cmd):
    found = []
    bare = strip_quotes(cmd, keep_double=False)
    expanding = strip_quotes(cmd, keep_double=True)

    words = first_words(bare)
    if any(w in ("cd", "pushd") for w in words) and any(w in ("git", "gh") for w in words):
        found.append("cd-git")
    if "eval" in words:
        found.append("eval")
    if "$(" in expanding.replace("$((", "") or "`" in expanding:
        found.append("subst")
    if re.search(r"[<>]\(", bare):
        found.append("procsub")
    if re.search(r"(?<!<)<<(?!<)", bare):
        found.append("heredoc")

    # A script handed to `bash -c '…'` is a command line too.
    for match in SHELL_C.finditer(cmd):
        for name in findings(match.group(2)):
            if name not in found:
                found.append(name)
    return found


def main():
    if os.environ.get("SWARM_BASH_GUARD", "").lower() == "off":
        return
    data = json.load(sys.stdin)
    if data.get("tool_name") != "Bash":
        return
    cmd = (data.get("tool_input") or {}).get("command") or ""
    allowed = {a.strip() for a in os.environ.get("SWARM_BASH_GUARD_ALLOW", "").split(",") if a.strip()}
    found = [f for f in findings(cmd) if f not in allowed]
    if not found:
        return

    reason = (
        "Refused before it could stop the run on a permission prompt (swarm bash-guard). "
        + " ".join(ADVICE[f] for f in found)
        + " Re-issue it in that form; do not retry this shape."
    )
    try:
        root = os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or "."
        log_dir = os.path.join(root, ".claude", "state", "logs")
        os.makedirs(log_dir, exist_ok=True)
        with open(os.path.join(log_dir, "swarm-bash-guard.log"), "a") as log:
            log.write("%s\t%s\t%s\n" % (time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), ",".join(found), cmd.replace("\n", "\\n")[:400]))
    except Exception:
        pass
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
