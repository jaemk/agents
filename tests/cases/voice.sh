#!/usr/bin/env bash
# voice/resources/mine-commits.sh: gather the user's commit messages across repos.

VOICE_MINE="$REPO/skills/voice/resources/mine-commits.sh"
VOICE_PATHS="$REPO/skills/voice/resources/voice-paths.sh"
VOICE_HOOK="$REPO/skills/voice/resources/voice-hook.sh"

# Seed a profile under a temp XDG_DATA_HOME (voice-hook resolves it via voice-paths),
# then feed PAYLOAD on stdin to the hook. Sets OUT/RC like cap().
voice_hook() { # <xdg> <payload>
    OUT="$(printf '%s' "$2" | XDG_DATA_HOME="$1" "$VOICE_HOOK" 2>&1)"; RC=$?
}
seed_profile() { # <xdg>
    XDG_DATA_HOME="$1" "$VOICE_PATHS" --ensure >/dev/null
}

test_voice_mine() {
    local root; root="$(mktemp_d)"
    mkdir -p "$root/a" "$root/b" "$root/notrepo"
    git -C "$root/a" init -q
    git -C "$root/b" init -q
    git_commit_as "$root/a" Me me@x.test "add widget"
    git_commit_as "$root/a" Me me@x.test "fix the bug"
    git_commit_as "$root/b" Me me@x.test "tidy docs" "a longer body line"
    git_commit_as "$root/b" Other other@x.test "drop in change"

    cap "$VOICE_MINE" "$root" --author me@x.test
    assert_exit 0 "$RC" "voice mine: exit 0"
    assert_contains "$OUT" "add widget" "voice mine: includes my subject"
    assert_contains "$OUT" "tidy docs" "voice mine: spans multiple repos"
    assert_not_contains "$OUT" "drop in change" "voice mine: filters out other authors"
    assert_contains "$OUT" "2 with commits" "voice mine: summary counts repos with my commits"
    assert_contains "$OUT" "3 commit(s)" "voice mine: summary counts total commits"
}

test_voice_mine_full() {
    local root; root="$(mktemp_d)"
    mkdir -p "$root/a"
    git -C "$root/a" init -q
    git_commit_as "$root/a" Me me@x.test "tidy docs" "a longer body line"
    cap "$VOICE_MINE" "$root" --author me@x.test --full
    assert_contains "$OUT" "a longer body line" "voice mine --full: includes commit bodies"
}

test_voice_mine_errors() {
    cap "$VOICE_MINE" --bogus
    assert_exit 2 "$RC" "voice mine: unknown flag -> exit 2"
    cap "$VOICE_MINE" /no/such/dir/here
    assert_exit 2 "$RC" "voice mine: missing root -> exit 2"
}

test_voice_mine_default_author() {
    # No --author: the script must auto-detect the identity from git config
    # (user.email, else user.name). Pin global/system config to temp files and run
    # from a non-repo dir so no local repo config leaks in - fully hermetic.
    local root cfg; root="$(mktemp_d)"; cfg="$(mktemp_d)/gitconfig"
    mkdir -p "$root/a"
    git -C "$root/a" init -q
    git_commit_as "$root/a" Me me@x.test "mine subject"
    git_commit_as "$root/a" Other other@x.test "other subject"
    printf '[user]\n\temail = me@x.test\n' > "$cfg"
    OUT="$(cd "$root" && GIT_CONFIG_GLOBAL="$cfg" GIT_CONFIG_SYSTEM=/dev/null "$VOICE_MINE" "$root" 2>&1)"; RC=$?
    assert_exit 0 "$RC" "voice mine default author: exit 0"
    assert_contains "$OUT" "mine subject" "voice mine default author: includes auto-detected identity's commit"
    assert_not_contains "$OUT" "other subject" "voice mine default author: filters out other authors"
    assert_contains "$OUT" "by 'me@x.test'" "voice mine default author: summary names the auto-detected identity"
}

test_voice_paths() {
    local xdg; xdg="$(mktemp_d)"
    local p; p="$(XDG_DATA_HOME="$xdg" "$VOICE_PATHS")"
    assert_eq "$xdg/agents/voice/voice-profile.md" "$p" "voice-paths: resolves under XDG_DATA_HOME"
    assert_no_path "$p" "voice-paths: does not create the profile without --ensure"
    p="$(XDG_DATA_HOME="$xdg" "$VOICE_PATHS" --ensure)"
    assert_file "$p" "voice-paths --ensure: seeds the profile"
    assert_contains "$(cat "$p")" "Voice profile" "voice-paths --ensure: seeded from the template"
    echo "MY LIVE EDITS" >> "$p"
    XDG_DATA_HOME="$xdg" "$VOICE_PATHS" --ensure >/dev/null
    assert_contains "$(cat "$p")" "MY LIVE EDITS" "voice-paths --ensure: never overwrites an existing profile"
    cap "$VOICE_PATHS" --bogus
    assert_exit 2 "$RC" "voice-paths: unknown flag -> exit 2"
}

# The rules live in their own file (the part CLAUDE.md imports); --ensure seeds it next
# to the profile and never overwrites it.
test_voice_paths_rules() {
    local xdg; xdg="$(mktemp_d)"
    local r; r="$(XDG_DATA_HOME="$xdg" "$VOICE_PATHS" --rules)"
    assert_eq "$xdg/agents/voice/voice-rules.md" "$r" "voice-paths --rules: resolves the rules file"
    assert_no_path "$r" "voice-paths --rules: does not create it without --ensure"
    r="$(XDG_DATA_HOME="$xdg" "$VOICE_PATHS" --rules --ensure)"
    assert_file "$r" "voice-paths --rules --ensure: seeds the rules file"
    assert_contains "$(cat "$r")" "Voice rules" "voice-paths --ensure: rules seeded from their template"
    assert_file "$xdg/agents/voice/voice-profile.md" "voice-paths --ensure: seeds the profile too"
    echo "MY RULE" >> "$r"
    XDG_DATA_HOME="$xdg" "$VOICE_PATHS" --ensure >/dev/null
    assert_contains "$(cat "$r")" "MY RULE" "voice-paths --ensure: never overwrites the rules file"
}

# The hook is a one-line reminder that names the rules file, not a copy of the rules.
test_voice_hook_commit() {
    local xdg; xdg="$(mktemp_d)"; seed_profile "$xdg"
    printf 'RULES-SENTINEL-XYZ\n' >> "$xdg/agents/voice/voice-rules.md"
    voice_hook "$xdg" '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"x\""}}'
    assert_exit 0 "$RC" "voice hook: git commit -> exit 0"
    assert_contains "$OUT" '"hookEventName": "PreToolUse"' "voice hook: emits PreToolUse output"
    assert_contains "$OUT" "$xdg/agents/voice/voice-rules.md" "voice hook: names the rules file"
    assert_not_contains "$OUT" "RULES-SENTINEL-XYZ" "voice hook: does not repeat the rules' content"
}

test_voice_hook_prose_write() {
    local xdg; xdg="$(mktemp_d)"; seed_profile "$xdg"
    voice_hook "$xdg" '{"tool_name":"Write","tool_input":{"file_path":"/tmp/README.md"}}'
    assert_contains "$OUT" "voice-rules.md" "voice hook: fires on a prose/doc write"
}

# A setup with only the older single-file profile still gets a reminder, naming it.
test_voice_hook_profile_fallback() {
    local xdg; xdg="$(mktemp_d)"; mkdir -p "$xdg/agents/voice"
    printf '# Voice profile\n' > "$xdg/agents/voice/voice-profile.md"
    voice_hook "$xdg" '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}'
    assert_contains "$OUT" "voice-profile.md" "voice hook: falls back to the profile without a rules file"
}

test_voice_hook_skips_non_writing() {
    local xdg; xdg="$(mktemp_d)"; seed_profile "$xdg"
    # Non-commit bash and code-file writes must be silent no-ops so the hook never
    # taxes unrelated tool calls.
    voice_hook "$xdg" '{"tool_name":"Bash","tool_input":{"command":"git status"}}'
    assert_exit 0 "$RC" "voice hook: non-commit bash -> exit 0"
    assert_eq "" "$OUT" "voice hook: non-commit bash emits nothing"
    voice_hook "$xdg" '{"tool_name":"Write","tool_input":{"file_path":"/tmp/main.rs"}}'
    assert_eq "" "$OUT" "voice hook: code-file write emits nothing"
}

test_voice_hook_degrades_safely() {
    # Missing profile and empty stdin are no-ops, never a wedged tool call.
    local xdg; xdg="$(mktemp_d)"
    voice_hook "$xdg" '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}'
    assert_exit 0 "$RC" "voice hook: missing profile -> exit 0"
    assert_eq "" "$OUT" "voice hook: missing profile emits nothing"
    voice_hook "$xdg" ''
    assert_exit 0 "$RC" "voice hook: empty stdin -> exit 0"
    assert_eq "" "$OUT" "voice hook: empty stdin emits nothing"
}

register test_voice_mine test_voice_mine_full test_voice_mine_default_author test_voice_mine_errors test_voice_paths \
    test_voice_paths_rules test_voice_hook_commit test_voice_hook_prose_write test_voice_hook_profile_fallback \
    test_voice_hook_skips_non_writing test_voice_hook_degrades_safely

