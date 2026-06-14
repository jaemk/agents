# agents - personal agents + skills library

This repo holds reusable Claude Code agent profiles (`agents/`), skills (`skills/`), shared
tooling (`resources/`), and a manager (`x`). `config/` is a backup of the user's personal
`~/.claude` files (CLAUDE.md, settings.json) and is not part of the library.

## LOUD RULES (these are not optional)

1. **All non-reasoning logic lives in committed resource scripts.** Agent/skill prose describes
   *when* and *why*; scripts do *how*. Do not bury procedural mechanics in markdown.
2. **No one-off inline probes.** Never generate or run ad-hoc bash/python to inspect, parse, or
   "check if something works". If a probe is needed it becomes a committed resource script with a
   stable, documented interface. Then it can be tested.
3. **All testing is committed.** Every skill and every resource script is exercised by a real
   case in `tests/run.sh`. Exploratory commands are not a substitute for a test. If you add or
   change a resource script, add or update its test in the same change.
4. **Language-agnostic.** No hardcoded `cargo`/`make`/`npm`/`pytest`/`origin/master`/package
   names in any agent, skill, or resource. Route build/test/lint/doc/version through
   `resources/detect-project.sh`.
5. **No shell invocation that can block on approval.** Every command an agent or skill directs
   a (sub-)agent to run must be auto-approvable: a committed resource script (or a plain
   `git`/`jq`), with no `$(...)`, backticks, or `eval`, and covered by a `Bash(...)` rule in
   `config/settings.json`. `resources/audit-shell-allowlist.py` enforces this (test:
   `tests/cases/allowlist.sh`); when you add a skill/agent command, add its allow rule in the
   same change. Spawned agents declare a non-interactive `permissionMode` (`acceptEdits` for
   editors, `dontAsk` for read-only) so they never stall on a prompt. Orchestrators (`do`,
   `review`) never wait indefinitely: a unit that errors, returns nothing, or stalls on a
   timed-out approval is a failed unit - surface it and re-dispatch or abort, never hang.

## Layout

- `agents/<name>.md` - agent profiles (flat files, YAML frontmatter: name, model, tools,
  description).
- `skills/<name>/SKILL.md` - skills, with optional `skills/<name>/resources/` for helper scripts.
- `resources/` - shared, non-skill tooling: `detect-project.sh` (project-type detector),
  `reviewer-prompt.md` (the `x review` template).
- `x` - manager: install/uninstall/status/check/review (see `./x help`).
- `tests/run.sh` - the hermetic test harness; `tests/lib.sh` assertions; `tests/fixtures/`.
- `config/` - personal `~/.claude` backups (not installed by `x`).

## Workflow

- Use the `Makefile` for check and test entrypoints: `make check` before committing, `make test`
  to run the harness, `make install` to install. These delegate to `x` and `tests/run.sh` and add
  no logic of their own.
- Run `make check` before committing; `./x status` shows install state.
- Run `make test` before committing any change to `x` or a resource script; it must be green (it
  runs hermetically against temp dirs and makes no network calls).
- Edit the repo source and re-run `make install`; never hand-edit installed copies under
  `~/.agents` / `~/.claude`.
- Resource scripts must keep their executable bit and a shebang (`x check` enforces this).

## Conventions

Follow the user's standing preferences (ASCII only, no em dashes, terse and factual, no
`Co-Authored-By` lines). These are recorded in `config/CLAUDE.md`.
