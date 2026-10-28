# agents

A personal library of Claude Code agent profiles and skills. It is a [`mind`](https://github.com/jaemk/mind)
source: `mind meld` installs the items and symlinks them into Claude's discovery locations
(`~/.claude`). A small manager (`x`) handles linting and review. Everything is
language-agnostic: build/test/lint/doc/version commands come from a project-type detector, never
hardcoded.

## Layout

```
agents/<name>.md            agent profiles (frontmatter: name, model, tools, description)
skills/<name>/SKILL.md      skills, with optional skills/<name>/resources/ helper scripts
tools/<name>/               mind tools: shared scripts referenced via {{tools:<name>}}
                            (detect-project, shard-plan)
resources/                  other shared files: reviewer-prompt.md, audit-shell-allowlist.py
resources/allowlist.json    Bash allow rules the library needs (audited by the tests)
mind.toml                   mind source manifest (prefix k)
x                           the manager (lint/review)
tests/run.sh                hermetic test harness (no network, uses temp dirs)
```

## Install

This repo is a [`mind`](https://github.com/jaemk/mind) source. To install everything, meld it:

```bash
mind meld .                          # from a local clone
mind meld git@github.com:jaemk/agents   # straight from the remote
mind meld jaemk/agents               # shorthand for the GitHub remote
```

`mind meld` clones and registers the source and installs its items (skills, agents, tools - found
by convention plus `mind.toml`). Every item installs under the `k:` prefix (`k:review`,
`k:do`). Use `mind learn <item>` to install a single item, `mind recall` to see what is
installed, and `mind sync --upgrade` to pull updates. See the mind README for the full command
set.

## Using `x`

```bash
./x check                # lint agent + skill files and their resources (warnings allowed)
./x check --strict       # treat genericity warnings as failures
./x status               # show per-item state: not-installed / up-to-date / needs-upgrade / drift
./x review skill:review  # run an opus critique of an item against resources/reviewer-prompt.md
./x review skill:review --fix   # apply the critique's suggestions in place
./x help
```

`NAME` is a bare name, `agent:<name>`, `skill:<name>`, or `resources` (the shared dir). With no
name, `x` operates on everything.

## Contents

Agents:
- `planner` - designs plans and shards work across disjoint agents with model tiers (randomized).
- `dev` - implements with formal tests; always hands off to `test`.
- `test` - certifies and improves coverage from outside the implementor's perspective.
- `fix-implementer` - applies an explicit fix spec verbatim.
- `implementor-reviewer` - read-only review from the author's perspective.
- `consumer-reviewer` - read-only review from the downstream user's perspective.
- `security-reviewer` - read-only adversarial review for exploitable vulnerabilities.

Skills:
- `do` - plan and (optionally) implement a change end to end: planner -> fix-implementer/dev ->
  test -> CI. Plans the spec changes too in a spec-driven project.
- `review` - review local changes and/or a GitHub PR; optionally fix findings and write back.
- `spec` - set up and maintain a `spec/` dir: a feature-status table and per-topic docs with
  stable IDs.
- `hermetic-verify` - verify behavior with a committed test first, and probe through one
  allowlisted runner (`scripts/probe.sh`).
- `consumer-experience-review` - audit a library by building a throwaway external consumer.
- `voice` - learn and maintain the user's writing voice from commit history, feedback, and
  draft/rewrite rounds. The rules live at `~/.local/share/agents/voice/voice-rules.md` (imported
  by `~/.claude/CLAUDE.md`), the evidence behind them in `voice-profile.md` next to it.

## Development

Edit the source here, then run `mind upgrade --yes` to install the changes. Never hand-edit
installed copies.

```bash
make check               # x check
make test                # the hermetic harness: every x subcommand and resource script
```

See `CLAUDE.md` for the project rules (all logic in resource scripts, no one-off probes, all
testing committed, language-agnostic via the detector).
