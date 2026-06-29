---
name: consumer-experience-review
description: Review a library/package from the perspective of an external downstream consumer. Build a throwaway project that depends on it the way a real user would, exercise the public API with naive-but-reasonable code, and surface gaps, inconsistencies, and inconveniences with tool-verified evidence (a captured compiler/type/import error, not an assertion). Language-agnostic. Use for "review the consumer/user experience", "find API gaps", "evaluate the public API", "is this ready to publish", or before a 1.0 / major release.
---

# Consumer-experience review

You are auditing a library as the people who will install it (`cargo add` / `npm install` /
`pip install`) - not as its author. The project's own tests run inside its privacy and import
context and therefore **cannot** see the gaps a real consumer hits (missing root re-exports,
import friction, name collisions, optional-dependency dead-ends, error types you can't name).
The only reliable instrument is a separate project that depends on the library **externally**
and uses it the way a reasonable-but-not-omniscient user would.

## Core principle

**Write the code a competent user would write on their first try - reaching for conventional
names and paths - and let it fail. The natural call that doesn't compile/import/resolve *is* the
finding.** Do not pre-correct your consumer code with insider knowledge; that hides exactly what
you are looking for. Evidence is a captured tool error, not an assertion.

## 0. Identify the ecosystem

```bash
{{tools:detect-project}} .
```

The reported `type` and `version_files` tell you how a consumer depends on and invokes this
project (Cargo / npm / pip / Go module). Everything below is the same methodology; the
mechanics differ per ecosystem and are given as parallel examples.

## Procedure

### 1. Map the public surface (read it, don't trust memory)

Enumerate what a consumer actually sees:
- **Root re-exports** vs what is only reachable via deeper paths. Asymmetry here is the #1
  source of findings (Rust `crate::sub::Foo` vs root; JS package `exports`/subpath; Python
  `__init__.py` re-exports).
- **Every public name and signature** - look for two entry points that share a **name** and
  collide when both are in scope (e.g. sync vs async pairs), and for mutable-receiver/awkward
  signatures where a consumer expects the simple form.
- **Constructors / builders** - is `new()` returning the value or a builder? Is the fallible
  path `build()` or `try_build()`? Consistent across siblings?
- **Error types** - can the error returned by a public function be **named via the same path the
  type came from**? (A classic gap: the type is at the root but its error is only at a submodule
  path.)
- **Optional features / extras** - what is gated, and does a plausible feature/extra combination
  leave a type unreferenceable or an entry point unusable? (Cargo features, npm optional
  peer deps / dual ESM-CJS, Python extras.)
- **Macros / codegen / decorators** - exposed at the conventional root, or only deep? Ecosystem
  convention is usually the root.

### 2. Scaffold a throwaway external consumer

- Put it in `./local/` (gitignored) - **never inside the repo proper, never in git**. Do
  not pollute the project's examples/tests/working tree. Create `./local/` if it does not exist.
- Depend on the library the way a real external project does, by local path with a realistic
  feature set:
  - Rust: `lib = { path = "/abs/path", features = [...] }`
  - npm: `npm link` or a `file:` dependency
  - Python: `pip install -e /abs/path` (with extras)
- Exercise the breadth: each public entry point, sync and async paths, builders, error handling,
  and at least one less-common feature/extra combination.

### 3. Write naive-but-reasonable consumer code

Deliberately reach for conventions first:
- Import from the package root before trying deep/submodule paths.
- Bring the obvious names into scope together (or glob-import) - exactly what a real user does.
- Name the error type returned by a builder/constructor in a signature or annotation.
- Guess builder/option names by convention (`max_size`, `capacity`, `with_*`). A wrong guess the
  tooling can't disambiguate is itself a discoverability finding.

### 4. Build / run / capture exact errors

Get the build and test commands from the detector rather than assuming them:

```bash
{{tools:detect-project}} <consumer-dir> --what build
{{tools:detect-project}} <consumer-dir> --what test
```

For every failure, record the **exact** diagnostic - the error code and message (Rust
`error[E0034]`/`E0432`, a TS type error, a Python `ImportError`/`AttributeError`). That verbatim
error is the evidence in your report.

### 5. Isolate each gap in a minimal probe

For each suspected issue create a tiny separate binary/module/script that triggers **only** that
issue with the smallest natural snippet. This proves it is real and not a side effect, and gives
a clean before/after to re-run once a fix is proposed.

### 6. Severity - weight the release window

- **Pre-1.0 / major bump:** a hard failure on a *common* operation, or any public-surface
  inconsistency, is **high** - this is the only non-breaking window to fix the public surface.
  Say so.
- **Post-1.0 minor:** a breaking fix is itself a cost; lean toward additive fixes (new
  re-exports, aliases, deprecations) and documentation.
- Always separate: high (blocks / forces ugly workarounds on common paths), medium (awkward but
  workable), low (docs / discoverability).

### 7. Report - evidence first, fixes proposed not applied

For each finding: the natural code that failed -> the exact tool error -> root cause (cite
`file:line`) -> a concrete proposed fix (and whether it is breaking or additive). Recommend a
subset given the release window. **Do not implement fixes unless asked** - this skill produces a
review. If asked to fix, re-run the isolated probes afterward to prove the natural code now
works, and run the project's full check (`{{tools:detect-project}} . --run ci`).

### 8. Clean up

Remove or abandon the scratch consumer project. Never leave it in the repo or stage it.

## Gap classes to actively check

- **Root re-export gaps / asymmetry** - a type at the root but its builder/error only at a deep
  path; one sibling exports its builder at the root, another doesn't.
- **Name collisions** - two in-scope entry points with the same name (sync vs async), forcing a
  qualified call. Fix: rename/prefix one; settle it pre-1.0.
- **Unnameable error types** - a constructor returns an error the consumer can't name from the
  path the type came from.
- **Constructor/builder inconsistency** - `new()` -> value vs `new()` -> builder; `build` vs
  `try_build`; one shared error vs per-type ones.
- **Entry point not at the conventional root** - a macro/decorator/helper reachable only deep.
- **Feature / extra dead-ends** - a plausible feature/extra set where a needed item is
  unreferenceable.
- **Awkward receivers/signatures for reads** - forcing a wrapper/lock for shared use.
- **Discoverability** - natural names that don't exist and have no alias; errors that don't hint
  the right import.

## Cautions

- Testing from inside the project (its own tests/examples/workspace member) is **not** a consumer
  test - it inherits the project's import/privacy context and misses the gaps. An external
  dependency is mandatory.
- Sandboxed builds may hit registry/network errors; this skill only needs the local path
  dependency plus standard deps. If a build fails for sandbox/network reasons (not a real gap),
  retry with the sandbox disabled before concluding.
- A finding is the *user's natural code failing*, not "the API is unusable" - the API may work
  fine once you know the trick. The cost being measured is "knowing the trick."
