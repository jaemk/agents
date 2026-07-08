#!/usr/bin/env bash
# audit-shell-allowlist.py: every shell invocation in agent/skill prose must be
# covered by a Bash(...) allow rule, so a spawned sub-agent never stalls on approval.

# The real library must pass: scanning agents/ and skills/ against resources/allowlist.json
# finds no un-allowlisted command. This is the live invariant, not just a unit test.
test_allowlist_real() {
    cap "$AUDIT"
    assert_exit 0 "$RC" "allowlist: real agents+skills are all covered -> exit 0"
    assert_contains "$OUT" "OK" "allowlist: reports OK on the real library"
}

# An un-allowlisted command in a bash block is flagged and named.
test_allowlist_detects_gap() {
    local d; d="$(mktemp_d)"; mkdir -p "$d/skills/x"
    printf '%s\n' '---' 'name: x' 'description: d' '---' '' '```bash' 'curl http://example.test/x' '```' \
        > "$d/skills/x/SKILL.md"
    local s="$d/settings.json"; printf '%s' '{"permissions":{"allow":["Bash(jq:*)"]}}' > "$s"
    cap "$AUDIT" --settings "$s" "$d/skills"
    assert_exit 1 "$RC" "allowlist: un-allowlisted command -> exit 1"
    assert_contains "$OUT" "curl http://example.test/x" "allowlist: names the offending command"
}

# A covered script invocation passes.
test_allowlist_covers_allowed() {
    local d; d="$(mktemp_d)"; mkdir -p "$d/skills/y"
    printf '%s\n' '---' 'name: y' 'description: d' '---' '' '```bash' '~/.agents/resources/detect-project.sh . --run ci' '```' \
        > "$d/skills/y/SKILL.md"
    local s="$d/settings.json"; printf '%s' '{"permissions":{"allow":["Bash(~/.agents/resources/detect-project.sh:*)"]}}' > "$s"
    cap "$AUDIT" --settings "$s" "$d/skills"
    assert_exit 0 "$RC" "allowlist: an allowlisted script invocation -> exit 0"
}

# Builtins, piped segments, line continuations, and inline comments are all handled.
test_allowlist_pipes_builtins_comments() {
    local d; d="$(mktemp_d)"; mkdir -p "$d/agents"
    printf '%s\n' '---' 'name: z' 'model: opus' 'tools: Bash' 'description: d' '---' 'body' '' \
        '```bash' 'printf "a b" \' '  | ~/.agents/resources/shard-plan.py --max-units 4   # inline comment' '```' \
        > "$d/agents/z.md"
    local s="$d/settings.json"; printf '%s' '{"permissions":{"allow":["Bash(~/.agents/resources/shard-plan.py:*)"]}}' > "$s"
    cap "$AUDIT" --settings "$s" "$d/agents"
    assert_exit 0 "$RC" "allowlist: builtin + pipe + continuation + comment -> exit 0"
}

# A bad settings path is a usage/IO error, not a false pass.
test_allowlist_bad_settings() {
    local d; d="$(mktemp_d)"
    cap "$AUDIT" --settings "$d/nope.json" "$d"
    assert_exit 2 "$RC" "allowlist: missing settings file -> exit 2"
}

# mind expands a {{tools:}}/{{self}} token to the ABSOLUTE ~/.mind/store path at
# runtime, and Claude matches Bash rules literally (no ~ expansion), so a
# tilde-only rule does NOT cover the command - the absolute-form rule does. The
# audit simulates the absolute runtime form, so it must flag the tilde-only case
# and pass the absolute one.
test_allowlist_token_needs_absolute_rule() {
    local d; d="$(mktemp_d)"; mkdir -p "$d/skills/t"
    printf '%s\n' '---' 'name: t' 'description: d' '---' '' '```bash' '{{tools:detect-project}} .' '```' \
        > "$d/skills/t/SKILL.md"
    # Tilde-only rule: the absolute-form command is not covered.
    local s1="$d/tilde.json"; printf '%s' '{"permissions":{"allow":["Bash(~/.mind/store/**)"]}}' > "$s1"
    cap "$AUDIT" --settings "$s1" "$d/skills"
    assert_exit 1 "$RC" "allowlist: token cmd not covered by tilde-only rule -> exit 1"
    assert_contains "$OUT" "{{tools:detect-project}}" "allowlist: names the uncovered token command"
    # Absolute glob rule covering the real home: covered.
    local s2="$d/abs.json"; printf '{"permissions":{"allow":["Bash(%s/.mind/store/**/*)"]}}' "$HOME" > "$s2"
    cap "$AUDIT" --settings "$s2" "$d/skills"
    assert_exit 0 "$RC" "allowlist: token cmd covered by absolute glob rule -> exit 0"
}

# A `${HOME}` rule in a committed allowlist expands to the real home at audit time, so an
# absolute-path store command (a {{tools:}}/{{self}} token as Claude expands it at runtime)
# is covered without hardcoding the machine's home path in the repo.
test_allowlist_home_token_expands() {
    local d; d="$(mktemp_d)"; mkdir -p "$d/skills/h"
    printf '%s\n' '---' 'name: h' 'description: d' '---' '' '```bash' '{{tools:detect-project}} .' '```' \
        > "$d/skills/h/SKILL.md"
    local s="$d/settings.json"; printf '%s' '{"permissions":{"allow":["Bash(${HOME}/.mind/store/**/*)"]}}' > "$s"
    cap "$AUDIT" --settings "$s" "$d/skills"
    assert_exit 0 "$RC" "allowlist: \${HOME} rule covers the absolute store token -> exit 0"
}

register test_allowlist_real test_allowlist_detects_gap test_allowlist_covers_allowed \
    test_allowlist_pipes_builtins_comments test_allowlist_bad_settings \
    test_allowlist_token_needs_absolute_rule test_allowlist_home_token_expands
