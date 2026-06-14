#!/usr/bin/env bash
# review/resources/pr.py: local commands (ci/readme/diff/pushpreview) and the
# GitHub commands (comments/threads/resolve/rerequest/minimize) via a gh stub.

test_pr_ci() {
    cap "$PR_PY" ci --ci-cmd true
    assert_exit 0 "$RC" "pr.py ci: passing command exits 0"
    assert_contains "$OUT" "CI passed" "pr.py ci: reports pass"
    cap "$PR_PY" ci --ci-cmd false
    assert_exit 1 "$RC" "pr.py ci: failing command exits non-zero"
    assert_contains "$OUT" "CI FAILED" "pr.py ci: reports failure"
    cap "$PR_PY" ci --ci-cmd 'echo redis-down; exit 1' --ignore redis
    assert_exit 0 "$RC" "pr.py ci: failure matching --ignore is tolerated"
    assert_contains "$OUT" "matched --ignore" "pr.py ci: reports ignore-tolerated pass"
}

test_pr_readme() {
    local d; d="$(mktemp_d)"
    cap_cd "$d" "$PR_PY" readme --readme-cmd 'echo GENERATED-README'
    assert_exit 0 "$RC" "pr.py readme: exit 0"
    assert_file "$d/README.md" "pr.py readme: writes README.md from generator stdout"
    assert_eq "GENERATED-README" "$(cat "$d/README.md")" "pr.py readme: README.md has generator output"
}

test_pr_diff_pushpreview() {
    local g; g="$(mktemp_d)"; mk_git_repo "$g"
    cap_cd "$g" "$PR_PY" diff
    assert_exit 0 "$RC" "pr.py diff: exit 0"
    assert_contains "$OUT" "diff origin/master" "pr.py diff: auto-detects base origin/master"
    cap_cd "$g" "$PR_PY" pushpreview
    assert_exit 0 "$RC" "pr.py pushpreview: exit 0"
    assert_contains "$OUT" "Push preview" "pr.py pushpreview: prints the push preamble"
}

test_pr_comments() {
    cap pr_gh 7 comments
    assert_exit 0 "$RC" "pr.py comments: exit 0"
    assert_contains "$OUT" "Total inline comments: 2" "pr.py comments: counts inline comments"
    assert_contains "$OUT" "NEW COMMENTS" "pr.py comments: splits new vs pre-existing"
}

test_pr_threads() {
    cap pr_gh 7 threads
    assert_exit 0 "$RC" "pr.py threads: exit 0"
    assert_contains "$OUT" "Unresolved: 1" "pr.py threads: counts unresolved threads"
}

test_pr_resolve() {
    cap pr_gh 7 resolve --dry-run
    assert_exit 0 "$RC" "pr.py resolve --dry-run: exit 0"
    assert_contains "$OUT" "would resolve" "pr.py resolve --dry-run: lists without mutating"
    cap pr_gh 7 resolve
    assert_exit 0 "$RC" "pr.py resolve: exit 0"
    assert_contains "$OUT" "Resolved 1/1" "pr.py resolve: mutates and reports the count"
}

test_pr_rerequest() {
    cap pr_gh 7 rerequest
    assert_exit 0 "$RC" "pr.py rerequest: exit 0"
    assert_contains "$OUT" "re-requested" "pr.py rerequest: confirms the re-request"
}

test_pr_minimize() {
    cap pr_gh 7 minimize --dry-run
    assert_exit 0 "$RC" "pr.py minimize --dry-run: exit 0"
    assert_contains "$OUT" "Found 2 eligible" "pr.py minimize: finds eligible comments before the cutoff"
    assert_contains "$OUT" "Would minimize" "pr.py minimize --dry-run: lists without mutating"
}

test_pr_units() {
    local g; g="$(mktemp_d)"; mk_git_repo "$g"
    echo b >> "$g/f.txt"   # working-tree change vs origin/master
    cap_cd "$g" "$PR_PY" units
    assert_exit 0 "$RC" "pr.py units: exit 0"
    assert_contains "$OUT" "f.txt"$'\t'"f.txt" "pr.py units: emits one <file>\\t<file> unit line per changed file"
}

test_pr_prnumber() {
    cap pr_gh prnumber
    assert_exit 0 "$RC" "pr.py prnumber: exit 0"
    assert_eq "7" "$OUT" "pr.py prnumber: prints the PR number inferred from the branch"
}

test_pr_argval() {
    cap "$PR_PY" bogus
    assert_exit 2 "$RC" "pr.py: unknown command -> exit 2"
    assert_contains "$OUT" "unknown command" "pr.py: names the bad command"
    cap "$PR_PY" comments
    assert_exit 2 "$RC" "pr.py: gh command without a PR number -> exit 2"
    assert_contains "$OUT" "PR number is required" "pr.py: explains the PR requirement"
}

register test_pr_ci test_pr_readme test_pr_diff_pushpreview test_pr_comments test_pr_threads test_pr_resolve test_pr_rerequest test_pr_minimize test_pr_units test_pr_prnumber test_pr_argval
