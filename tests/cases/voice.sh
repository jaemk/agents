#!/usr/bin/env bash
# voice/resources/mine-commits.sh: gather the user's commit messages across repos.

VOICE_MINE="$REPO/skills/voice/resources/mine-commits.sh"
VOICE_PATHS="$REPO/skills/voice/resources/voice-paths.sh"

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

register test_voice_mine test_voice_mine_full test_voice_mine_default_author test_voice_mine_errors test_voice_paths

