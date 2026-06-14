#!/usr/bin/env bash
# status state machine.

test_status_lifecycle() {
    roots; AR="$GOOD"
    cap runx status --json
    assert_exit 0 "$RC" "status --json: exit 0"
    assert_eq "not-installed" "$(state_of "$OUT" "skill:sample")" "status: fresh -> not-installed"
    cap runx install
    cap runx status --json
    assert_eq "up-to-date" "$(state_of "$OUT" "skill:sample")"     "status: installed skill up-to-date"
    assert_eq "up-to-date" "$(state_of "$OUT" "agent:sample")"     "status: installed agent up-to-date"
    assert_eq "up-to-date" "$(state_of "$OUT" "shared:resources")" "status: installed shared up-to-date"
}

test_status_drift() {
    roots; AR="$GOOD"
    cap runx install
    rm -f "$CH/skills/sample"
    cap runx status --json
    assert_eq "drift" "$(state_of "$OUT" "skill:sample")" "status: removed symlink -> drift"
    roots
    cap runx install
    echo "tampered" >> "$AH/skills/sample/resources/hello.sh"
    cap runx status --json
    assert_eq "drift" "$(state_of "$OUT" "skill:sample")" "status: tampered install copy -> drift"
}

register test_status_lifecycle test_status_drift
