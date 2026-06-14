#!/usr/bin/env bash
# mine-commits.sh - gather the user's commit messages across all git repos under a
# root, as a corpus for voice analysis. This is the non-reasoning data-gathering for
# the /voice skill; deriving the voice profile from the corpus is the agent's job.
#
# Usage: mine-commits.sh [ROOT] [--author NAME_OR_EMAIL] [--full]
#   ROOT      directory to scan for git repos (default: ~/dev)
#   --author  git author filter (default: the global git user.email, else user.name;
#             git matches it as a regex against "Name <email>"). Override to mine a
#             different identity. The flag requires a value; an explicit empty value
#             ("") falls back to auto-detection.
#   --full    include commit bodies (subject + body + a `---` separator per commit),
#             not just subject lines.
#
# Output: one record per commit on stdout (subject, or subject+body with --full);
#         a one-line summary on stderr. Exit 0 ok, 2 usage error.

set -euo pipefail

usage() { echo "usage: mine-commits.sh [ROOT] [--author NAME_OR_EMAIL] [--full]" >&2; }

root="$HOME/dev"
author=""
full=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --author)   [[ $# -ge 2 ]] || { usage; exit 2; }; author="$2"; shift 2 ;;
        --author=*) author="${1#--author=}"; shift ;;
        --full)     full=1; shift ;;
        -h|--help)  usage; exit 0 ;;
        --*)        usage; exit 2 ;;
        *)          root="$1"; shift ;;
    esac
done

[[ -d "$root" ]] || { echo "mine-commits.sh: not a directory: $root" >&2; exit 2; }

if [[ -z "$author" ]]; then
    author="$(git config user.email 2>/dev/null || true)"
    [[ -z "$author" ]] && author="$(git config user.name 2>/dev/null || true)"
fi

fmt='%s'
[[ $full -eq 1 ]] && fmt='%s%n%b%n---'

auth_args=()
[[ -n "$author" ]] && auth_args=(--author="$author")

repos=0 withc=0 total=0
while IFS= read -r gitdir; do
    repo="$(dirname "$gitdir")"
    repos=$((repos + 1))
    mapfile -t hashes < <(git -C "$repo" log --no-merges "${auth_args[@]}" --format='%H' 2>/dev/null || true)
    [[ ${#hashes[@]} -eq 0 ]] && continue
    withc=$((withc + 1))
    total=$((total + ${#hashes[@]}))
    git -C "$repo" log --no-merges "${auth_args[@]}" --format="$fmt" 2>/dev/null || true
done < <(find "$root" -type d -name node_modules -prune -o -type d -name .git -prune -print 2>/dev/null | sort)

echo "mine-commits: scanned $repos repo(s), $withc with commits by '${author:-ANY}', $total commit(s)" >&2
