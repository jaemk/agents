---
description: Plan a set of work units into review/implementation shards.
bin: shard-plan.py
---
Shared sharding helper used by the review skill and the planner agent. Invoke via {{tools:shard-plan}}.

It groups work units into disjoint-file shards (units sharing a written file land together, so
parallel agents never collide) in randomized order. Reads units one per line as
`unit-id  written-file [written-file ...]`.

Prefer the file-argument form so the call is statically auto-approvable:

    {{tools:shard-plan}} --max-units 4 /abs/path/to/units.txt

Write the units to a file with the editor first, then pass its path. A `printf ... |` pipe also
works (stdin) but forces a manual approval prompt. `--max-units` caps units per shard;
`--seed N` makes the shard order reproducible. Usage errors (bad `--max-units`, unreadable
file, duplicate unit id, a unit with no files) exit 2 with a one-line message.
