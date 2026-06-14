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
#   detect-project.sh [DIR] [--what KEY]
#
#   DIR        directory to inspect (default: .). Detection walks up to the root.
#   --what KEY one of: type build test lint doc readme version_files ci all
#              (default: all). Printing a single key omits the "key=" prefix.
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
usage: detect-project.sh [DIR] [--what KEY]
  KEY: type build test lint doc readme version_files ci all (default: all)
EOF
}

dir="."
what="all"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --what)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            what="$2"; shift 2 ;;
        --what=*)
            what="${1#--what=}"; shift ;;
        -h|--help)
            usage; exit 0 ;;
        --*)
            usage; exit 2 ;;
        *)
            dir="$1"; shift ;;
    esac
done

case "$what" in
    type|build|test|lint|doc|readme|version_files|ci|all) ;;
    *) usage; exit 2 ;;
esac

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
        command -v cargo-readme >/dev/null 2>&1 && readme="cargo readme"
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
