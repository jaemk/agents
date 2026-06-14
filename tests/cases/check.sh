#!/usr/bin/env bash
# check: linting of agents, skills, resources, and the cross-agent color audit.

test_check_good() {
    roots; AR="$GOOD"
    cap runx check
    assert_exit 0 "$RC" "check good: exit 0"
    assert_not_contains "$OUT" "FAIL" "check good: no failures"
}

test_check_malformed() {
    roots; AR="$BAD"
    cap runx check skill:badexec
    assert_exit 1 "$RC" "check badexec: exit 1"
    assert_contains "$OUT" "not executable" "check badexec: flags non-exec resource with shebang"
    cap runx check skill:badpy
    assert_exit 1 "$RC" "check badpy: exit 1"
    assert_contains "$OUT" "python syntax" "check badpy: flags python syntax error"
    cap runx check skill:ghostref
    assert_exit 1 "$RC" "check ghostref: exit 1"
    assert_contains "$OUT" "references missing resources/missing.sh" "check ghostref: flags missing resource ref"
    cap runx check agent:nodesc
    assert_exit 1 "$RC" "check nodesc: exit 1"
    assert_contains "$OUT" "empty description" "check nodesc: flags empty description"
}

test_check_strict() {
    roots; AR="$BAD"
    cap runx check skill:hascargo
    assert_exit 0 "$RC" "check hascargo: warn-only exit 0"
    assert_contains "$OUT" "WARN skill:hascargo" "check hascargo: emits warning"
    cap runx check skill:hascargo --strict
    assert_exit 1 "$RC" "check hascargo --strict: exit 1"
}

test_check_color_audit() {
    local car; car="$(mktemp_d)"; mkdir -p "$car/agents"
    printf -- '---\nname: a1\nmodel: sonnet\ntools: Read\ncolor: blue\ndescription: one.\n---\nbody\n' > "$car/agents/a1.md"
    printf -- '---\nname: a2\nmodel: sonnet\ntools: Read\ncolor: blue\ndescription: two.\n---\nbody\n' > "$car/agents/a2.md"
    printf -- '---\nname: a3\nmodel: sonnet\ntools: Read\ndescription: three.\n---\nbody\n' > "$car/agents/a3.md"
    roots; AR="$car"
    cap runx check
    assert_exit 1 "$RC" "check: duplicate agent color -> exit 1"
    assert_contains "$OUT" "already used by agent:a1" "check: reports the duplicate color clash"
    assert_contains "$OUT" "agent:a3: no color set" "check: warns on a missing color"
    cap runx check agent:a1
    assert_exit 0 "$RC" "check agent:a1 alone: global color audit skipped, exit 0"
    assert_not_contains "$OUT" "already used by" "check single agent: no global color audit"
}

test_check_permission_mode() {
    local pmd; pmd="$(mktemp_d)"; mkdir -p "$pmd/agents"
    printf -- '---\nname: bad\nmodel: sonnet\npermissionMode: dontask\ntools: Read\ncolor: blue\ndescription: one.\n---\nbody\n' > "$pmd/agents/bad.md"
    printf -- '---\nname: ok\nmodel: sonnet\npermissionMode: dontAsk\ntools: Read\ncolor: green\ndescription: two.\n---\nbody\n' > "$pmd/agents/ok.md"
    roots; AR="$pmd"
    cap runx check agent:bad
    assert_exit 1 "$RC" "check: invalid permissionMode -> exit 1"
    assert_contains "$OUT" "invalid permissionMode 'dontask'" "check: names the bad permissionMode"
    cap runx check agent:ok
    assert_exit 0 "$RC" "check: valid permissionMode -> exit 0"
}

register test_check_good test_check_malformed test_check_strict test_check_color_audit test_check_permission_mode
