You are reviewing ONE agent or skill definition from a personal Claude Code library against the
rubric and rules below. The MODE for this run - review-only, or review-and-fix - is stated on
the first line of this prompt, above this text. Follow it.

The target file(s) are dumped verbatim below the `=== TARGET FILES ===` delimiter, each
preceded by a `--- <path> ---` header. A skill review includes its `SKILL.md` and every file
under its `resources/`. An agent review is the single `.md`.

## What to evaluate

1. Description / trigger quality. Does the frontmatter `description` tell Claude precisely WHEN
   to reach for this item and when not to? Vague or overlapping triggers cause mis-selection.
   Quote the weak phrasing and propose a sharper one.
2. Scope and altitude. Does the prose describe WHEN and WHY (judgment) and leave HOW
   (mechanics) to resource scripts? Flag any procedural logic embedded in prose that belongs in
   a script.
3. Resource-path correctness. Every `resources/<file>` path referenced in the prose must exist
   in the target dump. Flag references to missing files and resource files that are never
   referenced.
4. Model-tier fit. Is the declared `model` appropriate (mechanical/repetitive -> sonnet;
   genuine reasoning/judgment -> opus)? Flag mismatches.
5. Genericity. Flag every hardcoded project assumption: `cargo`, `make`, `make ci`, `npm`,
   `pytest`, `origin/master`, specific crate/package/module names, fixed file layouts. These
   must route through `resources/detect-project.sh` instead. State the exact offending tokens.
6. Testability. Is every resource script and every claimed behavior covered by a committed test
   in `tests/`? If the item implies behavior that is only "verified" by ad-hoc inspection, that
   is a finding.

## NON-NEGOTIABLE RULES (judge the target against these; any violation is at least medium)

```
LOUD RULES - THESE ARE NOT OPTIONAL
1. ALL non-reasoning logic MUST live in committed resource scripts. Prose describes when/why;
   scripts do how. No procedural mechanics buried in agent/skill text.
2. NO ONE-OFF INLINE PROBES. An agent or skill must NEVER generate or run ad-hoc bash/python to
   inspect, parse, or test something. If a probe is needed it becomes a committed resource
   script with a stable, documented interface - then it can be tested.
3. ALL TESTING IS COMMITTED. Every skill and every resource script must be exercised by real,
   committed tests in tests/run.sh. Exploratory commands are NOT a substitute for a test case.
4. LANGUAGE-AGNOSTIC. No hardcoded cargo/make/npm/pytest/origin-master/crate names anywhere.
   Build/test/lint/doc/version go through resources/detect-project.sh.
```

## Output

**Review-only mode** - change nothing. Output a flat numbered list of findings:

```
N. [HIGH|MEDIUM|LOW] <area> - one-sentence summary
   Detail: what is wrong, the exact offending text/token, and the concrete fix.
```

**Review-and-fix mode** - apply each fix by editing the file in place at the path shown in its
`--- <path> ---` header (your working directory is the repo root, so those paths are editable).
Every fix must comply with the LOUD RULES: if a fix moves logic into a resource script, create
the script AND add a committed test for it in `tests/run.sh`. Then output the same numbered
list, written in past tense, describing what you changed in each file.

Close (both modes) with one line:

```
Genericity verdict: <generic | has N hardcoded assumptions (list tokens)>
```

If the target is already clean, say "No findings" (review-only) or "No changes needed"
(review-and-fix). Do not pad the list.

=== TARGET FILES ===
