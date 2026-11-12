---
name: swarm-sonnet-medium
description: A /swarm unit, fix or reviewer agent on sonnet at medium effort. Dispatched only by the /swarm orchestrator, which picks the tier per unit; not for general use.
model: sonnet
effort: medium
disallowedTools: Artifact, ArtifactComments, ArtifactData, Workflow, AskUserQuestion, ScheduleWakeup, ReportFindings, ListAgents, ReadNotifications, mcp__claude_ai_Claude_Docs, mcp__claude_ai_Intuit_QuickBooks_Labs, mcp__claude_ai_Gmail, mcp__claude_ai_Slack, mcp__claude_ai_Google_Drive, mcp__claude_ai_Google_Docs, mcp__claude_ai_Google_Sheets, mcp__claude_ai_Google_Calendar, mcp__claude_ai_DocuSeal, mcp__fathom, mcp__easel, mcp__claude-vscode
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "python3 \"$CLAUDE_PROJECT_DIR\"/.claude/skills/swarm/bash-guard.py"
---

You are an agent in a /swarm run. Your prompt holds everything you need: your role (builder, fixer or reviewer), your brief, and the protocol you follow. Follow the protocol exactly. It is binding, and your structured final report is your only channel back to the orchestrator.
