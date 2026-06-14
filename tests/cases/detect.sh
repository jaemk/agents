#!/usr/bin/env bash
# detect-project.sh: per-ecosystem detection and command mapping.

test_detect_rust() {
    local d; d="$(mktemp_d)"; : > "$d/Cargo.toml"
    cap "$DET" "$d"
    assert_exit 0 "$RC" "detect rust: exit 0"
    assert_contains "$OUT" "type=rust" "detect rust: type"
    assert_contains "$OUT" "build=cargo build" "detect rust: build command"
    assert_contains "$OUT" "lint=cargo clippy" "detect rust: lint command"
    assert_eq "rust" "$("$DET" "$d" --what type)" "detect rust: --what type bare value"
}

test_detect_node() {
    local d; d="$(mktemp_d)"; printf '{"scripts":{"build":"webpack"}}' > "$d/package.json"
    cap "$DET" "$d"
    assert_contains "$OUT" "type=node" "detect node: type"
    assert_contains "$OUT" "build=npm run build" "detect node: build script detected from package.json"
    local d2; d2="$(mktemp_d)"; printf '{}' > "$d2/package.json"
    assert_eq "" "$("$DET" "$d2" --what build)" "detect node: no scripts -> empty build command"
}

test_detect_python() {
    local d; d="$(mktemp_d)"; : > "$d/pyproject.toml"
    cap "$DET" "$d"
    assert_contains "$OUT" "type=python" "detect python: type"
    assert_contains "$OUT" "version_files=pyproject.toml" "detect python: version file"
}

test_detect_go() {
    local d; d="$(mktemp_d)"; : > "$d/go.mod"
    cap "$DET" "$d"
    assert_contains "$OUT" "type=go" "detect go: type"
    assert_contains "$OUT" "test=go test ./..." "detect go: test command"
}

test_detect_ci_and_walkup() {
    local d; d="$(mktemp_d)"; : > "$d/Cargo.toml"; printf 'ci:\n\techo hi\n' > "$d/Makefile"
    assert_eq "make ci" "$("$DET" "$d" --what ci)" "detect: Makefile ci target -> make ci"
    mkdir -p "$d/sub/deep"
    assert_eq "rust" "$("$DET" "$d/sub/deep" --what type)" "detect: walks up to the nearest marker"
}

test_detect_unknown() {
    local d; d="$(mktemp_d)"
    cap "$DET" "$d"
    assert_exit 3 "$RC" "detect unknown: exit 3"
    assert_contains "$OUT" "unknown" "detect unknown: reports unknown"
}

register test_detect_rust test_detect_node test_detect_python test_detect_go test_detect_ci_and_walkup test_detect_unknown
