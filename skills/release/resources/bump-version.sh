#!/usr/bin/env bash
# bump-version.sh - set the package version in a project's version file(s).
#
# Language-agnostic: the version files are obtained from the shared detector
# (resources/detect-project.sh), so this works for Cargo.toml, package.json, and
# pyproject.toml without hardcoding a layout. The version is updated only in the
# package's own version field, not in dependency version requirements.
#
# Usage: bump-version.sh NEW_VERSION [DIR]   (DIR default: .)
#
# Output: one line per file changed: "bumped <file> -> <NEW_VERSION>".
# Exit codes: 0 ok, 2 usage error, 3 no version files detected.

set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
    echo "usage: bump-version.sh NEW_VERSION [DIR]" >&2
    exit 2
fi
new="$1"
dir="${2:-.}"
[[ -d "$dir" ]] || { echo "bump-version.sh: not a directory: $dir" >&2; exit 2; }

self_dir="$(cd "$(dirname "$0")" && pwd)"          # skills/release/resources
det="$(cd "$self_dir/../../.." && pwd)/resources/detect-project.sh"
[[ -x "$det" ]] || { echo "bump-version.sh: detector not found at $det" >&2; exit 3; }

vfiles="$("$det" "$dir" --what version_files || true)"
[[ -n "$vfiles" ]] || { echo "bump-version.sh: no version files detected in $dir" >&2; exit 3; }

bump_toml() {
    # Replace the version line inside the package table only ([package] for Cargo,
    # [project] or [tool.poetry] for pyproject), leaving dependency versions alone.
    local f="$1"
    awk -v ver="$new" '
        /^\[/ { table=$0 }
        {
            if ($0 ~ /^version[ \t]*=/ && (table=="[package]" || table=="[project]" || table=="[tool.poetry]")) {
                print "version = \"" ver "\""
                next
            }
            print
        }
    ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

bump_json() {
    local f="$1"
    python3 - "$f" "$new" <<'PY'
import json, sys
path, ver = sys.argv[1], sys.argv[2]
with open(path) as fh:
    data = json.load(fh)
data["version"] = ver
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY
}

changed=0
for vf in $vfiles; do
    path="$dir/$vf"
    [[ -f "$path" ]] || { echo "bump-version.sh: version file missing: $path" >&2; continue; }
    case "$vf" in
        *.json) bump_json "$path" ;;
        *.toml) bump_toml "$path" ;;
        *)      echo "bump-version.sh: unsupported version file: $vf" >&2; continue ;;
    esac
    echo "bumped $vf -> $new"
    changed=1
done

[[ $changed -eq 1 ]] || { echo "bump-version.sh: nothing changed" >&2; exit 3; }
