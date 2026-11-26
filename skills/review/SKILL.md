---
name: review
description: 'Review local changes against the detected base and report findings with severity and a verdict. Add `pr [N]` to include GitHub PR comments, `fix` to apply and verify fixes, and `writeback` to update PR review threads and re-request Copilot. Sub-agent delegation and sharding require an explicit request. Use for "review my changes", "review this PR", "review and fix", or "address the PR comments".'
allowed-tools: Bash, Read, Edit, Write, Agent
expand: resources/pr.py
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
- **fix** - after reviewing, plan and apply fixes, run the detected tests, and commit. Push
  only when the input asks for it or writeback mode is on.
- **writeback** - after pushing fixes, resolve threads, minimize prior comments, and re-request
  Copilot review. Implies a PR target.

Announce the resolved modes at the start, e.g. "review: local + fix" or "review: pr 264 +
fix + writeback".

## Execution

Review and apply requested fixes in the current session by default. Use sub-agents only for
stages the user explicitly asks to delegate. Shard the work only when the user explicitly asks
for sharding or parallel agent work. A PR target, fix mode, writeback, or model preference
does not by itself request delegation.

## Steps

### 1. Acquire the diff

```bash
{{self}}/resources/pr.py diff                      # git diff vs the auto-detected base
{{self}}/resources/pr.py diff --base origin/main   # explicit base
```

The base branch is auto-detected from the remote's default branch (origin/HEAD, falling back to
the conventional main or master); pass `--base` to override.

### 2. Review the changes

Read the changed files and enough surrounding code to check their behavior and callers.
Cover these perspectives where applicable.

- **Correctness:** Check intended behavior, regressions, edge cases, and test coverage.
- **Consumer impact:** Check public APIs, CLI, configuration, documentation, and examples
  from the user's perspective.
- **Security:** Check changed trust boundaries and sensitive operations, including untrusted
  input, auth, crypto, secrets, filesystem access, process execution, serialization, and new
  dependencies. Trace credible issues to their impact.

When the user explicitly requests delegated review, use the optional workflow below for the
requested review work and cover any remaining scope in the current session.

### 3. (pr mode) Fetch GitHub PR comments

```bash
{{self}}/resources/pr.py PR_NUMBER comments threads
```

Carry the open inline comments into the findings for evaluation.

### 4. Evaluate and deduplicate

Merge duplicate findings, including any PR comments. Assign each a verdict:
- **valid** - real, the code should change.
- **already-fixed** - was valid but the current code already handles it.
- **invalid** - incorrect or environment-specific.

### 5. Report

Report the target, counts by severity and verdict, each valid finding with `file:line` and
its impact, and a brief reason for each invalid or already-fixed finding. Close with the
overall verdict. Include delegation details if used. Without `fix`, stop after reporting.

### 6. (fix mode) Apply and verify fixes

Plan and apply fixes for the valid findings. Add or update formal tests as needed to cover the
corrected behavior. Use the optional workflow below for any fix stages the user explicitly
asked to delegate. Run the detected CI and regenerate the README if applicable:

```bash
{{self}}/resources/pr.py ci
{{self}}/resources/pr.py readme
```

`readme` runs only for a project that opts into a generated README (the detector reports a
generator command), and it leaves `README.md` unchanged when the output is under half its
current lines, which means the README is hand-written. Check `git diff --stat` before
committing either way.

Commit the fixes. Write the message in the user's voice (see their voice profile and the repo's
existing subjects): describe what changed in the code, not the review that found it. Then show
the push preamble, and push only when the input asked for a push or writeback mode is on:

```bash
git commit -m "<subject describing the fixes>"
{{self}}/resources/pr.py pushpreview
git push
```

### 7. (writeback mode) Update the PR conversation

After pushing:

```bash
{{self}}/resources/pr.py PR_NUMBER resolve rerequest minimize
```

`resolve` closes all open threads, `rerequest` triggers a fresh Copilot review, `minimize`
hides pre-push comments (use `--dry-run` first to preview). Report what was resolved/minimized.

## Explicit delegation and sharding

For delegated review, use `implementor-reviewer` for correctness, `consumer-reviewer` for
consumer impact, and `security-reviewer` for security, within the scope requested. Give each
reviewer the target and file scope. Keep reviewers read-only. Use a requested model override
or the profile's default.

When delegated review is explicitly requested in parallel or by shard, group work by applicable
perspectives and keep atomic couplings together, such as a generator and its output or a test
and its fixture. To shard a large perspective, generate the baseline inventory, edit it to
include only the relevant files and merge coupled files onto one line, then pass it to the
shared sharder. Pass the same `--base` to `units` as to `diff` if overridden.

```bash
{{self}}/resources/pr.py units --out ./local/review-units.txt
{{tools:shard-plan}} --max-units 5 ./local/review-units.txt
```

Each output line identifies one shard and its file list. Run independent reviewers together and
merge their findings with the rest of the review.

For requested delegation of fix stages, use `planner` for planning, `fix-implementer` for
precise mechanical edits, `dev` for substantive changes, or `test` for independent coverage
certification. Delegate only the requested stages. For explicitly requested fix sharding,
use the planner profile's disjoint write sets and respect dependencies between shards.
Use non-interactive permissions and allowlisted commands. Surface failed or stalled tasks and
continue directly when possible. Report any remaining blocker.

## Discipline

- Use formal project tests for verification and avoid one-off inline probes.
- Use `{{tools:detect-project}}` for build, test, lint, and README commands.
- Keep the review read-only unless the user requests fixes.
- Do not force-push or rewrite history unless explicitly asked.
