#!/usr/bin/env bash
# release/resources/bump-version.sh: version bump across detected version files.

test_bump_rust() {
    local d; d="$(mktemp_d)"
    printf '[package]\nname = "demo"\nversion = "0.1.0"\n\n[dependencies]\nfoo = "1.2.3"\n' > "$d/Cargo.toml"
    cap "$BUMP" 0.2.0 "$d"
    assert_exit 0 "$RC" "bump rust: exit 0"
    assert_contains "$OUT" "bumped Cargo.toml -> 0.2.0" "bump rust: reports the change"
    local c; c="$(cat "$d/Cargo.toml")"
    assert_contains "$c" 'version = "0.2.0"' "bump rust: package version updated"
    assert_not_contains "$c" 'version = "0.1.0"' "bump rust: old version gone"
    assert_contains "$c" 'foo = "1.2.3"' "bump rust: dependency version untouched"
}

test_bump_node() {
    local d; d="$(mktemp_d)"; printf '{"name":"demo","version":"0.1.0"}\n' > "$d/package.json"
    cap "$BUMP" 0.2.0 "$d"
    assert_exit 0 "$RC" "bump node: exit 0"
    assert_eq "0.2.0" "$(jq -r .version "$d/package.json")" "bump node: version updated"
}

test_bump_pyproject() {
    local d; d="$(mktemp_d)"
    printf '[project]\nname = "demo"\nversion = "0.1.0"\n\n[tool.black]\nline-length = 88\n' > "$d/pyproject.toml"
    cap "$BUMP" 0.2.0 "$d"
    assert_exit 0 "$RC" "bump pyproject [project]: exit 0"
    assert_contains "$(cat "$d/pyproject.toml")" 'version = "0.2.0"' "bump pyproject: [project] version updated"
}

test_bump_poetry() {
    local d; d="$(mktemp_d)"
    printf '[tool.poetry]\nname = "demo"\nversion = "0.1.0"\n' > "$d/pyproject.toml"
    cap "$BUMP" 0.2.0 "$d"
    assert_exit 0 "$RC" "bump pyproject [tool.poetry]: exit 0"
    assert_contains "$(cat "$d/pyproject.toml")" 'version = "0.2.0"' "bump poetry: version updated"
}

test_bump_unsupported() {
    local d; d="$(mktemp_d)"; : > "$d/setup.py"
    cap "$BUMP" 0.2.0 "$d"
    assert_exit 3 "$RC" "bump setup.py: unsupported file -> exit 3"
    assert_contains "$OUT" "unsupported version file" "bump: names the unsupported file"
}

test_bump_usage() {
    cap "$BUMP"
    assert_exit 2 "$RC" "bump: no arg -> exit 2"
    assert_contains "$OUT" "usage:" "bump: prints usage on misuse"
    local d; d="$(mktemp_d)"
    cap "$BUMP" 0.2.0 "$d"
    assert_exit 3 "$RC" "bump: no version files detected -> exit 3"
}

register test_bump_rust test_bump_node test_bump_pyproject test_bump_poetry test_bump_unsupported test_bump_usage
