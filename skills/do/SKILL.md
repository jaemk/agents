---
name: do
description: 'Plan or implement a change end to end. Planning requests return an advisory plan. Implementation requests plan, make, and verify changes using the detected CI. In a spec-driven project, include spec edits in the plan and update feature status after CI. Add "and review" to run the review skill. Sub-agent delegation and sharding require an explicit request. Use for "do X", "implement X", "build X", or "plan X".'
allowed-tools: Bash, Read, Edit, Write, Agent
requires: skill:review skill:spec
---

# do

Plan, implement, and verify changes in the current session. Get build, test, lint, and CI
commands from the project detector.

## Mode (inferred from the prompt)

- **plan** - for planning or design requests. Return an advisory plan without changing files.
- **implement** - for requests to do, implement, build, or add something. Plan the change,
  implement it, and run verification.

Announce the resolved mode at the start, e.g. "do: plan" or "do: plan + implement".

Use sub-agents only for stages the user explicitly asks to delegate. Produce a shard table
only when the user asks for sharding or parallel agent work. In plan mode, a requested shard
table is advisory. A request for an additional review invokes that skill in the current session
unless the user requests delegation for the review.

## Steps

### 1. Frame the goal

Restate the goal and its acceptance criteria in a sentence or two. Read the directly relevant
files for context and identify the project's commands (do not assume a toolchain):

```bash
{{tools:detect-project}} .
```

If the project has a `spec/` (or `specs/`) dir, it is spec-driven (see the `spec` skill): the
behavior is documented before it is built. Read the spec directory's `README.md` and the relevant spec docs,
and list where the goal's statements belong: existing IDs it changes, new IDs it needs (append
only, never reuse a number), and the feature-status row it moves.

### 2. Plan

Identify the approach, affected files, existing code to reuse, dependencies, and how to verify
the acceptance criteria. In a spec-driven project, include spec edits in the plan and have
tests reference new statement IDs using the project's existing convention.

For explicitly requested delegation or sharding, follow the optional workflow below within the
requested scope. In **plan** mode, present the resulting plan and stop.

### 3. Implement

Make the planned changes and add or update formal tests for changed behavior. In a spec-driven
project, update the behavior docs before implementing their changes. Check that the tests cover
the acceptance criteria and relevant boundaries and failure paths.

### 4. Verify

Run the detected CI and address failures:

```bash
{{tools:detect-project}} . --run ci
```

For a spec-driven project, then bring the feature-status table up to date with the `spec`
skill: `set` the row to the legend's `done` value once the behavior is implemented and tested
(or a partial value if only some of it landed), and run its `sync` command until it reports
no missing or orphaned docs.

### 5. Review (when asked)

When the input asks for a review ("do X and review it"), run the `review` skill in local mode
once CI is green. Include its findings in the report. Apply fixes only if requested.

### 6. Report

State the resolved mode and summarize the plan. For implementation, report the files changed,
test and CI results, any spec status changes, and requested review findings. Include delegated
work and its results if used. Commit locally only if the user asked. Push or open a PR only
when requested.

## Explicit delegation and sharding

- If sharding is requested and you are planning directly, follow the shard-table guidance in
  the `planner` profile in the current session.
- For a delegated planning stage, give `planner` the goal, acceptance criteria, constraints,
  and any spec edits. Ask for a shard table only when sharding or parallel agent work was
  requested. The table lists disjoint write sets, dependencies, executors, and models.
- For delegated implementation, use `fix-implementer` for a precise mechanical fix and `dev`
  for changes that need implementation judgment and formal tests. When sharding is requested,
  use one executor per shard and run independent shards together. Wait for prerequisites before
  running shards that depend on them.
- Delegate independent coverage certification to `test` only when the user explicitly
  requests delegated verification. Give it the implementation summary, tests, and relevant
  paths. The current agent owns CI and any verification outside the delegated scope.
- Use non-interactive permissions and allowlisted commands for delegated work. Surface failed
  or stalled tasks and continue directly when possible. Report any remaining blocker.

## Discipline

- Use `{{tools:detect-project}}` for build, test, lint, and CI commands.
- Use formal project tests for verification and avoid one-off inline probes.
- Do not force-push or rewrite history unless explicitly asked.
