#!/usr/bin/env python3
"""shard-plan.py - group work units into disjoint-file shards in randomized order.

This is the planner's sharding mechanism, extracted into a committed, tested script so
the agent prose can invoke it instead of hand-rolling the algorithm.

Reads units on stdin, one per line:

    UNIT_ID  FILE [FILE ...]

The first whitespace-separated token is the unit id; the rest are the files that unit
WRITES. Every unit must name at least one written file, and ids must be unique; a unit
with no files or a repeated id is a usage error (exit 2). Units that share any written
file are forced into the same shard, so no file
ever spans two shards and shards can run in parallel without colliding. The resulting
shards are emitted in a randomized order (fresh OS entropy each run, or fixed via
--seed for reproducibility) and greedily packed up to --max-units units per shard
(a single mandatory group is never split, even if it exceeds the cap).

--max-units caps units PER SHARD, not the number of shards: a high value (>= the unit
count) packs every disjoint group onto one line, while --max-units 1 emits each
mandatory group on its own line. Pick it to match how many units one executor should
own at once.

Usage:  shard-plan.py [--max-units N] [--seed N] [UNITS_FILE]
        Units are read from UNITS_FILE when given, else from stdin. Passing a
        file lets the caller avoid a `printf ... |` pipe (auto-approvable).
Output: one shard per line:  UNIT_ID,UNIT_ID<TAB>FILE,FILE   (ids in input order,
        files sorted). Empty input produces no output.
Exit:   0 ok, 2 usage error (bad --max-units, unreadable file, duplicate unit id).
"""

import argparse
import random
import sys


def die(msg):
    """Print a usage error to stderr and exit 2."""
    print(f"shard-plan: {msg}", file=sys.stderr)
    raise SystemExit(2)


def read_units(units_file):
    """Parse units from a file path (or stdin when None). Returns [(id, set(files))]."""
    try:
        if units_file:
            with open(units_file, encoding="utf-8") as fh:
                lines = fh.readlines()
        else:
            lines = sys.stdin.readlines()
    except OSError as e:
        die(f"cannot read units from {units_file!r}: {e.strerror}" if units_file
            else f"cannot read units from stdin: {e.strerror}")

    units = []  # list of (id, set(files)) in input order
    seen = set()
    for lineno, line in enumerate(lines, 1):
        parts = line.split()
        if not parts:
            continue
        unit_id, files = parts[0], parts[1:]
        if unit_id in seen:
            die(f"duplicate unit id {unit_id!r} on line {lineno}")
        seen.add(unit_id)
        if not files:
            die(f"unit {unit_id!r} on line {lineno} lists no written files")
        units.append((unit_id, set(files)))
    return units


def main():
    ap = argparse.ArgumentParser(description="group work units into disjoint-file shards")
    ap.add_argument("--max-units", type=int, default=4,
                    help="max units per shard after grouping (default: 4)")
    ap.add_argument("--seed", type=int, default=None,
                    help="fix the RNG seed for reproducible shard order (default: OS entropy)")
    ap.add_argument("units_file", nargs="?", default=None,
                    help="read units from this file instead of stdin")
    args = ap.parse_args()

    if args.max_units < 1:
        die(f"--max-units must be >= 1 (got {args.max_units})")

    units = read_units(args.units_file)
    if not units:
        return 0

    # Union-find over unit indices, merging any two units that share a written file.
    parent = list(range(len(units)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    file_owner = {}
    for i, (_, files) in enumerate(units):
        for f in files:
            if f in file_owner:
                union(file_owner[f], i)
            else:
                file_owner[f] = i

    # Mandatory groups (connected components): disjoint in files by construction.
    comps = {}
    for i in range(len(units)):
        comps.setdefault(find(i), []).append(i)
    # Order components by their first unit's input position for stable pre-shuffle order.
    components = [comps[k] for k in sorted(comps, key=lambda k: min(comps[k]))]

    random.Random(args.seed).shuffle(components)  # seed=None -> system entropy

    # Greedily pack shuffled components into shards up to max-units; never split a component.
    shards = []
    cur = []
    for comp in components:
        if cur and len(cur) + len(comp) > args.max_units:
            shards.append(cur)
            cur = []
        cur.extend(comp)
    if cur:
        shards.append(cur)

    for shard in shards:
        ids = [units[i][0] for i in shard]
        files = sorted({f for i in shard for f in units[i][1]})
        print(",".join(ids) + "\t" + ",".join(files))
    return 0


if __name__ == "__main__":
    sys.exit(main())
