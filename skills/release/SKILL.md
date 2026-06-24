---
name: release
description: Prepare a release or run a pre-release review. With a version string it bumps the version (via resources/bump-version.sh), updates the changelog and migration guide, regenerates the README, verifies, and commits. With `review` it runs an advisory pre-release audit (consistency review plus a consumer-experience-review) that changes nothing. Language-agnostic: version files, readme, and test commands come from detect-project.sh. Use for "cut a release", "bump the version", "release X.Y.Z", or "review for release".
---

# release

Prepare a new release by bumping the version and updating the changelog, or - with the
`review` argument - run a pre-release audit that surfaces inconsistencies without changing
anything. Language-agnostic: nothing here assumes a particular ecosystem; build/test/readme
commands and the version files come from the shared detector.

```bash
{{tools:detect-project}} .            # type, version_files, readme, test, ci
```

## Input

- **`review`** - run the **Release review** below. Advisory only: bumps nothing, edits nothing,
  commits nothing. Run it before cutting a release.
- **A version string** (e.g. `1.2.0`) - run the **Version bump** flow. If no argument is given
  and the intent is clearly to release, ask which version.

## Release review

A pre-release audit, run before cutting a release (especially a major, the only window in which
breaking changes are acceptable). It produces a report and changes nothing.

Gather the baseline signals with the helper (one auto-approvable command; all git/changelog
inspection lives in the script, not inline shell):

```bash
{{self}}/resources/release-baseline.sh .   # last tag, tags, changelog headings, recent commits
```

Reason over its output to pick the baseline: tags can lag the real version, so cross-check the
last tag against the changelog's version headings and the recent commits. If they disagree, use
the last-actually-released commit as the baseline. Then diff the whole accumulated surface
against it:

```bash
{{self}}/resources/release-baseline.sh --diff vX.Y.Z .   # git diff vX.Y.Z..HEAD --stat
```

Run two complementary reviews and synthesize:

### A. Consistency review

Audit the public surface across the **whole** project (everything since the last release), not
just the latest diff. Check:
- **Naming parity** - do sibling types/functions/flags share vocabulary? Flag the odd one out.
- **Constructor / builder symmetry** - do parallel families expose the same shape where it makes
  sense?
- **Signature parity** - do variants (sync/async, plain/batched) expose a consistent method set?
- **Doc / changelog / migration-guide alignment** - do they accurately describe the shipped API
  (named types, signatures, flags)?

Delegate the correctness/idiom sweep to an `implementor-reviewer` and the public-surface
intuition to a `consumer-reviewer`; reason through the cross-cutting parity items yourself.

### B. Consumer-experience review

Run the `consumer-experience-review` skill: it builds a throwaway external consumer that
depends on the project the way a real user would and surfaces API gaps, naming inconsistencies,
and dead-ends with **tool-verified evidence**.

### C. Synthesize

Merge both into one report: a flat list of inconsistencies (each with `file:line` or API path);
recommended changes split into **breaking** (mark "land now or wait for next major", with
migration cost) and **non-breaking** (additive/doc); and a recommendation on whether to release
as-is. Apply nothing. Then ask whether to address findings first or proceed to the bump.

## Version bump

Run these when the argument is a version string (or after a review, once the user opts in).

### 1. Bump the version

```bash
{{self}}/resources/bump-version.sh X.Y.Z
```

This updates the version field in the detected version file(s) (Cargo.toml `[package]`,
`package.json`, or pyproject `[project]`/`[tool.poetry]`), leaving dependency requirements
alone. It prints each file it changed. For a workspace with multiple independently-versioned
packages, run it per package directory (`bump-version.sh X.Y.Z path/to/pkg`).

### 2. Update the changelog

If the project keeps a `CHANGELOG.md`: replace `## [Unreleased]` with `## [X.Y.Z]`, add a fresh
empty `## [Unreleased]` above it, and keep an `[Unreleased]` section at the top at all times.

### 3. Migration guide

If the project keeps migration guides, add or update one for this version (named for the
PREV-to-X.Y.Z transition). Write it for agent consumption: terse and mechanical. For each
breaking change give Detection (what to grep/search for) and Action (the exact transformation).
If there are no breaking changes the guide still exists and says so. Match the established
format of existing guides.

### 4. Regenerate the README

If the project generates its README from source, run the detected generator:

```bash
{{tools:detect-project}} . --run readme   # no-op if no generator
```

If no generator is detected this is a no-op (exit 0); move on.

### 5. Verify

```bash
{{tools:detect-project}} . --run ci
```

Fix any failures before proceeding.

### 6. Commit

Stage the changed files (version file(s), changelog, migration guide, README) and commit, e.g.
`release: bump version to X.Y.Z`. If a single release commit already exists on the branch,
amend it. Do not add a `Co-Authored-By` line.

### 7. Report

State which version file(s) were bumped and to what, whether the README was regenerated, and
the resulting commit SHA.
