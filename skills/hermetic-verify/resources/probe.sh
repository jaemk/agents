#!/usr/bin/env bash
#
# Hermetic probe runner - template from the hermetic-verify skill.
#
# Purpose: run the project's binary/app against a fixture in a throwaway, fully
# isolated environment so you can capture real output WITHOUT a permission prompt
# per run. The agent-facing command is always `bash scripts/probe.sh ...`, which
# is statically allowlistable once (.claude/settings.json:
# "Bash(bash scripts/probe.sh *)"). ALL dynamism - temp dirs, env vars, fixtures
# - lives INSIDE this script, so no invocation needs a unique path or an env-var
# prefix that would force a fresh approval.
#
# PREFER A TEST. If the behavior can be asserted, encode it in the project's test
# suite instead of probing. Use this only to capture output or explore, then
# promote what you learn into a test.
#
# ADAPT THE TWO MARKED SECTIONS for this project, then delete this notice and the
# `exit 3` guard below. Use `<detect-project> . --run build` for the build step;
# the run/binary invocation is project-specific (point it at the build's output).
#
# Usage: scripts/probe.sh <args...>
# Env:   KEEP=1   keep the temp workdir and print its path instead of deleting it.
#
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

# --- BUILD (adapt) ---------------------------------------------------------
# Build once. Most build tools serialize on their own locks, so concurrent probes
# are safe. Replace with the project's build command (see
# `<detect-project> . --run build`), or delete if none.
echo "probe.sh template not adapted: fill in BUILD and RUN" >&2
exit 3
# ---------------------------------------------------------------------------

# A unique throwaway workdir. mktemp keeps concurrent probes from colliding; the
# dynamism is contained here, not in the caller's command.
work=$(mktemp -d "${TMPDIR:-/tmp}/probe.XXXXXX")
cleanup() {
  if [ -n "${KEEP:-}" ]; then
    echo "probe: kept $work" >&2
  else
    rm -rf "$work"
  fi
}
trap cleanup EXIT

# --- ISOLATION + RUN (adapt) -----------------------------------------------
# Export every isolation env var HERE so the caller never needs a prefix, build
# any fixture under "$work", then run the binary/app passing "$@". Example:
#
#   export APP_HOME="$work/home"; mkdir -p "$APP_HOME"
#   "$repo_root"/path/to/built-binary "$@"
# ---------------------------------------------------------------------------
