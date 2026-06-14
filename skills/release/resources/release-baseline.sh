#!/usr/bin/env bash
# release-baseline.sh - gather the signals needed to pick a pre-release baseline.
#
# A release review must diff the whole accumulated surface since the last
# *actually released* version. Tags can lag reality, so this gathers the
# candidate signals - last tag, recent tags, changelog version headings, and
# recent commits - for the caller to reason over and pick a baseline. With
# --diff REF it prints the accumulated change stat from REF to HEAD.
#
# All git/changelog inspection for the release review lives here (not inlined in
# the skill prose) so it is one committed, tested, auto-approvable command rather
# than an ad-hoc string of shell probes.
#
# Usage:
#   release-baseline.sh [DIR]              print the baseline signals report
#   release-baseline.sh --diff REF [DIR]   print `git diff REF..HEAD --stat`
#
# Exit codes: 0 ok, 2 usage error, 3 not a git repository.

set -euo pipefail

mode="report"
ref=""
dir="."
while [[ $# -gt 0 ]]; do
    case "$1" in
        --diff)
            [[ $# -ge 2 ]] || { echo "usage: release-baseline.sh --diff REF [DIR]" >&2; exit 2; }
            mode="diff"; ref="$2"; shift 2 ;;
        --diff=*)
            mode="diff"; ref="${1#--diff=}"; shift ;;
        -h|--help)
            echo "usage: release-baseline.sh [DIR] | release-baseline.sh --diff REF [DIR]"; exit 0 ;;
        --*)
            echo "release-baseline.sh: unknown flag: $1" >&2; exit 2 ;;
        *)
            dir="$1"; shift ;;
    esac
done

[[ -d "$dir" ]] || { echo "release-baseline.sh: not a directory: $dir" >&2; exit 2; }
cd "$dir"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "release-baseline.sh: not a git repository: $dir" >&2; exit 3; }

if [[ "$mode" == "diff" ]]; then
    git diff "$ref..HEAD" --stat
    exit 0
fi

last_tag="$(git describe --tags --abbrev=0 2>/dev/null || true)"
tags="$(git tag --sort=-creatordate 2>/dev/null | head -20 || true)"
commits="$(git log --oneline -20 2>/dev/null || true)"
changelog=""
if [[ -f CHANGELOG.md ]]; then
    # Pull the bracketed version headings (## [X.Y.Z] / ## [Unreleased]), top first.
    changelog="$(grep -oE '^##[[:space:]]+\[[^]]+\]' CHANGELOG.md | sed -E 's/^##[[:space:]]+\[([^]]+)\]/\1/' | head -20 || true)"
fi

echo "== last released tag =="
[[ -n "$last_tag" ]] && echo "$last_tag" || echo "(none)"
echo
echo "== tags (newest first) =="
[[ -n "$tags" ]] && echo "$tags" || echo "(none)"
echo
echo "== changelog version headings (top first) =="
if [[ ! -f CHANGELOG.md ]]; then echo "(no CHANGELOG.md)"
elif [[ -n "$changelog" ]]; then echo "$changelog"
else echo "(no version headings found)"; fi
echo
echo "== recent commits =="
[[ -n "$commits" ]] && echo "$commits" || echo "(none)"
