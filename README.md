# agents

A personal library of Claude Code agent profiles and skills, plus a small manager (`x`) that
installs them to a generic location (`~/.agents`) and symlinks them into Claude's discovery
locations (`~/.claude`). Everything is language-agnostic: build/test/lint/doc/version commands
come from a project-type detector, never hardcoded.

## Layout

```
agents/<name>.md            agent profiles (frontmatter: name, model, tools, description)
skills/<name>/SKILL.md      skills, with optional skills/<name>/resources/ helper scripts
resources/                  shared tooling: detect-project.sh, reviewer-prompt.md
x                           the manager (install/uninstall/status/check/review)
tests/run.sh                hermetic test harness (no network, uses temp dirs)
config/                     backup of the user's personal ~/.claude files (synced via `x config`)
```

## Install model

`x install` copies each item to `~/.agents` (generic, tool-agnostic) and then symlinks it into
`~/.claude` so Claude discovers it:

- agents: `~/.agents/agents/<name>.md`  ->  symlink `~/.claude/agents/<name>.md`
- skills: `~/.agents/skills/<name>/`    ->  symlink `~/.claude/skills/<name>`
- shared: `~/.agents/resources/`        (copied, no symlink; referenced by path)

Install is hash-aware: an item whose source matches what is already installed is skipped. A
manifest at `~/.agents/manifest.json` records installed hashes.

The install roots are overridable via `AGENTS_HOME`, `CLAUDE_HOME`, and `AGENTS_REPO` (the test
harness points these at temp dirs).

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

Edit the source here and re-run `./x install`. Never hand-edit installed copies. Before
committing changes to `x` or any resource script, run the harness:

```bash
bash tests/run.sh
```

It is hermetic (temp dirs, no network) and exercises every `x` subcommand and every resource
script. See `CLAUDE.md` for the project rules (all logic in resource scripts, no one-off
probes, all testing committed, language-agnostic via the detector).
