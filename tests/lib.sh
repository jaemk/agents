#!/usr/bin/env bash
# Test harness infrastructure: assertions, isolation helpers, and a tiny registry.
# Sourced by tests/run.sh before the case files. No framework, no network.
#
# A test is a shell function named `test_*` that runs assertions. Each case file
# under tests/cases/ defines such functions and calls `register` with their names
# (in the order they should run). run.sh sources the cases then calls `run_cases`.
#
# Isolation: a test that installs calls `roots` for fresh temp AGENTS_HOME/CLAUDE_HOME,
# and sets AR (AGENTS_REPO). All temp dirs are tracked and removed on exit, so the real
# ~/.agents and ~/.claude are never touched.

# --- paths ------------------------------------------------------------------

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$LIB_DIR/.." && pwd)"
X="$REPO/x"
DET="$REPO/resources/detect-project.sh"
SHARD="$REPO/resources/shard-plan.py"
PR_PY="$REPO/skills/review/resources/pr.py"
BUMP="$REPO/skills/release/resources/bump-version.sh"
BASELINE="$REPO/skills/release/resources/release-baseline.sh"
AUDIT="$REPO/resources/audit-shell-allowlist.py"
GOOD="$LIB_DIR/fixtures/good"
BAD="$LIB_DIR/fixtures/bad"
FIXBIN="$LIB_DIR/fixtures/bin"

# --- assertions -------------------------------------------------------------

TESTS_RUN=0
TESTS_FAIL=0

_ok()   { TESTS_RUN=$((TESTS_RUN+1)); echo "ok   - $1"; }
_fail() { TESTS_RUN=$((TESTS_RUN+1)); TESTS_FAIL=$((TESTS_FAIL+1)); echo "FAIL - $1"; [[ -n "${2:-}" ]] && echo "       $2"; }

assert_eq()           { [[ "$1" == "$2" ]] && _ok "$3" || _fail "$3" "expected [$1] got [$2]"; }
assert_ne()           { [[ "$1" != "$2" ]] && _ok "$3" || _fail "$3" "expected != [$1]"; }
assert_contains()     { [[ "$1" == *"$2"* ]] && _ok "$3" || _fail "$3" "[$2] not in output"; }
assert_not_contains() { [[ "$1" != *"$2"* ]] && _ok "$3" || _fail "$3" "[$2] unexpectedly present"; }
assert_file()         { [[ -f "$1" ]] && _ok "$2" || _fail "$2" "missing file $1"; }
assert_exec()         { [[ -x "$1" ]] && _ok "$2" || _fail "$2" "not executable $1"; }
assert_no_path()      { [[ ! -e "$1" ]] && _ok "$2" || _fail "$2" "path exists $1"; }
assert_symlink_to()   { [[ -L "$1" && "$(readlink "$1")" == "$2" ]] && _ok "$3" || _fail "$3" "symlink $1 -> $(readlink "$1" 2>/dev/null) != $2"; }
assert_not_symlink()  { [[ ! -L "$1" ]] && _ok "$2" || _fail "$2" "$1 is unexpectedly a symlink"; }
assert_exit()         { [[ "$1" == "$2" ]] && _ok "$3" || _fail "$3" "expected exit $1 got $2"; }

# --- temp dir tracking ------------------------------------------------------

TMPDIRS=()
mktemp_d() { local d; d="$(mktemp -d)"; TMPDIRS+=("$d"); printf '%s' "$d"; }
cleanup() { local d; for d in "${TMPDIRS[@]:-}"; do [[ -n "$d" ]] && rm -rf "$d"; done; }
trap cleanup EXIT

# --- run helpers ------------------------------------------------------------

# Globals set per test and consumed by runx/cap.
AH="" ; CH="" ; AR="" ; OUT="" ; RC=0

# A stub `claude` that echoes its args, so `x review` needs no network.
STUB="$(mktemp_d)/claude"
cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
echo "CLAUDE_STUB called with: $*"
EOF
chmod +x "$STUB"

roots()    { AH="$(mktemp_d)"; CH="$(mktemp_d)"; }
runx()     { AGENTS_HOME="$AH" CLAUDE_HOME="$CH" AGENTS_REPO="$AR" CLAUDE_BIN="$STUB" "$X" "$@"; }
cap()      { OUT="$("$@" 2>&1)"; RC=$?; }
cap_cd()   { local d="$1"; shift; OUT="$(cd "$d" && "$@" 2>&1)"; RC=$?; }
state_of() { printf '%s' "$1" | jq -r --arg id "$2" '.[] | select(.id==$id) | .state'; }

# A throwaway git repo with an origin/master ref, for pr.py diff/pushpreview tests.
mk_git_repo() {
    local g="$1"
    git -C "$g" init -q
    git -C "$g" config user.email t@t.t
    git -C "$g" config user.name tester
    echo a > "$g/f.txt"
    git -C "$g" add f.txt
    git -C "$g" commit -qm init
    git -C "$g" update-ref refs/remotes/origin/master HEAD
}

# Run pr.py with the stub `gh` on PATH (hermetic; no GitHub network).
pr_gh() { PATH="$FIXBIN:$PATH" "$PR_PY" "$@"; }

# Commit to a repo as a specific author identity (for mine-commits tests).
git_commit_as() {
    local repo="$1" name="$2" email="$3" subject="$4" body="${5:-}"
    printf '%s\n' "$subject" >> "$repo/log.txt"
    git -C "$repo" add -A
    local args=(-m "$subject")
    [[ -n "$body" ]] && args+=(-m "$body")
    GIT_AUTHOR_NAME="$name" GIT_AUTHOR_EMAIL="$email" \
    GIT_COMMITTER_NAME="$name" GIT_COMMITTER_EMAIL="$email" \
        git -C "$repo" commit -q "${args[@]}"
}

# --- registry ---------------------------------------------------------------

CASES=()
register() { CASES+=("$@"); }

run_cases() {
    local filter="${1:-}" t
    for t in "${CASES[@]}"; do
        [[ -n "$filter" && "$t" != *"$filter"* ]] && continue
        echo "# $t"
        "$t"
    done
    echo "---"
    echo "PASS $((TESTS_RUN-TESTS_FAIL)) / FAIL $TESTS_FAIL  (total $TESTS_RUN)"
    [[ $TESTS_FAIL -eq 0 ]]
}
