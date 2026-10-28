#!/usr/bin/env bash
# detect-project.sh - language-agnostic project-type detection and command mapping.
#
# Walks up from DIR to the nearest project marker and prints a stable set of
# key=value lines describing how to build/test/lint/doc/version that project.
# This is the single source of truth that replaces hardcoded `cargo`/`make`/`npm`
# assumptions in skills and their resource scripts. Callers ask the detector for a
# command instead of baking one in; an empty value means "no command known, skip".
#
# Usage:
#   detect-project.sh [DIR] [--what KEY | --run KEY]
#
#   DIR        directory to inspect (default: .). Detection walks up to the root.
#   --what KEY one of: type build test lint doc readme version_files ci all
#              (default: all). Printing a single key omits the "key=" prefix.
#   --run KEY  resolve the command for a runnable KEY (build test lint doc readme
#              ci) and execute it, so callers never capture-and-eval the string
#              themselves. An empty command for KEY is a no-op (exit 0). The
#              command's own exit status is propagated.
#
# Output (all): one `key=value` line per known key, e.g.
#   type=rust
#   build=cargo build
#   test=cargo test
#   lint=cargo clippy --all-targets
#   doc=cargo doc --no-deps
#   readme=cargo readme
#   version_files=Cargo.toml
#   ci=make ci
#
# Exit codes: 0 detected, 2 usage error, 3 unknown project type.

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
usage: detect-project.sh [DIR] [--what KEY | --run KEY]
  --what KEY: type build test lint doc readme version_files ci all (default: all)
  --run  KEY: build test lint doc readme ci (resolve the command and execute it)
EOF
}

dir="."
what="all"
run=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --what)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            what="$2"; shift 2 ;;
        --what=*)
            what="${1#--what=}"; shift ;;
        --run)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            run="$2"; shift 2 ;;
        --run=*)
            run="${1#--run=}"; shift ;;
        -h|--help)
            usage; exit 0 ;;
        --*)
            usage; exit 2 ;;
        *)
            dir="$1"; shift ;;
    esac
done

# --what and --run are mutually exclusive: --run executes, --what prints.
[[ -n "$run" && "$what" != "all" ]] && { usage; exit 2; }

case "$what" in
    type|build|test|lint|doc|readme|version_files|ci|all) ;;
    *) usage; exit 2 ;;
esac

# --run accepts only runnable command keys (not type/version_files/all).
if [[ -n "$run" ]]; then
    case "$run" in
        build|test|lint|doc|readme|ci) ;;
        *) usage; exit 2 ;;
    esac
fi

[[ -d "$dir" ]] || { echo "detect-project.sh: not a directory: $dir" >&2; exit 2; }

# Resolve to an absolute path so the walk-up terminates at filesystem root.
dir="$(cd "$dir" && pwd)"

# Walk up looking for the nearest marker. First matching directory wins; within a
# directory the marker precedence below decides the type for mixed repos.
root=""
type=""
d="$dir"
while :; do
    if [[ -f "$d/Cargo.toml" ]]; then root="$d"; type="rust"; break; fi
    if [[ -f "$d/package.json" ]]; then root="$d"; type="node"; break; fi
    if [[ -f "$d/pyproject.toml" || -f "$d/setup.py" || -f "$d/setup.cfg" ]]; then root="$d"; type="python"; break; fi
    if [[ -f "$d/go.mod" ]]; then root="$d"; type="go"; break; fi
    [[ "$d" == "/" ]] && break
    d="$(dirname "$d")"
done

# A Makefile with a `ci` target is honored across all types (preserves repos that
# centralize CI behind `make ci`); it is a detected option, never an assumption.
make_ci=""
if [[ -n "$root" && -f "$root/Makefile" ]] && grep -qE '^ci:' "$root/Makefile" 2>/dev/null; then
    make_ci="make ci"
fi

# node: only surface a script command when package.json actually defines it.
npm_script() {
    # $1 = script name; echoes "npm run <name>" if present, else nothing.
    local name="$1"
    if [[ "$type" == "node" ]] && command -v jq >/dev/null 2>&1; then
        if jq -e --arg n "$name" '.scripts[$n] // empty' "$root/package.json" >/dev/null 2>&1; then
            echo "npm run $name"
        fi
    fi
}

build="" ; test="" ; lint="" ; doc="" ; readme="" ; version_files="" ; ci=""

case "$type" in
    rust)
        build="cargo build"
        test="cargo test"
        lint="cargo clippy --all-targets"
        doc="cargo doc --no-deps"
        # A generated README is opt-in: cargo-readme's README.tpl marks a crate
        # whose README.md comes from its doc comment. Without it the README is
        # hand-written and regenerating it would replace it.
        if [[ -f "$root/README.tpl" ]] && command -v cargo-readme >/dev/null 2>&1; then
            readme="cargo readme"
        fi
        version_files="Cargo.toml"
        ci="${make_ci:-$test}"
        ;;
    node)
        build="$(npm_script build)"
        test="$(npm_script test)"
        [[ -z "$test" ]] && test="npm test"
        lint="$(npm_script lint)"
        doc="$(npm_script docs)"
        version_files="package.json"
        ci="${make_ci:-$test}"
        ;;
    python)
        build="python -m build"
        command -v pytest >/dev/null 2>&1 && test="pytest" || test="python -m pytest"
        if command -v ruff >/dev/null 2>&1; then lint="ruff check"
        elif command -v flake8 >/dev/null 2>&1; then lint="flake8"; fi
        if [[ -f "$root/pyproject.toml" ]]; then version_files="pyproject.toml"
        elif [[ -f "$root/setup.py" ]]; then version_files="setup.py"
        else version_files="setup.cfg"; fi
        ci="${make_ci:-$test}"
        ;;
    go)
        build="go build ./..."
        test="go test ./..."
        lint="go vet ./..."
        doc="go doc"
        version_files=""
        ci="${make_ci:-$test}"
        ;;
    *)
        type="unknown"
        if [[ "$what" == "type" ]]; then echo "unknown"; exit 3; fi
        echo "type=unknown" >&2
        exit 3
        ;;
esac

# --run: resolve the command for the requested key and execute it here, so callers
# issue one static invocation instead of capturing the string and eval-ing it. This
# is the single, tested place the resolved command is run.
if [[ -n "$run" ]]; then
    cmd=""
    case "$run" in
        build)  cmd="$build" ;;
        test)   cmd="$test" ;;
        lint)   cmd="$lint" ;;
        doc)    cmd="$doc" ;;
        readme) cmd="$readme" ;;
        ci)     cmd="$ci" ;;
    esac
    if [[ -z "$cmd" ]]; then
        echo "detect-project.sh: no '$run' command for $type project, skipping" >&2
        exit 0
    fi
    echo "detect-project.sh: running '$run' in $root: $cmd" >&2
    # Run from the project root so the command sees the right tree. The if/else
    # keeps set -e from masking the command's own exit status: $? in the else
    # branch is the failed subshell's code, which we propagate.
    if ( cd "$root" && eval "$cmd" ); then
        exit 0
    else
        exit $?
    fi
fi

emit() {
    local key="$1" val="$2"
    if [[ "$what" == "all" ]]; then
        echo "${key}=${val}"
    elif [[ "$what" == "$key" ]]; then
        echo "$val"
    fi
}

emit type "$type"
emit build "$build"
emit test "$test"
emit lint "$lint"
emit doc "$doc"
emit readme "$readme"
emit version_files "$version_files"
emit ci "$ci"
