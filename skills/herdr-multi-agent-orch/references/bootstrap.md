# Bootstrap / repair the multi-agent topology

Use only when the labeled roster does not exist or is broken. Prefer repairing
an existing `multi-agent-orch` workspace over creating a second one.

## 0. Preconditions

```bash
test "${HERDR_ENV:-}" = 1
command -v herdr
herdr workspace list
```

Pick a project cwd (example: current repo root). All agent panes should share it
unless the user asked for worktree isolation.

## 1. Workspace

If a workspace labeled `multi-agent-orch` already exists, use it.

Otherwise create one (exact flags may vary by herdr version — check
`herdr workspace` help first):

```bash
herdr workspace
herdr workspace list
# create/select and set label multi-agent-orch if supported
```

Record `workspace_id` from JSON. Do not hardcode IDs from docs.

## 2. Tabs

Desired tab labels:

1. `00-coordinator`
2. `01-planning`
3. `02-implementation`
4. `03-review`

```bash
herdr tab list --workspace <workspace_id>
herdr tab
# create/rename tabs to match labels; re-list after each mutation
```

## 3. Panes and agents

Target layout:

| Tab | Label | Launch |
|-----|-------|--------|
| `00-coordinator` | `coord-pi` | `pi` |
| `00-coordinator` | `relay-board` | shell (no agent) |
| `01-planning` | `architect-claude` | `claude` |
| `01-planning` | `scout-pi` | `pi` |
| `02-implementation` | `implementer-codex` | `codex` |
| `03-review` | `reviewer-claude` | `claude` |
| `03-review` | `validator-pi` | `pi` |

Pattern for each missing role:

```bash
# Split without stealing focus
herdr pane split --current --direction right --no-focus --cwd <project_cwd>
# Read result.pane.pane_id from JSON
herdr pane rename <pane_id> "<label>"
herdr pane run <pane_id> "<agent-binary>"   # pi | claude | codex
```

Choose split direction from pane geometry (`herdr pane layout`) — wide → right,
tall/narrow → down. Avoid unusable micro-columns.

For the relay board, leave a plain shell and print a roster header.

## 4. Seed role prompts

Once each agent is idle at its prompt, seed with the matching template from
[role-prompts.md](role-prompts.md):

```bash
herdr pane run <pane_id> "<role seed prompt>"
herdr wait agent-status <pane_id> --status idle --timeout 120000
```

## 5. Verify roster

```bash
herdr pane list --workspace <workspace_id>
```

Confirm labels, agents, cwd, and that exactly one pane is intended as writer
(`implementer-codex`).

## 6. Optional project snapshot

If the user wants a local human snapshot:

```bash
# Write/update ORCHESTRATION.md with current labels + IDs + recipe
# Mark IDs as ephemeral; skill remains canonical protocol
```

## Repair notes

- Closed pane/tab IDs are never reused. Re-list after close/move.
- A pane moved across workspaces gets a new public pane ID.
- If an agent is in the wrong tab, move/rename rather than launching a duplicate writer.
- If two writers exist, stop and reassign — do not run both on one worktree.
