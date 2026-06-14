---
name: do
description: Plan and (optionally) implement a change end to end through the agent chain. Infers mode from the prompt: a planning ask ("plan X", "design X", "how would you X") runs the planner and returns the plan plus shard table, advisory only; an implementation ask ("do X", "implement X", "build X", "add X") runs the full chain - the planner shards the work, fix-implementer/dev execute the shards, dev hands off to test, then the detected CI runs. Language-agnostic via detect-project.sh. Use for "do X", "implement X", "build X", "plan X".
allowed-tools: Bash, Read, Edit, Write, Agent
---

# do

The forward implementation chain in one entry point: a goal goes to the `planner`, which shards
it; `fix-implementer` and `dev` execute the shards; `dev` hands each substantive shard to
`test`; then the detected CI runs. The counterpart to `/review` (which drives the review -> fix
path); `do` drives the plan -> build -> test path. Language-agnostic: every build/test/lint/ci
command comes from the detector.

## Mode (inferred from the prompt)

- **plan** - the ask is to plan/design/outline ("plan X", "design X", "how would you X", "just
  plan"). Run the planner and stop at the plan + shard table. Advisory: change nothing.
- **implement** (default for "do/implement/build/add X") - run the full chain: plan, execute the
  shards, certify with tests, run CI.

Announce the resolved mode at the start, e.g. "do: plan" or "do: plan + implement".

## Steps

### 1. Frame the goal

Restate the goal and its acceptance criteria in a sentence or two. Read the directly relevant
files for context and identify the project's commands (do not assume a toolchain):

```bash
~/.agents/resources/detect-project.sh .
```

### 2. Plan (always)

Spawn the `planner` agent with the goal, the acceptance criteria, and any constraints. It
returns the plan and a **shard table**: disjoint written-file sets (no two shards touch the same
file) with an **executor** and **model** per shard - `fix-implementer` for mechanical shards,
`dev` (which hands off to `test`) for substantive ones.

In **plan** mode, present the planner's plan + shard table and stop here.

### 3. Execute the shards (implement mode)

Spawn one executor per shard from the planner's table, in a single batch so they run
concurrently, at the model the table specifies:
- **mechanical** shard -> `fix-implementer`, given the shard as a verbatim spec.
- **substantive** shard -> `dev`, given the behavior + acceptance criteria; `dev` implements
  with formal committed tests and then hands off to `test` for an independent, outside-in
  coverage certification.

The shards are disjoint by construction, so they do not collide. Add a barrier only where one
shard consumes another's output (the planner flags these). Wait for every shard to report - and
for each `dev` shard's `test` certification - before continuing. If a `test` certification
fails, send that shard back to `dev`; if a `fix-implementer` shard turns out to need reasoning,
re-route it to `dev`.

Never wait indefinitely. A shard that returns nothing usable, reports an error, or stalls (for
example a sub-agent blocked on a tool-approval prompt that timed out) is a **failed shard**, not
a reason to keep waiting. Surface the failure explicitly, then re-dispatch that shard once or
abort the run with what completed - do not hang on a report that is not coming. Sub-agents should
not need approvals: they invoke only committed resource scripts (allowlisted in `config/`), so a
stall means something is wrong, not that you should wait longer.

### 4. Verify

Run the detected CI and fix any failures (re-dispatch to the shard's owning executor) until
green:

```bash
~/.agents/resources/detect-project.sh . --run ci
```

### 5. Report

State the resolved mode, the plan summary, the shard table that ran (each shard's executor,
model, and result), the `test` certifications, the CI result, and the files changed. Commit
locally only if the user asked; do not push or open a PR unless asked.

## Discipline

- The chain is `planner` -> `fix-implementer`/`dev` -> `test`; do the planning in the `planner`
  agent, not inline, so sharding stays in one place and is reusable.
- All build/test/lint/ci commands come from `resources/detect-project.sh`; no hardcoded
  toolchain.
- All tests are formal and committed (`dev`/`test`); never one-off inline probes.
- Every shell command spawned agents run is a committed resource script (or a plain `git`/`jq`)
  that is allowlisted in `config/settings.json`, so no spawn ever blocks on a tool approval. A
  sub-agent that stalls is a failed shard, not a wait - see step 3.
- Shards must be disjoint in their written files so executors can run concurrently without
  corrupting each other.
- Do not force-push or rewrite history unless explicitly asked.
