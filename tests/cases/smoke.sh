#!/usr/bin/env bash
# smoke: the real library itself is well-formed and installable.

test_smoke_real() {
    roots; AR="$REPO"
    cap runx check
    assert_exit 0 "$RC" "smoke: x check on the real library exits 0 (warnings allowed)"
    cap runx status
    assert_exit 0 "$RC" "smoke: x status on the real library exits 0"
    cap runx install --dry-run
    assert_exit 0 "$RC" "smoke: x install --dry-run exits 0"
    assert_contains "$OUT" "install" "smoke: dry-run lists install actions"
}

register test_smoke_real
