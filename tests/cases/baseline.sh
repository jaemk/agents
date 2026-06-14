#!/usr/bin/env bash
# release/resources/release-baseline.sh: gather pre-release baseline signals.

# Build a throwaway git repo with two tagged releases, a CHANGELOG, and history.
_mk_release_repo() {
    local g="$1"
    git -C "$g" init -q
    git -C "$g" config user.email t@t.t
    git -C "$g" config user.name tester
    printf '## [Unreleased]\n\n## [0.2.0]\n\n## [0.1.0]\n' > "$g/CHANGELOG.md"
    echo a > "$g/f.txt"
    git -C "$g" add -A
    git -C "$g" commit -qm "release: bump version to 0.1.0"
    git -C "$g" tag v0.1.0
    echo b >> "$g/f.txt"
    git -C "$g" add -A
    git -C "$g" commit -qm "feat: add a feature since release"
}

test_baseline_report() {
    local d; d="$(mktemp_d)"; _mk_release_repo "$d"
    cap "$BASELINE" "$d"
    assert_exit 0 "$RC" "baseline: report exits 0"
    assert_contains "$OUT" "v0.1.0" "baseline: shows the last tag"
    assert_contains "$OUT" "0.2.0" "baseline: shows changelog version heading"
    assert_contains "$OUT" "add a feature since release" "baseline: shows recent commits"
    assert_contains "$OUT" "== changelog version headings" "baseline: labels the changelog section"
}

test_baseline_no_changelog() {
    local d; d="$(mktemp_d)"; _mk_release_repo "$d"
    rm -f "$d/CHANGELOG.md"
    cap "$BASELINE" "$d"
    assert_exit 0 "$RC" "baseline: report exits 0 without a changelog"
    assert_contains "$OUT" "(no CHANGELOG.md)" "baseline: notes a missing changelog"
}

test_baseline_diff() {
    local d; d="$(mktemp_d)"; _mk_release_repo "$d"
    cap "$BASELINE" --diff v0.1.0 "$d"
    assert_exit 0 "$RC" "baseline: --diff exits 0"
    assert_contains "$OUT" "f.txt" "baseline: --diff stats the changed file"
}

test_baseline_errors() {
    local d; d="$(mktemp_d)"   # plain dir, not a git repo
    cap "$BASELINE" "$d"
    assert_exit 3 "$RC" "baseline: non-git dir -> exit 3"
    assert_contains "$OUT" "not a git repository" "baseline: names the non-git failure"
    cap "$BASELINE" --diff
    assert_exit 2 "$RC" "baseline: --diff without REF -> exit 2"
}

register test_baseline_report test_baseline_no_changelog test_baseline_diff test_baseline_errors
