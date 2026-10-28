#!/usr/bin/env bash
# voice-paths.sh - resolve (and optionally create) the voice profile files.
#
# They live under the XDG data dir, NOT under ~/.claude, so they can be granted read
# access in settings.json without allowing broad access to ~/.claude:
#
#     ${XDG_DATA_HOME:-$HOME/.local/share}/agents/voice/voice-rules.md
#     ${XDG_DATA_HOME:-$HOME/.local/share}/agents/voice/voice-profile.md
#
# voice-rules.md holds the distilled rules: the part applied to every piece of writing,
# imported into context from ~/.claude/CLAUDE.md. voice-profile.md holds the evidence
# behind them (mined patterns, training examples, feedback log), read by /voice only.
#
# Usage: voice-paths.sh [--rules] [--ensure]
#   (no flag)  print the profile path.
#   --rules    print the rules path instead.
#   --ensure   create the data dir and seed any missing file from its template
#              (voice-profile.template.md / voice-rules.template.md next to this
#              script), then print the path. Never overwrites an existing file.
#
# Exit: 0 ok, 2 usage error.

set -euo pipefail

usage() { echo "usage: voice-paths.sh [--rules] [--ensure]" >&2; }

ensure=0
rules=0
for arg in "$@"; do
    case "$arg" in
        --ensure)  ensure=1 ;;
        --rules)   rules=1 ;;
        -h|--help) usage; exit 0 ;;
        *)         usage; exit 2 ;;
    esac
done

here="$(cd "$(dirname "$0")" && pwd)"
dir="${XDG_DATA_HOME:-$HOME/.local/share}/agents/voice"
profile="$dir/voice-profile.md"
rules_file="$dir/voice-rules.md"

seed() { # <file> <template> <fallback heading>
    [[ -f "$1" ]] && return 0
    if [[ -f "$2" ]]; then cp "$2" "$1"; else echo "$3" > "$1"; fi
}

if [[ $ensure -eq 1 ]]; then
    mkdir -p "$dir"
    seed "$profile" "$here/voice-profile.template.md" "# Voice profile"
    seed "$rules_file" "$here/voice-rules.template.md" "# Voice rules"
fi

if [[ $rules -eq 1 ]]; then
    printf '%s\n' "$rules_file"
else
    printf '%s\n' "$profile"
fi
