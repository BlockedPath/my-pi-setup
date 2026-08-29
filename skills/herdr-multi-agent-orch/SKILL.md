---
name: herdr-multi-agent-orch
description: >-
  Run a multi-agent coding workflow inside Herdr with fixed roles: coordinator,
  scout, architect, sole implementer, reviewer, and validator. Use when the user
  asks for multi-agent orchestration in Herdr, a coord/scout/architect/implementer
  /reviewer/validator pipeline, Herdr relay boards, or the multi-agent-orch
  workspace pattern. Distinct from Orca orchestration (use the orchestration
  skill) and from raw Herdr pane control (use the herdr skill). Requires
  HERDR_ENV=1.
---

# Herdr Multi-Agent Orchestration

Coordinate specialized coding agents across Herdr panes with **one writer**,
**read-only recon/review**, and a **coordinator that owns routing + synthesis**.

This skill is the protocol. Load the `herdr` skill for raw CLI details when needed.
Do **not** substitute Orca orchestration, pi-subagents, or ad-hoc parallel agents
unless the user explicitly asks for those systems.

## Preconditions

```bash
test "${HERDR_ENV:-}" = 1
command -v herdr
```

If either fails, say you are not inside a Herdr-managed session and stop. Do not
try to drive Herdr from outside `HERDR_ENV=1`.

## Tool boundary

| System | When |
|--------|------|
| **This skill** | Supervised multi-role coding jobs inside Herdr |
| **`herdr` skill** | Low-level pane/tab/workspace CLI, splits, waits |
| **`orchestration` skill** | Orca task DAGs / `worker_done` / decision gates |
| **`pi-subagents`** | In-process subagents in a single Pi session |
| **`orca-cli`** | Full ownership handoffs / Orca worktrees |

Prefer pane labels as human handles. **Always re-list and resolve live pane IDs**
before dispatch — IDs are opaque and change after moves/closes.

## Canonical topology

Default workspace label: `multi-agent-orch`.

| Tab label | Pane label | Agent | Role |
|-----------|------------|-------|------|
| `00-coordinator` | `coord-pi` | Pi | Lead coordinator & synthesizer |
| `00-coordinator` | `relay-board` | shell | Living roster / protocol board |
| `01-planning` | `architect-claude` | Claude | Architecture & plans (no large impl) |
| `01-planning` | `scout-pi` | Pi | Read-only codebase recon |
| `02-implementation` | `implementer-codex` | Codex | **Sole primary code writer** |
| `03-review` | `reviewer-claude` | Claude | Adversarial review (read-only default) |
| `03-review` | `validator-pi` | Pi | Focused tests / build / lint |

If the live layout differs, adapt by **role**, not by hardcoded IDs from docs.

### Resolve live roster

```bash
herdr workspace list
# find workspace by label multi-agent-orch (or current $HERDR_WORKSPACE_ID)
herdr tab list --workspace <workspace_id>
herdr pane list --workspace <workspace_id>
```

Build a map: `label -> pane_id`. Prefer labels from the table above. Never invent
IDs like `wQ:p3` from memory.

Optional: keep the relay board updated as a human-readable roster:

```bash
herdr pane run <relay-board-pane> "clear; printf '%s\n' '=== multi-agent roster ===' ..."
```

## Relay flow

```
User
  └─► coord-pi
        ├─► scout-pi              # context map
        ├─► architect-claude      # plan / implementer handoff prompt
        ├─► implementer-codex     # code changes (only writer)
        ├─► reviewer-claude       # findings
        ├─► validator-pi          # verification
        └─► coord-pi              # synthesize for user
```

Loops:

1. Review blockers → `implementer-codex` → re-review
2. Validation failures → `implementer-codex` with a tight fix brief
3. Scope / product decisions → escalate to `coord-pi` / user

## Ownership rules

1. **One writer**: only `implementer-codex` edits the shared worktree unless
   `coord-pi` explicitly reassigns for a named exception.
2. **Scout / reviewer default read-only** — no drive-by edits.
3. **Architect produces plans + implementer handoff prompts**, not large code dumps.
4. **Validator runs the smallest useful checks** for the change (not full suite by default).
5. **Coordinator owns routing, synthesis, and user communication**.
6. Do not fan-out parallel writers into the same worktree.
7. Prefer `--no-focus` when spawning/dispatching background work so the user keeps context.

## Status contract

Every agent turn that finishes a dispatched unit should end with:

```text
STATUS: idle|blocked|needs_input
NEXT: <who should act next and why>
SUMMARY:
- bullet
- bullet
- bullet
```

Coordinator waits for completion with:

```bash
# finished + unseen
herdr wait agent-status <pane_id> --status done --timeout 300000
# finished + seen (also treat as complete)
herdr wait agent-status <pane_id> --status idle --timeout 300000
```

Treat **`idle` and `done` as completed**. Difference is only whether the result was seen.

Then read the result:

```bash
herdr pane read <pane_id> --source recent-unwrapped --lines 120
# or
herdr agent read <pane_id> --source recent-unwrapped --lines 120
```

## Dispatch pattern

```bash
# Resolve pane first
PANE=$(herdr pane list --workspace <ws> | ... label match ...)

# Send a task (command text + Enter)
herdr pane run "$PANE" "TASK: <role brief + goal + constraints + STATUS contract reminder>"
```

Use `herdr pane run` for prompt delivery (text + Enter). Use `herdr pane send-text`
only when you intentionally do not want Enter.

Do not sleep/poll in a tight loop. Prefer `herdr wait agent-status`. On timeout,
checkpoint: re-read the pane, check `agent_status`, decide retry / escalate / ask user.

## Coordinator recipe (start a job)

1. **Restate** the user goal, constraints, and definition of done.
2. **Resolve roster** (`workspace list` → `pane list` → label map).
3. **Scout** (`scout-pi`): read-only map of relevant files, entry points, tests, risks.
4. **Wait + read** scout output; if thin, re-dispatch a tighter scout brief.
5. **Architect** (`architect-claude`): design + concrete implementer handoff prompt.
   No large implementation.
6. **Gate** (coordinator/user): approve or revise the plan when scope is non-trivial.
7. **Implement** (`implementer-codex`): sole writer executes the handoff prompt.
8. **Parallel QA** when implementer is done:
   - `reviewer-claude` — adversarial correctness/risk review
   - `validator-pi` — focused tests/build/lint
9. **Repair loop**: blockers or failing checks → tight fix brief to implementer only.
10. **Synthesize** for the user: what changed, residual risks, how to verify.

Skip stages only when the job is trivially small (e.g. pure validation of an
existing diff can start at reviewer+validator). State the skip explicitly.

## Role briefs

Keep dispatches short and role-specific. Full templates live in:

- [references/role-prompts.md](references/role-prompts.md)
- [references/bootstrap.md](references/bootstrap.md) — create/repair the topology

### Scout

Read-only recon. Return file map, symbols, existing tests, risks. No edits.

### Architect

Plan + handoff prompt for implementer. Prefer interfaces, sequencing, and
acceptance checks over code dumps.

### Implementer

Only writer. Follow handoff. Minimal diff. Report files changed + how to verify.

### Reviewer

Adversarial, read-only by default. Blockers vs notes. No drive-by fixes unless
explicitly reassigned as writer.

### Validator

Smallest useful verification. Report pass/fail commands and residual gaps.

## Bootstrap / repair

If the workspace or roles are missing, follow
[references/bootstrap.md](references/bootstrap.md).

Summary:

1. Create or select workspace labeled `multi-agent-orch` with the project cwd.
2. Create tabs `00-coordinator` … `03-review`.
3. Split panes, rename labels, launch each agent binary (`pi`, `claude`, `codex`, shell).
4. Seed each agent with its role prompt once.
5. Write/update a project `ORCHESTRATION.md` only if the user wants a local snapshot;
   live IDs always come from `herdr pane list`.

## Anti-patterns

- Hardcoding stale pane IDs from chat history or markdown
- Letting scout/reviewer/architect edit production code
- Parallel implementers on one worktree
- Polling with sleep instead of `herdr wait agent-status`
- Claiming Orca/`worker_done` semantics while driving Herdr panes
- Spawning a new topology when an existing labeled roster already fits
- Focusing every dispatch pane (`--no-focus` for background work)

## Example local snapshot

A project may keep `ORCHESTRATION.md` as a human-readable roster snapshot. Treat it
as **hints**, not ground truth. Re-list Herdr state before every job.
