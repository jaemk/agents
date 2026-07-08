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
                   (default: <repo>/resources/allowlist.json)
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
        # `${HOME}` in a committed rule expands to the real home so the generic
        # allowlist stays machine-independent. A leading `~` is left literal on
        # purpose: Claude does not expand it, so a tilde rule genuinely does NOT
        # cover an absolute-path command (see the token-expansion note below).
        inner = inner.replace("${HOME}", str(Path.home()))
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


def glob_base(rule):
    """The literal directory prefix of a trailing-path-glob rule, else None.

    Maps `<dir>/**/*`, `<dir>/**`, `<dir>/*`, and `<dir>**` to `<dir>/`, so any
    command under that directory is matched. Longer suffixes are checked first.
    """
    for suffix in ("/**/*", "/**", "/*", "**"):
        if rule.endswith(suffix):
            base = rule[: -len(suffix)]
            return base if base.endswith("/") else base + "/"
    return None


def is_covered(cmd, prefixes):
    head = cmd.split()[0] if cmd.split() else ""
    if head in SAFE_BUILTINS:
        return True
    for p in prefixes:
        # A path-glob rule (e.g. ~/.mind/store/**, /home/u/.mind/store/**/*) is a
        # directory-prefix match: strip the trailing glob and match under the dir.
        base = glob_base(p)
        if base is not None:
            if cmd.startswith(base):
                return True
        elif cmd == p or cmd.startswith(p + " "):
            return True
    return False


# mind reference tokens resolve, at install, to ABSOLUTE paths under the user's
# ~/.mind/store (mind expands them to the real home path, not a literal ~). The
# audit runs on source prose (tokens unexpanded), so it expands a leading token
# to that same absolute form Claude matches against at runtime. Claude matches
# Bash rules literally with no ~ expansion, so a tilde-form allow rule does NOT
# cover an absolute-path command - the allow rules must carry the absolute store
# path (e.g. Bash(/home/<user>/.mind/store/**/*)) for these to auto-approve.
STORE = str(Path.home() / ".mind" / "store")


def item_identity(path):
    """The (kind, name) of the item a file belongs to, for {{self}} expansion."""
    parts = Path(path).parts
    for dir_name, kind in (("skills", "skill"), ("tools", "tool")):
        if dir_name in parts:
            return kind, parts[parts.index(dir_name) + 1]
    for dir_name, kind in (("agents", "agent"), ("rules", "rule")):
        if dir_name in parts:
            return kind, Path(parts[parts.index(dir_name) + 1]).stem
    return None, None


def expand_token(cmd, kind, name):
    """Expand a leading {{self}}/{{tools:}}/{{path:}} token to its store path."""
    if cmd.startswith("{{self}}") and kind and name:
        return f"{STORE}/{kind}/{name}" + cmd[len("{{self}}") :]
    m = re.match(r"\{\{tools:([^}]+)\}\}", cmd)
    if m:
        return f"{STORE}/tool/{m.group(1).strip()}" + cmd[m.end() :]
    m = re.match(r"\{\{path:([^}]+)\}\}", cmd)
    if m:
        ref = m.group(1).strip()
        kn = ref.split(":", 1) if ":" in ref else [ref]
        return f"{STORE}/{'/'.join(p.strip() for p in kn)}" + cmd[m.end() :]
    return cmd


def iter_md_files(paths):
    for p in paths:
        p = Path(p)
        if p.is_dir():
            yield from sorted(p.rglob("*.md"))
        elif p.suffix == ".md":
            yield p


def main(argv):
    settings = REPO / "resources" / "allowlist.json"
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
        kind, name = item_identity(f)
        for cmd in extract_commands(f.read_text()):
            if not is_covered(expand_token(cmd, kind, name), prefixes):
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
