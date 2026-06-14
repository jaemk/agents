#!/usr/bin/env bash
# review: prompt assembly, stubbed claude invocation, modes, and errors (no network).

test_review_prompt() {
    roots; AR="$GOOD"
    cap runx review skill:sample --write-prompt
    assert_exit 0 "$RC" "review --write-prompt: exit 0"
    assert_contains "$OUT" "LOUD RULES" "review: includes loud rules from template"
    assert_contains "$OUT" "A sample skill fixture" "review: includes SKILL.md content"
    assert_contains "$OUT" "hello from sample" "review: includes resource content"
    assert_contains "$OUT" "--- skills/sample/SKILL.md ---" "review: includes file header"
    assert_contains "$OUT" "MODE: REVIEW-ONLY" "review: review-only mode header"
    cap runx review skill:sample --fix --write-prompt
    assert_contains "$OUT" "MODE: REVIEW-AND-FIX" "review --fix: fix-mode header"
}

test_review_stub() {
    roots; AR="$GOOD"
    cap runx review agent:sample
    assert_exit 0 "$RC" "review (stub): exit 0"
    assert_contains "$OUT" "CLAUDE_STUB called with: --model opus --print" "review: invokes claude with model+print"
    assert_contains "$OUT" "critiquing agent:sample" "review: prints progress before calling claude"
    cap runx review agent:sample --model sonnet
    assert_contains "$OUT" "--model sonnet --print" "review: honors --model override"
    cap runx review agent:sample --fix
    assert_exit 0 "$RC" "review --fix (stub): exit 0"
    assert_contains "$OUT" "--permission-mode acceptEdits" "review --fix: invokes claude with edit permission"
    assert_contains "$OUT" "reviewing AND fixing" "review --fix: progress notes fixing"
}

test_review_errors() {
    roots; AR="$GOOD"
    cap runx review
    assert_exit 2 "$RC" "review: no name -> exit 2"
    assert_contains "$OUT" "needs exactly one item" "review: clear error when no item named"
    cap runx review agent:sample skill:sample
    assert_exit 2 "$RC" "review: more than one item -> exit 2"
}

register test_review_prompt test_review_stub test_review_errors
