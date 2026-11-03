## Brainstorm Flow

Flesh out a loose plan conversationally, phase by phase, before building. Use when a plan exists as a first draft with rough phases that need design work before they're concrete enough to execute.

Usage: `<NNN> brainstorm` (e.g. `013 brainstorm`)

### Step B1 — Load and bind

Same as Resume flow R1: resolve plan file, read it, bind the session.

### Step B2 — Assess plan maturity

For each phase, classify its items:
- **Concrete** — specific enough to execute (file paths, API shapes, clear implementation steps)
- **Loose** — directionally correct but needs design decisions (e.g. "config schema" without specifying what the schema looks like)
- **Unknown** — open questions that need research or brainstorming before items can be written

Present a quick summary:
```
**Plan NNN — Brainstorm Mode**

Phase 1 — <title> (<plan>:<start>-<end>): 3 concrete, 2 loose, 0 unknown
Phase 2 — <title> (<plan>:<start>-<end>): 1 concrete, 4 loose, 1 unknown
...

Starting with Phase <X> (first phase with loose/unknown items).
```

If all phases are concrete, suggest switching to Resume flow instead.

### Step B3 — Phase-by-phase brainstorm

Work through one phase at a time, starting with the first phase that has loose or unknown items.

For each phase:

1. **Present the phase** — show all items, flag which are loose/unknown, note related brain DB entries and codebase state.
2. **Brainstorm conversationally** — same principles as `/brainstorm`: think out loud, be opinionated, ask questions, stay concrete, diverge then converge. Focus on:
   - API design (function signatures, config shapes, data models)
   - Architecture decisions (where does this code live, how does it interact with existing code)
   - Edge cases and unknowns that need resolution
   - Build order within the phase
3. **Capture outputs to brain DB** — as decisions, insights, and questions emerge, log them immediately (same as `/brainstorm` Step 4). Link to the plan's brainstorm entry or create one if needed.
4. **Update the plan file** — rewrite the phase's items to be concrete based on the brainstorm. Replace loose items with specific implementation steps. Add new items that emerged. Mark resolved questions.
5. **User confirms** — present the updated phase and get approval before moving to the next phase.

### Step B4 — Transition to execution

After brainstorming through a phase (or set of phases), ask the user:
- **Continue brainstorming** the next phase, or
- **Switch to execution** on the now-concrete phases (transitions to Resume flow behavior — reconciliation + build)

The plan file is updated as you go, so a future session can pick up where you left off regardless of which mode you were in.

### Behavioral rules for brainstorm mode

- **Don't write code.** Brainstorm mode is for design, not implementation. If you find yourself reaching for Edit/Write on source files, you've left brainstorm mode — stop and ask if the user wants to switch to execution.
- **Update the plan file liberally.** The plan is the artifact. Every brainstorm conclusion should be reflected in more concrete plan items.
- **Log decisions to brain DB.** Design decisions made during brainstorm are durable — they outlive the plan. Use `parent_id` linking to the brainstorm or plan-linked entries.
- **One phase at a time.** Don't brainstorm Phase 4 before Phase 1 is concrete, unless the user explicitly jumps ahead. Earlier phases inform later ones.
- **Codebase research is encouraged.** Read files, grep for patterns, check existing implementations. The goal is to ground the brainstorm in reality, not speculate in the abstract.
