# agents

A personal library of Claude Code agent profiles and skills. It is a [`mind`](https://github.com/jaemk/mind)
source: `mind meld` installs the items and symlinks them into Claude's discovery locations
(`~/.claude`). A small manager (`x`) handles linting, review, and config sync. Everything is
language-agnostic: build/test/lint/doc/version commands come from a project-type detector, never
hardcoded.

## Layout

```
agents/<name>.md            agent profiles (frontmatter: name, model, tools, description)
skills/<name>/SKILL.md      skills, with optional skills/<name>/resources/ helper scripts
tools/<name>/               mind tools: shared scripts referenced via {{tools:<name>}}
                            (detect-project, shard-plan)
resources/                  other shared files: reviewer-prompt.md, audit-shell-allowlist.py
mind.toml                   mind source manifest (install hook)
x                           the manager (lint/review/config sync)
tests/run.sh                hermetic test harness (no network, uses temp dirs)
config/                     backup of the user's personal ~/.claude files (synced via `x config`)
```

## Install

This repo is a [`mind`](https://github.com/jaemk/mind) source. To install everything, meld it:

```bash
mind meld .                          # from a local clone
mind meld git@github.com:jaemk/agents   # straight from the remote
mind meld jaemk/agents               # shorthand for the GitHub remote
```

`mind meld` clones and registers the source, installs its items (skills, agents, tools - found by
convention plus `mind.toml`), and runs the declared `config apply` install hook to sync the
personal `~/.claude` files. Use `mind learn <item>` to install a single item, `mind recall` to see
what is installed, and `mind sync --upgrade` to pull updates. See the mind README for the full
command set.

Under the hood mind copies each item into its store and symlinks it into each agent home
(`~/.claude` by default) so Claude discovers it.

## Using `x`

```bash
./x install              # install everything (idempotent; skips unchanged items)
./x install review       # install one item by name
./x status               # show per-item state: not-installed / up-to-date / needs-upgrade / drift
./x check                # lint agent + skill files and their resources (warnings allowed)
./x check --strict       # treat genericity warnings as failures
./x uninstall review     # remove an item's symlink and copy (never touches real user files)
./x review skill:review  # run an opus critique of an item against resources/reviewer-prompt.md
./x review skill:review --fix   # apply the critique's suggestions in place
./x config diff          # show what config/ would change in the live ~/.claude files
./x config apply         # push config/ -> live (merges settings.json, overwrites CLAUDE.md)
./x config pull          # refresh the config/ backups from the live ~/.claude files
./x help
```

`NAME` is a bare name, `agent:<name>`, `skill:<name>`, or `resources` (the shared dir). With no
name, `x` operates on everything.

## Contents

Agents:
- `implementor-reviewer` - read-only review from the author's perspective.
- `consumer-reviewer` - read-only review from the downstream user's perspective.
- `planner` - designs plans and shards work across disjoint agents with model tiers (randomized).
- `dev` - implements with formal tests; always hands off to `test`.
- `test` - certifies and improves coverage from outside the implementor's perspective.
- `fix-implementer` - applies an explicit fix spec verbatim.

Skills:
- `do` - plan and (optionally) implement a change end to end: planner -> fix-implementer/dev ->
  test -> CI. Plans only, or plans and builds, depending on the prompt.
- `review` - review local changes and/or a GitHub PR; optionally fix findings and write back.
- `release` - bump versions, update changelog/migration guide, regenerate README, or run a
  pre-release review.
- `consumer-experience-review` - audit a library by building a throwaway external consumer.
- `voice` - learn and maintain the user's writing voice: mine commit messages across `~/dev`,
  fold in feedback, and run draft/rewrite training rounds. The profile lives in the XDG data dir
  (`~/.local/share/agents/voice/voice-profile.md`), scope-allowed in settings.json, and CLAUDE.md
  references it so writing tasks load it on demand.

## Development

Edit the source here and re-meld (`mind meld .`) to reinstall. Never hand-edit installed copies.
Before committing changes to `x` or any resource script, run the harness:

```bash
bash tests/run.sh
```

It is hermetic (temp dirs, no network) and exercises every `x` subcommand and every resource
script. See `CLAUDE.md` for the project rules (all logic in resource scripts, no one-off
probes, all testing committed, language-agnostic via the detector).
