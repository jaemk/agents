#!/usr/bin/env bash
# voice-hook.sh - PreToolUse hook that reminds the model to apply the user's voice rules
# right before a commit message or prose/doc write is finalized.
#
# The rules themselves are always in context: ~/.claude/CLAUDE.md imports voice-rules.md,
# and imports are reloaded after a compaction. This hook only brings them to the front at
# the moment of writing, with a one-line reminder naming the rules file, so it does not
# repeat the rules on every matching call.
#
# Reads the PreToolUse hook payload (JSON) on stdin. When the pending tool call is a
# `git commit` (Bash) or a write to a prose/doc file (Write/Edit), it prints a JSON
# object whose hookSpecificOutput.additionalContext carries the reminder. For any other
# call it prints nothing and exits 0 (the tool proceeds unchanged). All matched calls use
# additionalContext (advisory) so the tool always proceeds; decision:block was removed
# because it re-fired on every retry with no way to pass through.
# A missing rules file (and profile) or parse error is a silent no-op, never a wedged
# tool call.
#
# Usage: voice-hook.sh < payload.json
# Exit:  always 0.

set -uo pipefail

emit_nothing() { exit 0; }

input="$(cat)"
[[ -n "$input" ]] || emit_nothing

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" || emit_nothing

applies=0
cmd=""

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

# The rules are already in context (imported from ~/.claude/CLAUDE.md), so this is a
# one-line reminder that names the file rather than a copy of it. Fall back to the
# profile for a setup that has not split the rules out yet.
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/agents/voice"
paths="$(cd "$(dirname "$0")" && pwd)/voice-paths.sh"
if [[ -x "$paths" ]]; then
    rules_file="$("$paths" --rules 2>/dev/null)" || emit_nothing
    profile_file="$("$paths" 2>/dev/null)" || emit_nothing
else
    rules_file="$data_dir/voice-rules.md"
    profile_file="$data_dir/voice-profile.md"
fi

target=""
if [[ -s "$rules_file" ]]; then target="$rules_file"
elif [[ -s "$profile_file" ]]; then target="$profile_file"
else emit_nothing; fi

context="Writing for the user: apply the voice rules in $target (read it if it is not already in context)."
jq -n --arg ctx "$context" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}'
