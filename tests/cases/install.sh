#!/usr/bin/env bash
# install / uninstall behavior.

test_install_fresh() {
    roots; AR="$GOOD"
    cap runx install
    assert_exit 0 "$RC" "install fresh: exit 0"
    assert_file "$AH/agents/sample.md"                 "install: agent copied to AGENTS_HOME"
    assert_file "$AH/skills/sample/SKILL.md"           "install: skill SKILL.md copied"
    assert_file "$AH/skills/sample/resources/hello.sh" "install: skill resource copied"
    assert_exec "$AH/skills/sample/resources/hello.sh" "install: resource keeps +x"
    assert_file "$AH/resources/noop.sh"                "install: shared resource copied"
    assert_symlink_to "$CH/agents/sample.md" "$AH/agents/sample.md" "install: agent symlinked into CLAUDE_HOME"
    assert_symlink_to "$CH/skills/sample"    "$AH/skills/sample"    "install: skill symlinked into CLAUDE_HOME"
    assert_no_path "$CH/resources" "install: shared resources are NOT symlinked"
    assert_file "$AH/manifest.json" "install: manifest written"
    assert_ne "" "$(jq -r '.items["skill:sample"].hash' "$AH/manifest.json")" "install: manifest records skill hash"
    cap runx install
    assert_exit 0 "$RC" "install idempotent: exit 0"
    assert_contains "$OUT" "up-to-date" "install idempotent: reports up-to-date"
}

test_install_upgrade() {
    local ar; ar="$(mktemp_d)"; cp -Rp "$GOOD/." "$ar/"
    roots; AR="$ar"
    cap runx install
    assert_exit 0 "$RC" "upgrade: initial install exit 0"
    echo 'echo more' >> "$ar/skills/sample/resources/hello.sh"
    cap runx status --json
    assert_eq "needs-upgrade" "$(state_of "$OUT" "skill:sample")" "upgrade: resource edit -> needs-upgrade"
    cap runx install
    assert_exit 0 "$RC" "upgrade: reinstall exit 0"
    cap runx status --json
    assert_eq "up-to-date" "$(state_of "$OUT" "skill:sample")" "upgrade: after reinstall up-to-date"
}

test_uninstall() {
    roots; AR="$GOOD"
    cap runx install
    cap runx uninstall
    assert_exit 0 "$RC" "uninstall: exit 0"
    assert_no_path "$CH/skills/sample"    "uninstall: skill symlink removed"
    assert_no_path "$CH/agents/sample.md" "uninstall: agent symlink removed"
    assert_no_path "$AH/skills/sample"    "uninstall: skill payload removed"
    assert_eq "gone" "$(jq -r '.items["skill:sample"] // "gone"' "$AH/manifest.json")" "uninstall: manifest entry removed"
    cap runx uninstall
    assert_exit 0 "$RC" "uninstall idempotent: exit 0"
}

test_uninstall_preserves_real() {
    roots; AR="$GOOD"
    mkdir -p "$CH/agents"; echo "real user file" > "$CH/agents/sample.md"
    cap runx uninstall agent:sample
    assert_file "$CH/agents/sample.md" "uninstall: real (non-symlink) file preserved"
    assert_eq "real user file" "$(cat "$CH/agents/sample.md")" "uninstall: real file content intact"
}

test_install_refuse_clobber() {
    roots; AR="$GOOD"
    mkdir -p "$CH/agents"; echo "real" > "$CH/agents/sample.md"
    cap runx install agent:sample
    assert_exit 1 "$RC" "clobber: install without --force exits 1"
    assert_contains "$OUT" "refusing to clobber" "clobber: reports refusal"
    assert_not_symlink "$CH/agents/sample.md" "clobber: real file not replaced"
    cap runx install agent:sample --force
    assert_exit 0 "$RC" "clobber: --force exits 0"
    assert_symlink_to "$CH/agents/sample.md" "$AH/agents/sample.md" "clobber: --force installs symlink"
}

register test_install_fresh test_install_upgrade test_uninstall test_uninstall_preserves_real test_install_refuse_clobber
