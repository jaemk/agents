---
name: spec
description: Adopt and maintain a spec-driven workflow: a repo-root spec/ dir with a feature-status table, per-topic docs with stable append-only IDs, and a document-first discipline (plan before build). Four commands automate the mechanics: init, add, todo, sync.
allowed-tools: Bash, Read, Edit, Write, Agent
---

# spec

Manage a spec-driven workflow for any project. The spec lives in a `spec/` directory at the
project root. Its `README.md` holds a feature-status table (status: `done`, `planned`,
`partial`). Per-topic doc files carry stable append-only IDs (e.g. `AUTH-1`, `API-3`).

## Document-first discipline

A feature is documented via `add` (status `planned`) before planning or implementation begins.
Implementation follows via the `/do` chain. Once implemented and verified, the table row is
flipped to `done`. `/review` validates that the implementation matches the spec. This sequence
is mandatory: spec first, then build.

## Commands

### init

Scaffold the spec dir in a project that does not yet have one.

```bash
{{self}}/resources/spec.py init PROJECT
```

Creates `spec/README.md` with the table header, status legend, and Conventions section.
Idempotent: if `README.md` already exists, prints a message and exits 0 without touching it.

After `init`, populate per-feature spec docs by reviewing the existing codebase: read the
source, identify features already built, and call `add` for each with an appropriate status.
That review is the agent's job, not the script's.

### add

Add a new feature spec doc and append a table row.

```bash
{{self}}/resources/spec.py add "Feature Name" PROJECT --status planned --desc "Short description"
```

Slugifies the name to `<slug>.md`, creates the doc with an H1 and a starter ID (`PREFIX-1`),
and appends a row to the table. Exits 3 if the spec dir is not initialized or the file already
exists. Default status is `planned`. Use `--status partial` or `--status done` when back-filling
an existing project.

### todo

List specs not yet done (status `planned` or `partial`).

```bash
{{self}}/resources/spec.py todo PROJECT
{{self}}/resources/spec.py todo PROJECT --json
```

Prints one line per pending row as `<status><TAB><feature><TAB><spec-cell>`. Use this to
decide what to implement next. `--json` emits a JSON array for programmatic use.

### sync

Report status counts and surface inconsistencies: a table row whose referenced doc file is
missing, or a `*.md` in the spec dir not referenced by any row.

```bash
{{self}}/resources/spec.py sync PROJECT
{{self}}/resources/spec.py sync PROJECT --json
```

Exits 0 when clean, 1 when any inconsistency is found. Run after merging branches, renaming
files, or manual edits to the table to catch drift.

## Workflow summary

1. New project: `init`, then `add` one entry per planned feature (status `planned`).
2. New feature request: `add` first (status `planned`), then plan and implement via `/do`.
3. After implementation: flip the table row to `done`, run `sync` to verify consistency.
4. Backfill existing project: `init`, then `add` each known feature with its current status.
5. Periodic review: `todo` to see what is unimplemented; `sync` to catch drift.

## Notes

- `--dir D` overrides the spec directory name (default: `spec/`; falls back to `specs/` if
  it exists).
- Stable IDs in doc files are append-only. Mark a retired statement as removed; never reuse
  the number.
- The table parser tolerates the mind-style pipe format. Keep rows in the canonical form:
  `| Feature | Status | [slug.md](slug.md) |`.
