#!/usr/bin/env bash
# voice-paths.sh - resolve (and optionally create) the voice profile path.
#
# The profile lives under the XDG data dir, NOT under ~/.claude, so it can be granted
# read access in settings.json without allowing broad access to ~/.claude:
#
#     ${XDG_DATA_HOME:-$HOME/.local/share}/agents/voice/voice-profile.md
#
# Usage: voice-paths.sh [--ensure]
#   (no flag)  print the profile path.
#   --ensure   create the data dir and, if the profile is missing, seed it from the
#              template (voice-profile.template.md next to this script); then print the path.
#              Never overwrites an existing profile.
#
# Exit: 0 ok, 2 usage error.

set -euo pipefail

ensure=0
case "${1:-}" in
    --ensure)  ensure=1 ;;
    "")        ;;
    -h|--help) echo "usage: voice-paths.sh [--ensure]" >&2; exit 0 ;;
    *)         echo "usage: voice-paths.sh [--ensure]" >&2; exit 2 ;;
esac

dir="${XDG_DATA_HOME:-$HOME/.local/share}/agents/voice"
profile="$dir/voice-profile.md"

if [[ $ensure -eq 1 ]]; then
    mkdir -p "$dir"
    if [[ ! -f "$profile" ]]; then
        template="$(cd "$(dirname "$0")" && pwd)/voice-profile.template.md"
        if [[ -f "$template" ]]; then
            cp "$template" "$profile"
        else
            echo "# Voice profile" > "$profile"
        fi
    fi
fi

printf '%s\n' "$profile"
