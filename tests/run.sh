#!/usr/bin/env bash
# Hermetic test harness entrypoint.
#
# Sources the infra (lib.sh) and every case file under cases/, then runs all
# registered tests - or only those whose name contains the optional filter argument:
#
#   tests/run.sh           run everything
#   tests/run.sh pr        run only tests whose name contains "pr"
#   tests/run.sh detect    run only the detector tests
#
# No network; all state lives in temp dirs, so the real ~/.agents and ~/.claude are
# never touched. Exits non-zero if any assertion fails.
#
# To add tests: create or edit a cases/<area>.sh file with `test_*` functions and a
# trailing `register test_a test_b ...`, and add <area> to the CASE_ORDER list below.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/lib.sh
source "$HERE/lib.sh"

CASE_ORDER=(install status check review config detect pr bump baseline shard voice allowlist xcli smoke spec)
for c in "${CASE_ORDER[@]}"; do
    # shellcheck disable=SC1090
    source "$HERE/cases/$c.sh"
done

run_cases "${1:-}"
