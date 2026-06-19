#!/usr/bin/env bash
# voice-hook.sh - PreToolUse hook that injects the user's voice profile into context
# right before a commit message or prose/doc write is finalized.
#
# The voice directive in CLAUDE.md is advisory: the model must notice it applies AND
# remember to read an out-of-context file. This hook makes the profile *content* present
# at the moment of writing, so application stops depending on memory.
#
# Reads the PreToolUse hook payload (JSON) on stdin. When the pending tool call is a
# `git commit` (Bash) or a write to a prose/doc file (Write/Edit), it prints a JSON
# object whose hookSpecificOutput.additionalContext carries the full voice profile plus
# an instruction to apply it. For any other call it prints nothing and exits 0 (the tool
# proceeds unchanged). It never blocks - a missing profile or parse error is a silent
# no-op, never a wedged tool call.
#
# Usage: voice-hook.sh < payload.json
# Exit:  always 0 (advisory hook; never denies a tool).

set -uo pipefail

emit_nothing() { exit 0; }

input="$(cat)"
[[ -n "$input" ]] || emit_nothing

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" || emit_nothing

applies=0
case "$tool" in
    Bash)
        cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
        # Fire for a git commit that authors a message. Over-matching is harmless
        # (worst case: the profile is injected for a no-op commit); under-matching is
        # the failure we are fixing, so bias toward matching.
        if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])git([[:space:]]|$).*commit'; then
            applies=1
        fi
        ;;
    Write|Edit)
        path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
        case "$path" in
            *.md|*.markdown|*.mdx|*.txt|*.rst|*COMMIT_EDITMSG*|*PULLREQ_EDITMSG*|*MERGE_MSG*|*TAG_EDITMSG*)
                applies=1 ;;
        esac
        ;;
esac

[[ "$applies" -eq 1 ]] || emit_nothing

profile_path="$(cd "$(dirname "$0")" && pwd)/voice-paths.sh"
if [[ -x "$profile_path" ]]; then
    profile_file="$("$profile_path" 2>/dev/null)" || emit_nothing
else
    profile_file="${XDG_DATA_HOME:-$HOME/.local/share}/agents/voice/voice-profile.md"
fi

[[ -f "$profile_file" ]] || emit_nothing
profile="$(cat "$profile_file" 2>/dev/null)" || emit_nothing
[[ -n "$profile" ]] || emit_nothing

context="You are about to finalize writing for the user (a commit message, PR/issue text, or docs).
Apply the user's writing voice. This profile is the single source of truth - follow it before the tool call lands:

$profile"

jq -n --arg ctx "$context" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}'
