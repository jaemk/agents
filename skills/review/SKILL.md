---
name: review
description: 'Review code changes and optionally fix the findings. Defaults to a read-only review of your local changes (diff vs the detected base branch): shards the diff, spawns implementor-reviewer, consumer-reviewer, and adversarial security-reviewer agents in parallel, and reports deduplicated findings with severity and a verdict. Add `pr [N]` to also pull a GitHub PR''s review comments, `fix` to plan and apply fixes (mechanical -> fix-implementer, substantive -> dev then test), and `writeback` to resolve threads / minimize comments / re-request Copilot. Language-agnostic via detect-project.sh. Use for "review my changes", "review this PR", "review and fix", "address the PR comments".'
allowed-tools: Bash, Read, Edit, Write, Agent
---

# review

One skill for the whole review loop, from a read-only look at your local changes up to
fetching PR feedback, fixing findings, and updating the PR. It is language-agnostic: every
build/test/lint/readme command comes from the detector, never hardcoded.

Helper script (run outside the sandbox for the GitHub commands, which need network):

```bash
{{self}}/resources/pr.py [PR_NUMBER] COMMAND [COMMAND ...]
```

Commands: `comments threads resolve rerequest minimize ci readme pushpreview diff units
prnumber`. The local ones (`ci readme pushpreview diff units prnumber`) take no PR number.
`ci`/`readme` get their command from `{{tools:detect-project}}`; override with
`--ci-cmd` / `--readme-cmd`.

## Modes (compose freely from the input)

- **local** (default) - review your own uncommitted/branch changes (diff vs the detected base).
  Read-only.
- **pr [N]** - also fetch PR #N's review comments and fold them into the findings. If N is
  omitted, infer it from the current branch with `pr.py prnumber`.
- **fix** - after reviewing, plan and apply fixes, run the detected tests, and commit/push.
- **writeback** - after pushing fixes, resolve threads, minimize prior comments, and re-request
  Copilot review. Implies a PR target.

Announce the resolved modes at the start, e.g. "review: local + fix" or "review: pr 264 +
fix + writeback".

## Model tiers

| Tier | What | Model |
|------|------|-------|
| 0 mechanical | `pr.py` (GitHub API, ci, readme, diff, push preamble) | script, no model |
| 1 delegation | review sub-agents (`implementor-reviewer`/`consumer-reviewer`/`security-reviewer`); fix executors (`fix-implementer`/`dev`/`test`) fanned across disjoint shards | each agent's pinned default (override per run) |
| 2 judgment   | shard the diff for review; dedup + classify findings; hand valid findings to the `planner`, which shards the fix work | opus (session model + `planner`) |

## Steps

### 1. Acquire the diff

```bash
{{self}}/resources/pr.py diff                      # git diff vs the auto-detected base
{{self}}/resources/pr.py diff --base origin/main   # explicit base
```

The base branch is auto-detected from the remote's default branch (origin/HEAD, falling back to
the conventional main or master); pass `--base` to override.

Build an inventory of **review units** from the changed files. One unit is normally one file,
except keep **atomic couplings** together (a generated file and its source, a test and the
fixture it asserts on) as a single unit. Tag each unit:
- **code set** - every changed source/test file (reviewed by `implementor-reviewer`).
- **consumer set** - public-facing surface only: public API/exports, CLI, README/docs,
  changelog, examples (reviewed by `consumer-reviewer`).
- **security set** - source touching a security-sensitive surface: untrusted input
  (request/CLI/file/network/env data), auth, crypto, secrets, filesystem or process execution,
  serialization, or a newly added dependency (reviewed by the adversarial `security-reviewer`).
  A pure-internal change with no such surface needs no security pass; when in doubt, include it.

A unit can be in more than one set.

### 2. Shard the changed files

Use the shared sharder rather than hand-rolling the shuffle/pack. Feed it the changed files as
units (one per line: a unit id then the files it covers); it randomizes the order and packs
them into shards, varying each file's neighbors each run so reviewers surface different
cross-cutting issues. Keep atomic couplings (a file and its paired golden/snapshot) on a single
unit line so they stay together:

```bash
{{self}}/resources/pr.py units \
  | {{tools:shard-plan}} --max-units 5
```

`pr.py units` emits the baseline review-unit inventory (one `<file>\t<file>` line per changed
file vs the detected base; pass `--base` to override). Merge any atomic-coupling lines before
the pipe when you want a file and its paired golden/snapshot to stay in one unit.

Pick `--max-units` from the review-agent model (sonnet: ~5 units/shard; opus: ~12). Shard the
code set, consumer set, and security set independently. Each output line is one shard:
`unit,unit<TAB>files`. Announce the shard counts.

### 3. Spawn one reviewer per shard, in parallel

For each code shard spawn an `implementor-reviewer`; for each consumer shard spawn a
`consumer-reviewer`; for each security shard spawn a `security-reviewer` (an adversarial,
attacker-mindset pass). Each agent's prompt carries: the target, its explicit file list, and an
instruction to scope findings to those files (read others only for context). All three are
read-only and carry their own rubric. Spawn all shard agents in a single message so they run
concurrently. The review sub-agents default to their pinned model (opus); with a model override
in the input (e.g. "review with sonnet"), pass it to every spawn, otherwise omit `model` and
they use that default.

### 4. (pr mode) Fetch GitHub PR comments

```bash
{{self}}/resources/pr.py PR_NUMBER comments threads
```

Carry the open inline comments into step 5 alongside the agent findings.

### 5. Evaluate and dedup (opus / judgment core)

Merge findings across shards (and PR comments). A cross-cutting issue can appear in more than
one shard - merge duplicates into one. Assign each a verdict:
- **valid** - real, the code should change.
- **already-fixed** - was valid but the current code already handles it.
- **invalid** - incorrect or environment-specific.

### 6. Report

Present one consolidated report: target and review-agent model; shard counts; counts by
severity (high/medium/low) and verdict; each valid finding with `file:line` and why it matters;
each invalid/already-fixed with a one-line reason; a closing verdict (clean, or N valid
findings to address). In **local** (no `fix`) mode, stop here - this is advisory.

### 7. (fix mode) Hand off to the planner, then apply

Do not write the fix plan here - hand the **valid** findings to the `planner` agent. The planner
turns them into a shard table: disjoint written-file sets (no two shards touch the same file)
with an executor and model per shard. It assigns:
- **mechanical** shards (doc/comment, a pattern replicated across files, a precise one-line
  change) -> `fix-implementer`, as a verbatim fix spec.
- **substantive** shards (logic, API, anything needing reasoning) -> `dev`, which implements
  with formal tests and then hands off to `test` for coverage certification.

Spawn one executor per shard from the planner's table, in a single batch, at the model the table
specifies. Wait for all to report (and for each `dev` shard's `test` certification) before
continuing. Never wait indefinitely: a shard (or a reviewer in step 3) that returns nothing
usable, reports an error, or stalls on a tool-approval prompt that timed out is a **failed
unit** - surface it and re-dispatch once or abort with what completed, do not hang. Then run the
detected CI and regenerate the README if applicable:

```bash
{{self}}/resources/pr.py ci
{{self}}/resources/pr.py readme
```

Commit, show the push preamble, then push:

```bash
{{self}}/resources/pr.py pushpreview
git commit -m "fix: address review findings"
git push
```

### 8. (writeback mode) Update the PR conversation

After pushing:

```bash
{{self}}/resources/pr.py PR_NUMBER resolve rerequest minimize
```

`resolve` closes all open threads, `rerequest` triggers a fresh Copilot review, `minimize`
hides pre-push comments (use `--dry-run` first to preview). Report what was resolved/minimized.

## Discipline

- No one-off inline probes: every check the fix agents make is a committed test, never an ad-hoc
  command. All build/test/lint/readme commands come from `{{tools:detect-project}}`.
- The reviewers are read-only. Only `fix` mode edits, and only through the agent chain:
  `implementor-reviewer`/`consumer-reviewer`/`security-reviewer` -> `planner` ->
  `fix-implementer`/`dev` -> `test`.
- Every shell command spawned agents run is a committed resource script (or a plain `git`/`jq`)
  covered by a Bash allow rule (see `resources/allowlist.json`), so no spawn ever blocks on a
  tool approval. A sub-agent that stalls is a failed unit, not a wait - see step 7.
- Do not force-push or rewrite history unless explicitly asked.
