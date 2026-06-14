#!/usr/bin/env python3
"""audit-shell-allowlist.py - verify every shell invocation in agent/skill prose is allowlisted.

Spawned sub-agents that hit a Bash command needing interactive approval can stall a
handoff (the orchestrator waits forever). To prevent that, every command an agent or
skill directs a sub-agent to run must be auto-approvable: a committed resource script
(or a plain git/jq) covered by a `permissions.allow` rule in the settings backup.

This scans the ```bash fenced blocks in the given agent/skill markdown files and checks
each command against the allow rules. Anything not covered is reported as a violation.

Usage:
  audit-shell-allowlist.py [--settings PATH] [PATH ...]

  --settings PATH  settings JSON whose .permissions.allow holds the Bash(...) rules
                   (default: <repo>/config/settings.json)
  PATH ...         markdown files or dirs to scan (default: <repo>/agents <repo>/skills)

Exit codes: 0 all covered, 1 one or more uncovered commands, 2 usage/IO error.
"""
import json
import re
import sys
from pathlib import Path

# Shell builtins / no-ops that never trigger a permission prompt.
SAFE_BUILTINS = {"printf", "echo", "cd", "true", "false", ":", "test", "[", "[["}

REPO = Path(__file__).resolve().parent.parent


def load_allow_prefixes(settings_path):
    """Return the list of Bash command prefixes from a settings file's allow rules."""
    data = json.loads(Path(settings_path).read_text())
    rules = data.get("permissions", {}).get("allow", [])
    prefixes = []
    for rule in rules:
        m = re.fullmatch(r"Bash\((.*)\)", rule)
        if not m:
            continue
        inner = m.group(1)
        # `cmd:*` means "cmd with any args"; a bare `cmd` is an exact match.
        inner = inner[:-2] if inner.endswith(":*") else inner
        prefixes.append(inner)
    return prefixes


def extract_commands(md_text):
    """Yield each command invocation found in ```bash fenced blocks of md_text.

    Line continuations (trailing backslash) are joined, then logical lines are split
    on pipes / && / ; into individual command segments.
    """
    in_block = False
    logical = ""
    for raw in md_text.splitlines():
        stripped = raw.strip()
        if not in_block:
            if stripped == "```bash":
                in_block = True
            continue
        if stripped == "```":
            in_block = False
            continue
        # Accumulate backslash-continued lines into one logical line.
        if raw.rstrip().endswith("\\"):
            logical += raw.rstrip()[:-1] + " "
            continue
        logical += raw
        line = logical
        logical = ""
        # Drop a trailing inline comment (commands here carry no ' #' in their args).
        if " #" in line:
            line = line[: line.index(" #")]
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        for seg in re.split(r"\|\||\||&&|;", line):
            seg = seg.strip()
            if seg:
                yield seg


def is_covered(cmd, prefixes):
    head = cmd.split()[0] if cmd.split() else ""
    if head in SAFE_BUILTINS:
        return True
    for p in prefixes:
        if cmd == p or cmd.startswith(p + " "):
            return True
    return False


def iter_md_files(paths):
    for p in paths:
        p = Path(p)
        if p.is_dir():
            yield from sorted(p.rglob("*.md"))
        elif p.suffix == ".md":
            yield p


def main(argv):
    settings = REPO / "config" / "settings.json"
    scan = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--settings":
            if i + 1 >= len(argv):
                print("usage: audit-shell-allowlist.py [--settings PATH] [PATH ...]", file=sys.stderr)
                return 2
            settings = argv[i + 1]
            i += 2
        else:
            scan.append(a)
            i += 1
    if not scan:
        scan = [str(REPO / "agents"), str(REPO / "skills")]

    try:
        prefixes = load_allow_prefixes(settings)
    except (OSError, ValueError) as e:
        print(f"audit-shell-allowlist.py: cannot read settings {settings}: {e}", file=sys.stderr)
        return 2

    violations = []
    for f in iter_md_files(scan):
        for cmd in extract_commands(f.read_text()):
            if not is_covered(cmd, prefixes):
                rel = f.relative_to(REPO) if str(f).startswith(str(REPO)) else f
                violations.append((str(rel), cmd))

    if violations:
        print(f"audit-shell-allowlist: {len(violations)} un-allowlisted command(s):", file=sys.stderr)
        for rel, cmd in violations:
            print(f"  {rel}: {cmd}", file=sys.stderr)
        print("Add a committed-script invocation + a Bash(...) allow rule, or route via detect-project.sh.", file=sys.stderr)
        return 1

    print("audit-shell-allowlist: OK (every bash-block command is allowlisted)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
