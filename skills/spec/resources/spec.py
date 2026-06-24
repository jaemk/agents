#!/usr/bin/env python3
"""
spec.py - spec-driven workflow helper for the /spec skill.

Manages a repo-root spec/ directory: a feature-status table, per-topic docs with
stable append-only IDs, and a document-first discipline (plan before build).

Usage:
  spec.py COMMAND [PROJECT] [options]

Commands:
  init   [PROJECT] [--dir D]                  scaffold the spec dir
  add    NAME [PROJECT] [--status S] [--desc TEXT] [--dir D]
                                              add a new spec doc + table row
  todo   [PROJECT] [--dir D] [--json]         list unimplemented specs
  set    NAME [PROJECT] --status S [--dir D]  set an existing row's status
  sync   [PROJECT] [--dir D] [--json]         report status counts and inconsistencies

Exit codes: 0 ok, 1 inconsistency (sync), 2 usage error, 3 precondition failure.
"""

import argparse
import json
import re
import sys
from pathlib import Path

COMMANDS = ("init", "add", "todo", "set", "sync")

README_NAME = "README.md"

README_TEMPLATE = """\
# Spec

Every feature is documented here before or as it lands, with its status.

## Feature status

Status values: `done` (implemented and covered by tests), `pending` (documented,
not yet built; the default), `research` (needs investigation or design before it
can be built). Keep each row's status current with `spec.py set`.

| Feature | Status | Spec |
|---------|--------|------|

## Conventions

- Each normative statement carries a stable ID (e.g. `FEAT-1`, `API-3`). IDs are
  append-only: retire an ID by marking it removed, never reuse the number.
- Specs are document-first: a feature is documented (status `pending`, or
  `research` if it needs design work) before implementation begins. Flip to
  `done` only once implemented and verified.
- Spec files are named `<slug>.md` and linked from the table above.
"""

DOC_TEMPLATE = """\
# {name}
{desc_paragraph}
## {prefix}-1

(Add normative statements here. Each gets a stable ID like `{prefix}-2`, `{prefix}-3`, ...)
"""


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------


def resolve_dir(project_root, dir_opt):
    """Return the resolved Path for the spec directory.

    Priority: --dir NAME wins; then prefer an existing spec/ or specs/;
    else default to spec/.
    """
    root = Path(project_root)
    if dir_opt:
        return root / dir_opt
    for candidate in ("spec", "specs"):
        d = root / candidate
        if d.exists():
            return d
    return root / "spec"


def slugify(name):
    """Convert a feature name to a filesystem slug."""
    s = name.lower()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    s = s.strip("-")
    return s


def id_prefix(slug):
    """Derive the uppercased ID prefix from the slug (alnum stem only)."""
    stem = re.sub(r"[^a-z0-9]", "", slug)
    if not stem:
        stem = "spec"
    return stem[:6].upper()


def parse_table(readme_path):
    """Parse the feature-status pipe table from README.md.

    Returns a list of dicts with keys: feature, status, spec_cell, doc_file.
    doc_file is the linked filename when spec_cell contains [text](file), else None.
    Skips the header and separator rows.
    """
    text = Path(readme_path).read_text()
    rows = []
    in_table = False
    past_sep = False
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped.startswith("|"):
            in_table = False
            past_sep = False
            continue
        # Detect table header by checking for Feature/Status columns.
        cells = [c.strip() for c in stripped.strip("|").split("|")]
        if len(cells) < 2:
            continue
        if cells[0].lower() == "feature" and cells[1].lower() == "status":
            in_table = True
            past_sep = False
            continue
        if in_table and not past_sep:
            # Separator row: cells like --- or ------
            if all(re.fullmatch(r"-+", c.replace(" ", "")) for c in cells if c.replace(" ", "")):
                past_sep = True
                continue
        if in_table and past_sep:
            if len(cells) < 3:
                continue
            feature = cells[0]
            status = cells[1]
            spec_cell = cells[2]
            # Extract link target from [text](file.md), else no doc file.
            m = re.search(r"\(([^)]+\.md)\)", spec_cell)
            doc_file = m.group(1) if m else None
            rows.append({
                "feature": feature,
                "status": status,
                "spec_cell": spec_cell,
                "doc_file": doc_file,
            })
    return rows


def append_table_row(readme_path, name, status, slug):
    """Insert a data row into the feature-status table in README.md.

    The row is placed inside the table - right after the separator and any
    existing data rows - not at end-of-file, so the table block stays
    contiguous and parse_table reads it (the table precedes later sections
    like Conventions).
    """
    readme = Path(readme_path)
    lines = readme.read_text().splitlines()
    row = f"| {name} | {status} | [{slug}.md]({slug}.md) |"

    # Find the header row (| Feature | Status | ...); the separator follows it.
    sep_idx = None
    for i, line in enumerate(lines):
        s = line.strip()
        if not s.startswith("|"):
            continue
        cells = [c.strip() for c in s.strip("|").split("|")]
        if len(cells) >= 2 and cells[0].lower() == "feature" and cells[1].lower() == "status":
            sep_idx = i + 1  # the |---|---| separator line
            break

    if sep_idx is None or sep_idx >= len(lines):
        # No recognizable table; fall back to appending at EOF.
        readme.write_text(readme.read_text().rstrip("\n") + "\n" + row + "\n")
        return

    # Advance past the separator and any contiguous existing data rows.
    insert_at = sep_idx
    while insert_at + 1 < len(lines) and lines[insert_at + 1].strip().startswith("|"):
        insert_at += 1

    lines.insert(insert_at + 1, row)
    readme.write_text("\n".join(lines) + "\n")


# ---------------------------------------------------------------------------
# init
# ---------------------------------------------------------------------------


def cmd_init(args):
    root = args.project or "."
    spec_dir = resolve_dir(root, args.dir)
    spec_dir.mkdir(parents=True, exist_ok=True)
    readme = spec_dir / README_NAME
    if readme.exists():
        print(f"spec already initialized at {spec_dir}")
        return 0
    readme.write_text(README_TEMPLATE)
    print(f"initialized spec at {spec_dir}")
    return 0


# ---------------------------------------------------------------------------
# add
# ---------------------------------------------------------------------------


def cmd_add(args):
    root = args.project or "."
    spec_dir = resolve_dir(root, args.dir)
    readme = spec_dir / README_NAME
    if not readme.exists():
        print(f"spec dir not initialized: {spec_dir}", file=sys.stderr)
        return 3

    slug = slugify(args.name)
    if not slug:
        print(f"add: cannot derive a slug from name: {args.name!r}", file=sys.stderr)
        return 2

    doc_path = spec_dir / f"{slug}.md"
    if doc_path.exists():
        print(f"refusing to overwrite {doc_path}", file=sys.stderr)
        return 3

    prefix = id_prefix(slug)
    desc_paragraph = f"\n{args.desc}\n" if args.desc else "\n"
    content = DOC_TEMPLATE.format(name=args.name, desc_paragraph=desc_paragraph, prefix=prefix)
    doc_path.write_text(content)

    append_table_row(readme, args.name, args.status, slug)
    print(f"added spec {slug}.md ({args.status})")
    return 0


# ---------------------------------------------------------------------------
# todo
# ---------------------------------------------------------------------------


def cmd_todo(args):
    root = args.project or "."
    spec_dir = resolve_dir(root, args.dir)
    readme = spec_dir / README_NAME
    if not readme.exists():
        print(f"spec dir not initialized: {spec_dir}", file=sys.stderr)
        return 3

    rows = parse_table(readme)
    pending = [r for r in rows if r["status"] != "done"]

    if args.json:
        out = [{"status": r["status"], "feature": r["feature"], "spec": r["spec_cell"]}
               for r in pending]
        print(json.dumps(out, indent=2))
        return 0

    for r in pending:
        print(f"{r['status']}\t{r['feature']}\t{r['spec_cell']}")
    return 0


# ---------------------------------------------------------------------------
# sync
# ---------------------------------------------------------------------------


def cmd_sync(args):
    root = args.project or "."
    spec_dir = resolve_dir(root, args.dir)
    readme = spec_dir / README_NAME
    if not readme.exists():
        print(f"spec dir not initialized: {spec_dir}", file=sys.stderr)
        return 3

    rows = parse_table(readme)

    # Count by status.
    counts = {}
    for r in rows:
        counts[r["status"]] = counts.get(r["status"], 0) + 1

    # (a) rows whose referenced doc file is missing.
    missing = []
    referenced = set()
    for r in rows:
        if r["doc_file"]:
            referenced.add(r["doc_file"])
            p = spec_dir / r["doc_file"]
            if not p.exists():
                missing.append(r["doc_file"])

    # (b) *.md in spec dir other than README.md not referenced by any row.
    orphans = []
    for p in sorted(spec_dir.glob("*.md")):
        if p.name == README_NAME:
            continue
        if p.name not in referenced:
            orphans.append(p.name)

    if args.json:
        out = {
            "counts": counts,
            "missing": missing,
            "orphans": orphans,
        }
        print(json.dumps(out, indent=2))
    else:
        for status, count in sorted(counts.items()):
            print(f"{count}\t{status}")
        for f in missing:
            print(f"missing doc: {f}")
        for f in orphans:
            print(f"orphan doc: {f}")

    if missing or orphans:
        return 1
    return 0


# ---------------------------------------------------------------------------
# set
# ---------------------------------------------------------------------------


def cmd_set(args):
    root = args.project or "."
    spec_dir = resolve_dir(root, args.dir)
    readme = spec_dir / README_NAME
    if not readme.exists():
        print(f"spec dir not initialized: {spec_dir}", file=sys.stderr)
        return 3

    lines = readme.read_text().splitlines()
    target = args.name.strip().lower()
    in_table = False
    past_sep = False
    updated = False
    for i, line in enumerate(lines):
        s = line.strip()
        if not s.startswith("|"):
            in_table = False
            past_sep = False
            continue
        cells = [c.strip() for c in s.strip("|").split("|")]
        if len(cells) >= 2 and cells[0].lower() == "feature" and cells[1].lower() == "status":
            in_table = True
            past_sep = False
            continue
        if in_table and not past_sep:
            if all(re.fullmatch(r"-+", c.replace(" ", "")) for c in cells if c.replace(" ", "")):
                past_sep = True
                continue
        if in_table and past_sep and len(cells) >= 3 and cells[0].lower() == target:
            cells[1] = args.status
            lines[i] = "| " + " | ".join(cells) + " |"
            updated = True
            break

    if not updated:
        print(f"set: no table row matching feature {args.name!r}", file=sys.stderr)
        return 3

    readme.write_text("\n".join(lines) + "\n")
    print(f"set {args.name} -> {args.status}")
    return 0


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main(argv=None):
    if argv is None:
        argv = sys.argv[1:]

    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = ap.add_subparsers(dest="command", metavar="COMMAND")

    p_init = sub.add_parser("init", help="scaffold the spec dir")
    p_init.add_argument("project", nargs="?", default=None, metavar="PROJECT",
                        help="project root (default: .)")
    p_init.add_argument("--dir", default=None, metavar="D",
                        help="spec dir name relative to project root")

    p_add = sub.add_parser("add", help="add a new spec doc + table row")
    p_add.add_argument("name", metavar="NAME", help="feature name")
    p_add.add_argument("project", nargs="?", default=None, metavar="PROJECT",
                       help="project root (default: .)")
    p_add.add_argument("--status", default="pending",
                       help="initial status: done, pending, or research (default: pending)")
    p_add.add_argument("--desc", default=None, metavar="TEXT",
                       help="optional description paragraph")
    p_add.add_argument("--dir", default=None, metavar="D",
                       help="spec dir name relative to project root")

    p_todo = sub.add_parser("todo", help="list unimplemented specs")
    p_todo.add_argument("project", nargs="?", default=None, metavar="PROJECT",
                        help="project root (default: .)")
    p_todo.add_argument("--dir", default=None, metavar="D",
                        help="spec dir name relative to project root")
    p_todo.add_argument("--json", action="store_true", help="emit JSON array")

    p_set = sub.add_parser("set", help="set an existing row's status")
    p_set.add_argument("name", metavar="NAME", help="feature name (matches the table row)")
    p_set.add_argument("project", nargs="?", default=None, metavar="PROJECT",
                       help="project root (default: .)")
    p_set.add_argument("--status", required=True,
                       help="new status: done, pending, or research")
    p_set.add_argument("--dir", default=None, metavar="D",
                       help="spec dir name relative to project root")

    p_sync = sub.add_parser("sync", help="report status counts and inconsistencies")
    p_sync.add_argument("project", nargs="?", default=None, metavar="PROJECT",
                        help="project root (default: .)")
    p_sync.add_argument("--dir", default=None, metavar="D",
                        help="spec dir name relative to project root")
    p_sync.add_argument("--json", action="store_true", help="emit JSON")

    if not argv:
        ap.print_usage(sys.stderr)
        return 2
    if argv[0] not in COMMANDS and argv[0] not in ("-h", "--help"):
        print(f"spec.py: unknown command {argv[0]!r}; choose from {', '.join(COMMANDS)}",
              file=sys.stderr)
        return 2

    args = ap.parse_args(argv)

    if args.command == "init":
        return cmd_init(args)
    if args.command == "add":
        return cmd_add(args)
    if args.command == "todo":
        return cmd_todo(args)
    if args.command == "set":
        return cmd_set(args)
    if args.command == "sync":
        return cmd_sync(args)

    ap.print_usage(sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
