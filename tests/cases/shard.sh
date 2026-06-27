#!/usr/bin/env bash
# resources/shard-plan.py: disjoint-file grouping, randomized order, packing.

test_shard_grouping() {
    local out; out="$(printf '%s\n' 'u1 a.x t.x' 'u2 b.x t.x' 'u3 c.x' | "$SHARD" --max-units 1 --seed 1)"
    local grp; grp="$(printf '%s\n' "$out" | awk -F'\t' '{n=split($1,a,","); for(i=1;i<=n;i++) if(a[i]=="u1") print $1}')"
    assert_contains "$grp" "u2" "shard: units sharing a written file land in one shard"
    local dups; dups="$(printf '%s\n' "$out" | cut -f2 | tr ',' '\n' | sort | uniq -d)"
    assert_eq "" "$dups" "shard: no file spans two shards"
}

test_shard_determinism() {
    local a b
    a="$(printf '%s\n' 'u1 x' 'u2 y' | "$SHARD" --seed 5)"
    b="$(printf '%s\n' 'u1 x' 'u2 y' | "$SHARD" --seed 5)"
    assert_eq "$a" "$b" "shard: deterministic for a fixed seed"
}

test_shard_random() {
    local n
    n="$(for s in 1 2 3 4 5 6 7 8; do printf '%s\n' 'u1 a' 'u2 b' 'u3 c' 'u4 d' | "$SHARD" --max-units 1 --seed "$s" | cut -f1 | paste -sd'|' -; done | sort -u | wc -l | tr -d ' ')"
    assert_ne "1" "$n" "shard: shard order varies across seeds"
}

test_shard_packing() {
    local lines
    lines="$(printf '%s\n' 'u1 a' 'u2 b' 'u3 c' | "$SHARD" --max-units 9 --seed 1 | wc -l | tr -d ' ')"
    assert_eq "1" "$lines" "shard: disjoint units pack into one shard under a high max-units"
}

test_shard_empty() {
    assert_eq "" "$(printf '' | "$SHARD")" "shard: empty input -> no output"
}

test_shard_file_input() {
    local f; f="$(mktemp)"
    printf '%s\n' 'u1 a.x t.x' 'u2 b.x t.x' 'u3 c.x' > "$f"
    local fout sout
    fout="$("$SHARD" --max-units 1 --seed 1 "$f")"
    sout="$(printf '%s\n' 'u1 a.x t.x' 'u2 b.x t.x' 'u3 c.x' | "$SHARD" --max-units 1 --seed 1)"
    rm -f "$f"
    assert_eq "$sout" "$fout" "shard: UNITS_FILE argument matches stdin input"
}

test_shard_missing_file() {
    cap "$SHARD" /no/such/units/file
    assert_exit 2 "$RC" "shard: unreadable units file exits 2"
    assert_not_contains "$OUT" "Traceback" "shard: missing file gives a clean error, not a traceback"
}

test_shard_bad_max_units() {
    cap bash -c "printf '%s\n' 'u1 a' | '$SHARD' --max-units 0"
    assert_exit 2 "$RC" "shard: --max-units 0 exits 2"
}

test_shard_duplicate_id() {
    cap bash -c "printf '%s\n' 'u1 a.x' 'u1 b.x' | '$SHARD'"
    assert_exit 2 "$RC" "shard: duplicate unit id exits 2"
    assert_contains "$OUT" "duplicate unit id" "shard: duplicate id is reported"
}

test_shard_no_files() {
    cap bash -c "printf '%s\n' 'u1' | '$SHARD'"
    assert_exit 2 "$RC" "shard: a unit listing no written files exits 2"
}

register test_shard_grouping test_shard_determinism test_shard_random test_shard_packing \
         test_shard_empty test_shard_file_input test_shard_missing_file \
         test_shard_bad_max_units test_shard_duplicate_id test_shard_no_files
