---
name: hermetic-verify
description: The standard way to verify behavior in any project: encode the check as a formal hermetic test first, and run any unavoidable live check through one allowlisted runner (scripts/probe.sh) so it never triggers a per-run permission prompt. Use whenever you are about to run an app/CLI/binary to confirm something works, capture real output for docs, or reproduce a scenario by hand - especially when ad-hoc commands (env-var-prefixed runs, unique temp paths, command substitution) are forcing repeated approvals. Not for deciding what to assert (that is the test's job) or for changing app behavior. Language-agnostic. Use for "verify this works", "check the output", "reproduce X", or when probing generates approval prompts.
allowed-tools: Bash, Read, Edit, Write
---

# hermetic-verify

Verify behavior the cheap, repeatable, prompt-free way: make a formal test the default, and
route any unavoidable live check through one allowlistable runner.

Two failure modes this prevents:

1. Throwaway verification. An agent runs the binary/app by hand, sees it works, and moves on.
   The check evaporates; the next change re-breaks it silently.
2. Approval churn. Each hand-run uses a fresh temp path and an env-var prefix
   (`APP_HOME=/tmp/xyz123 ./bin ...`), so the harness cannot statically verify it and prompts
   every time. Dozens of near-identical single-use allowlist entries pile up and still never
   match the next run.

## The rule

1. Default to a formal, committed test.
2. If you must check live, run it through one statically-allowlistable command.
3. After probing, promote what you learned into a test so no one probes it again.

## Setup this skill enforces (do this before any live probe)

Steps 1-2 are the only per-project work (creating the runner); steps 3-4 are already handled
globally and are here so you know not to duplicate them. All steps are idempotent. A read-only
agent that cannot write files skips creation and just uses an existing runner (see Roles below).

1. **Require or create `scripts/probe.sh`.**
   - If it exists, use it.
   - If not, create it from this skill's template at `resources/probe.sh` (copy it to
     `scripts/probe.sh`, `chmod +x`, and adapt the BUILD and RUN sections to the project: use
     `{{tools:detect-project}} . --run build` for the build step; the run invocation points at
     the build's output). All isolation (temp dirs, env)
     lives INSIDE the script so the caller's command never needs an env-var prefix or a unique
     path.

2. **Gitignore it.** The runner is local dev tooling, not a committed artifact: add a
   `scripts/probe.sh` line to the project's `.gitignore` if not already ignored. The committed,
   shared contract is the allowlist entry and the CLAUDE.md note, not the script body - the
   script is regenerated from the template (or kept locally) per checkout.

3. **Do NOT re-add the runner permission per project - it is managed globally.**
   `"Bash(bash scripts/probe.sh *)"` lives in `~/dev/agents/config/settings.json`, which is
   merged into `~/.claude/settings.json` when mind installs the skills. The runner path is
   identical in every project, so that one global entry already covers this project's runner.
   Only add a project's OWN stable build/test/lint commands (its detected test/ci command, from
   `{{tools:detect-project}}`) to its committed `.claude/settings.json` if they prompt - never
   per-path entries, and never the
   probe.sh entry. For settings.json edits the `update-config` skill applies.

4. **Do NOT repeat the discipline in the project CLAUDE.md - it is managed globally.** The
   verify-by-test-first rule and the runner's purpose live in `~/dev/agents/config/CLAUDE.md`,
   merged into `~/.claude/CLAUDE.md`. At most add a one-line project-specific pointer (e.g. what
   fixture the runner melds); do not restate the general guidance.

## 1. Default to a test

Before running anything by hand to "see if it works", ask: can this be an assertion? Almost
always yes.

- Find the project's test harness and commands first: `{{tools:detect-project}} .` (or the
  repo's CONTRIBUTING/CLAUDE.md). Reuse its fixture helpers; do not invent a parallel setup.
- Encode the check where the project already keeps tests. Many projects ship a hermetic fixture
  for exactly this - one that drives the real binary against a shipped example under an isolated
  home/temp dir. Extend that fixture instead of running the CLI by hand.
- Run it with the detector's test command (`{{tools:detect-project}} . --run test`). Detected
  commands are stable and allowlistable, so they never churn.
- Assert on stable substrings/shape, not volatile values (hashes, timestamps, temp paths).

A behavior you would check by hand MUST become a test unless it genuinely cannot be automated
(real network, interactive auth that cannot be faked). If you skip automation, say so and why.

## 2. Probe without prompts

Some things are legitimately probe-first: capturing exact CLI output to paste into docs, or
exploring before you know what to assert. Funnel every such probe through `scripts/probe.sh`.
The principle: keep all dynamism INSIDE the script, so the agent-facing command is identical
every time and one allowlist entry covers all runs.

For example, a `scripts/probe.sh` can meld a shipped example into a hermetic home and run a
sequence of subcommands in one allowlisted call:
`bash scripts/probe.sh sub-a -- sub-b -- sub-c --yes -- sub-a`.

### Anti-patterns that force a prompt (never do these for a probe)

- An env-var prefix on the command: `APP_HOME=/tmp/x ./bin ...`. Put the env inside the runner.
- A unique temp path in the command itself (`/tmp/run-4815/...`). Generate it inside the runner;
  the caller's command must not carry it.
- Command substitution or shell expansion (`$(...)`, backticks, `${VAR}`), loops, or globs in
  the tool call - the harness cannot statically verify these. They belong inside the committed
  script, where they run fine.
- `cd <dir> && ...` one-offs. Have the runner resolve its own root.

The symptom you are avoiding: a `settings.local.json` that has grown dozens of single-use
entries like `APP_HOME=/tmp/ashome2 ... ./bin meld /tmp/assrc --yes`. Each was a prompt; none
helps the next run. One runner entry replaces all of them.

## 3. Promote the probe into a test

Once a probe shows the real behavior, encode it: paste the captured output into a test as the
expected substrings and add the test via the project's harness. The probe was scaffolding; the
test is the deliverable.

## Roles

- Writer agents (`dev`, `test`) own the per-project setup: create-and-gitignore the runner (the
  permission and the discipline note are already global, steps 3-4), then prefer tests and probe
  only through the runner.
- `fix-implementer` stays in scope: use an existing `scripts/probe.sh` if present, but do not set
  up tooling - if verification needs more than the spec's test, report and stop.
- Read-only reviewers (`implementor-reviewer`, `consumer-reviewer`, `security-reviewer`,
  `planner`) do not create or modify files: when they must run the app/CLI to verify a finding,
  they use an existing `scripts/probe.sh` if present, otherwise keep the probe minimal and note
  that the hermetic runner is missing.
