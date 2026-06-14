#!/usr/bin/env bash
# x CLI surface: help, usage, and argument errors.

test_x_help() {
    cap "$X" help
    assert_exit 0 "$RC" "x help: exit 0"
    assert_contains "$OUT" "usage:" "x help: prints usage"
    cap "$X"
    assert_exit 2 "$RC" "x (no subcommand): exit 2"
}

test_x_arg_errors() {
    roots; AR="$GOOD"
    cap runx install --bogus
    assert_exit 2 "$RC" "x install --bogus: unknown flag exits 2"
    assert_contains "$OUT" "unknown flag" "x: names the unknown flag"
    cap runx install nosuchitem
    assert_exit 2 "$RC" "x install nosuchitem: unknown item exits 2"
    assert_contains "$OUT" "unknown item" "x: names the unknown item"
}

register test_x_help test_x_arg_errors
