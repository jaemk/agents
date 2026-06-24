#!/usr/bin/env bash
# skills/spec/resources/spec.py: spec-driven workflow helper.

# ---------------------------------------------------------------------------
# init
# ---------------------------------------------------------------------------

test_spec_init_fresh() {
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    assert_exit 0 "$RC" "spec init: exit 0"
    assert_contains "$OUT" "initialized spec at" "spec init: reports initialization"
    assert_file "$d/spec/README.md" "spec init: README.md created"
    local c; c="$(< "$d/spec/README.md")"
    assert_contains "$c" "| Feature | Status | Spec |" "spec init: table header present"
    assert_contains "$c" "pending" "spec init: status legend mentions pending"
    assert_contains "$c" "done" "spec init: status legend mentions done"
    assert_contains "$c" "research" "spec init: status legend mentions research"
    assert_contains "$c" "append-only" "spec init: Conventions mentions append-only IDs"
    assert_contains "$c" "document-first" "spec init: Conventions mentions document-first"
}

test_spec_init_idempotent() {
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    assert_exit 0 "$RC" "spec init idempotent: first run exit 0"
    local content_before; content_before="$(< "$d/spec/README.md")"
    cap "$SPEC_PY" init "$d"
    assert_exit 0 "$RC" "spec init idempotent: second run exit 0"
    assert_contains "$OUT" "already initialized" "spec init idempotent: reports already initialized"
    local content_after; content_after="$(< "$d/spec/README.md")"
    assert_eq "$content_before" "$content_after" "spec init idempotent: README.md unchanged"
}

# ---------------------------------------------------------------------------
# add
# ---------------------------------------------------------------------------

test_spec_add_basic() {
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "Auth Flow" "$d" --status pending
    assert_exit 0 "$RC" "spec add: exit 0"
    assert_contains "$OUT" "added spec auth-flow.md" "spec add: reports slug"
    assert_contains "$OUT" "pending" "spec add: reports status"
    assert_file "$d/spec/auth-flow.md" "spec add: doc file created"
    local doc; doc="$(< "$d/spec/auth-flow.md")"
    assert_contains "$doc" "# Auth Flow" "spec add: H1 matches name"
    assert_contains "$doc" "AUTHFL-1" "spec add: starter ID present"
    local readme; readme="$(< "$d/spec/README.md")"
    assert_contains "$readme" "| Auth Flow | pending | [auth-flow.md](auth-flow.md) |" "spec add: table row appended"
}

test_spec_add_with_desc() {
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "Cache Layer" "$d" --desc "Redis-backed caching."
    assert_exit 0 "$RC" "spec add desc: exit 0"
    local doc; doc="$(< "$d/spec/cache-layer.md")"
    assert_contains "$doc" "Redis-backed caching." "spec add desc: description in doc"
}

test_spec_add_done_status() {
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "Core API" "$d" --status done
    assert_exit 0 "$RC" "spec add done: exit 0"
    local readme; readme="$(< "$d/spec/README.md")"
    assert_contains "$readme" "| Core API | done |" "spec add done: status in table row"
}

test_spec_add_default_status_pending() {
    # With no --status, a new row defaults to pending.
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "Future Thing" "$d"
    assert_exit 0 "$RC" "spec add default: exit 0"
    local readme; readme="$(< "$d/spec/README.md")"
    assert_contains "$readme" "| Future Thing | pending |" "spec add default: status defaults to pending"
}

test_spec_add_overwrite_refused() {
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "Auth Flow" "$d"
    cap "$SPEC_PY" add "Auth Flow" "$d"
    assert_exit 3 "$RC" "spec add overwrite: exit 3"
    assert_contains "$OUT" "refusing to overwrite" "spec add overwrite: reports refusal"
}

test_spec_add_uninitialized() {
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" add "Feature X" "$d"
    assert_exit 3 "$RC" "spec add uninit: exit 3"
    assert_contains "$OUT" "spec dir not initialized" "spec add uninit: reports not initialized"
}

# ---------------------------------------------------------------------------
# todo
# ---------------------------------------------------------------------------

test_spec_todo_lists_pending() {
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "Feature A" "$d" --status pending
    cap "$SPEC_PY" add "Feature B" "$d" --status done
    cap "$SPEC_PY" add "Feature C" "$d" --status research
    cap "$SPEC_PY" todo "$d"
    assert_exit 0 "$RC" "spec todo: exit 0"
    assert_contains "$OUT" "Feature A" "spec todo: lists pending item"
    assert_contains "$OUT" "Feature C" "spec todo: lists research item"
    assert_not_contains "$OUT" "Feature B" "spec todo: excludes done item"
    assert_contains "$OUT" "pending" "spec todo: shows pending status"
    assert_contains "$OUT" "research" "spec todo: shows research status"
}

test_spec_todo_empty() {
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "Feature A" "$d" --status done
    cap "$SPEC_PY" todo "$d"
    assert_exit 0 "$RC" "spec todo empty: exit 0 even if none"
    assert_not_contains "$OUT" "Feature A" "spec todo empty: done item excluded"
}

test_spec_todo_json() {
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "Feature A" "$d" --status pending
    cap "$SPEC_PY" todo "$d" --json
    assert_exit 0 "$RC" "spec todo json: exit 0"
    local parsed; parsed="$(printf '%s' "$OUT" | jq -r '.[0].feature')"
    assert_eq "Feature A" "$parsed" "spec todo json: feature field correct"
}

# ---------------------------------------------------------------------------
# sync
# ---------------------------------------------------------------------------

test_spec_sync_clean() {
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "Feature A" "$d" --status done
    cap "$SPEC_PY" sync "$d"
    assert_exit 0 "$RC" "spec sync clean: exit 0"
    assert_contains "$OUT" "done" "spec sync clean: counts shown"
}

test_spec_sync_missing_doc() {
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "Feature A" "$d" --status pending
    # Remove the doc file to create inconsistency.
    rm "$d/spec/feature-a.md"
    cap "$SPEC_PY" sync "$d"
    assert_exit 1 "$RC" "spec sync missing doc: exit 1"
    assert_contains "$OUT" "missing doc: feature-a.md" "spec sync missing doc: reports missing"
}

test_spec_sync_orphan_doc() {
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    # Create a .md file not referenced in the table.
    printf '# Orphan\n' > "$d/spec/orphan.md"
    cap "$SPEC_PY" sync "$d"
    assert_exit 1 "$RC" "spec sync orphan: exit 1"
    assert_contains "$OUT" "orphan doc: orphan.md" "spec sync orphan: reports orphan"
}

test_spec_sync_json() {
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "Feature A" "$d" --status done
    cap "$SPEC_PY" sync "$d" --json
    assert_exit 0 "$RC" "spec sync json: exit 0"
    local counts; counts="$(printf '%s' "$OUT" | jq -r '.counts.done')"
    assert_eq "1" "$counts" "spec sync json: counts.done correct"
    local missing; missing="$(printf '%s' "$OUT" | jq -r '.missing | length')"
    assert_eq "0" "$missing" "spec sync json: missing array empty"
}

# ---------------------------------------------------------------------------
# resolve_dir: --dir override and specs/ auto-detection
# ---------------------------------------------------------------------------

test_spec_init_dir_override() {
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d" --dir docs/spec
    assert_exit 0 "$RC" "spec init --dir: exit 0"
    assert_contains "$OUT" "initialized spec at" "spec init --dir: reports init"
    assert_file "$d/docs/spec/README.md" "spec init --dir: README under custom nested dir"
    assert_no_path "$d/spec/README.md" "spec init --dir: default spec/ not created"
}

test_spec_resolve_dir_override_used_by_add() {
    # --dir must steer add to the same custom dir, not the default spec/.
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d" --dir mydocs
    cap "$SPEC_PY" add "Feature A" "$d" --dir mydocs
    assert_exit 0 "$RC" "spec add --dir: exit 0"
    assert_file "$d/mydocs/feature-a.md" "spec add --dir: doc lands in custom dir"
    local readme; readme="$(< "$d/mydocs/README.md")"
    assert_contains "$readme" "| Feature A | pending |" "spec add --dir: row in custom dir README"
}

test_spec_resolve_dir_autodetect_specs() {
    # An existing specs/ dir (no spec/) is preferred over the default spec/.
    local d; d="$(mktemp_d)"
    mkdir -p "$d/specs"
    cap "$SPEC_PY" init "$d"
    assert_exit 0 "$RC" "spec init autodetect specs/: exit 0"
    assert_file "$d/specs/README.md" "spec init autodetect: README in existing specs/"
    assert_no_path "$d/spec/README.md" "spec init autodetect: default spec/ not created"
    # add must follow the same auto-detection.
    cap "$SPEC_PY" add "Feature A" "$d"
    assert_exit 0 "$RC" "spec add autodetect specs/: exit 0"
    assert_file "$d/specs/feature-a.md" "spec add autodetect: doc in specs/"
}

test_spec_resolve_dir_prefers_spec_over_specs() {
    # When both spec/ and specs/ exist, spec/ wins (listed first).
    local d; d="$(mktemp_d)"
    mkdir -p "$d/spec" "$d/specs"
    cap "$SPEC_PY" init "$d"
    assert_exit 0 "$RC" "spec init both dirs: exit 0"
    assert_file "$d/spec/README.md" "spec init both dirs: spec/ preferred"
    assert_no_path "$d/specs/README.md" "spec init both dirs: specs/ untouched"
}

# ---------------------------------------------------------------------------
# add: prefix derivation, starter ID, slug edge cases
# ---------------------------------------------------------------------------

test_spec_add_prefix_multiword_punct() {
    # PREFIX = first 6 uppercased alnum chars of the slug stem; punctuation drops.
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "OAuth2 / SSO Login!" "$d"
    assert_exit 0 "$RC" "spec add punct: exit 0"
    assert_contains "$OUT" "added spec oauth2-sso-login.md" "spec add punct: slug drops punctuation"
    local doc; doc="$(< "$d/spec/oauth2-sso-login.md")"
    assert_contains "$doc" "## OAUTH2-1" "spec add punct: starter ID prefix is first 6 alnum chars"
    assert_contains "$doc" "OAUTH2-2" "spec add punct: example next ID uses same prefix"
    assert_contains "$doc" "# OAuth2 / SSO Login!" "spec add punct: H1 keeps original name"
}

test_spec_add_starter_id_short_name() {
    # Short stem -> prefix shorter than 6 chars, still ends in -1.
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "DB" "$d"
    assert_exit 0 "$RC" "spec add short: exit 0"
    local doc; doc="$(< "$d/spec/db.md")"
    assert_contains "$doc" "## DB-1" "spec add short: prefix is whole stem when < 6 chars"
}

test_spec_add_desc_paragraph_absent_by_default() {
    # Without --desc there is no description paragraph between H1 and the ## ID.
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "Plain Feature" "$d"
    local doc; doc="$(< "$d/spec/plain-feature.md")"
    assert_contains "$doc" "# Plain Feature" "spec add no-desc: H1 present"
    assert_contains "$doc" "## PLAINF-1" "spec add no-desc: starter ID present"
}

test_spec_add_empty_slug_rejected() {
    # A name with no alnum chars cannot produce a slug -> usage error (exit 2).
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "!!!" "$d"
    assert_exit 2 "$RC" "spec add empty slug: exit 2"
    assert_contains "$OUT" "cannot derive a slug" "spec add empty slug: reports failure"
    assert_no_path "$d/spec/.md" "spec add empty slug: no stray doc written"
}

test_spec_add_slug_collision_different_name() {
    # Two distinct names that slugify identically must collide on the second add.
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "Auth Flow" "$d"
    assert_exit 0 "$RC" "spec add collision: first add ok"
    cap "$SPEC_PY" add "auth   flow" "$d"
    assert_exit 3 "$RC" "spec add collision: second add refused (exit 3)"
    assert_contains "$OUT" "refusing to overwrite" "spec add collision: reports refusal"
}

# ---------------------------------------------------------------------------
# table integrity: rows stay inside the table (regression guard)
# ---------------------------------------------------------------------------

test_spec_add_rows_contiguous_in_table() {
    # Regression guard for the prior bug where rows were written below
    # "## Conventions" (outside the table), breaking todo/sync.
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "Alpha" "$d" --status pending
    cap "$SPEC_PY" add "Beta" "$d" --status research
    cap "$SPEC_PY" add "Gamma" "$d" --status done

    # All three rows must be parsed by todo/sync, proving they are in the table.
    cap "$SPEC_PY" todo "$d"
    assert_contains "$OUT" "Alpha" "spec rows contiguous: Alpha visible to todo"
    assert_contains "$OUT" "Beta" "spec rows contiguous: Beta visible to todo"
    assert_not_contains "$OUT" "Gamma" "spec rows contiguous: done Gamma excluded"

    # No data row may appear below the Conventions heading.
    local readme; readme="$(< "$d/spec/README.md")"
    local below; below="${readme#*## Conventions}"
    assert_not_contains "$below" "| Alpha |" "spec rows contiguous: Alpha not below Conventions"
    assert_not_contains "$below" "| Gamma |" "spec rows contiguous: Gamma not below Conventions"
    # And the table block above Conventions holds all rows + Conventions intact.
    assert_contains "$readme" "## Conventions" "spec rows contiguous: Conventions section preserved"

    # sync must count all three (1 each), confirming every row parsed.
    cap "$SPEC_PY" sync "$d" --json
    local total; total="$(printf '%s' "$OUT" | jq -r '[.counts[]] | add')"
    assert_eq "3" "$total" "spec rows contiguous: sync counts all 3 rows"
}

# ---------------------------------------------------------------------------
# todo: exact field shape and json field names
# ---------------------------------------------------------------------------

test_spec_todo_tab_shape() {
    # Each line is exactly status<TAB>feature<TAB>spec-cell.
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "Alpha" "$d" --status pending
    cap "$SPEC_PY" todo "$d"
    assert_eq "$(printf 'pending\tAlpha\t[alpha.md](alpha.md)')" "$OUT" \
        "spec todo shape: exact tab-separated line"
}

test_spec_todo_json_all_fields() {
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "Alpha" "$d" --status research
    cap "$SPEC_PY" todo "$d" --json
    assert_exit 0 "$RC" "spec todo json fields: exit 0"
    local status; status="$(printf '%s' "$OUT" | jq -r '.[0].status')"
    local spec;   spec="$(printf '%s' "$OUT" | jq -r '.[0].spec')"
    local feature; feature="$(printf '%s' "$OUT" | jq -r '.[0].feature')"
    assert_eq "research" "$status" "spec todo json fields: status field"
    assert_eq "Alpha" "$feature" "spec todo json fields: feature field"
    assert_eq "[alpha.md](alpha.md)" "$spec" "spec todo json fields: spec field is raw cell"
}

test_spec_todo_uninitialized() {
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" todo "$d"
    assert_exit 3 "$RC" "spec todo uninit: exit 3"
    assert_contains "$OUT" "spec dir not initialized" "spec todo uninit: reports not initialized"
}

# ---------------------------------------------------------------------------
# sync: combined inconsistencies, mixed counts, hand-edited status
# ---------------------------------------------------------------------------

test_spec_sync_missing_and_orphan_together() {
    # Both inconsistency classes at once: still exit 1, both messages present.
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "Alpha" "$d" --status pending
    cap "$SPEC_PY" add "Beta" "$d" --status done
    rm "$d/spec/alpha.md"                       # missing doc
    printf '# Orphan\n' > "$d/spec/orphan.md"   # orphan doc
    cap "$SPEC_PY" sync "$d"
    assert_exit 1 "$RC" "spec sync both: exit 1"
    assert_contains "$OUT" "missing doc: alpha.md" "spec sync both: reports missing"
    assert_contains "$OUT" "orphan doc: orphan.md" "spec sync both: reports orphan"
    # Mixed counts wording: <count>\t<status>, one per distinct status.
    assert_contains "$OUT" "$(printf '1\tdone')" "spec sync both: done count line"
    assert_contains "$OUT" "$(printf '1\tpending')" "spec sync both: pending count line"
}

test_spec_sync_both_json() {
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "Alpha" "$d" --status pending
    rm "$d/spec/alpha.md"
    printf '# Orphan\n' > "$d/spec/orphan.md"
    cap "$SPEC_PY" sync "$d" --json
    assert_exit 1 "$RC" "spec sync both json: exit 1"
    local m; m="$(printf '%s' "$OUT" | jq -r '.missing[0]')"
    local o; o="$(printf '%s' "$OUT" | jq -r '.orphans[0]')"
    assert_eq "alpha.md" "$m" "spec sync both json: missing entry"
    assert_eq "orphan.md" "$o" "spec sync both json: orphan entry"
}

test_spec_sync_counts_mixed_statuses() {
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "A" "$d" --status pending
    cap "$SPEC_PY" add "B" "$d" --status pending
    cap "$SPEC_PY" add "C" "$d" --status research
    cap "$SPEC_PY" add "D" "$d" --status done
    cap "$SPEC_PY" sync "$d" --json
    assert_exit 0 "$RC" "spec sync mixed: clean tree exit 0"
    assert_eq "2" "$(printf '%s' "$OUT" | jq -r '.counts.pending')" "spec sync mixed: pending=2"
    assert_eq "1" "$(printf '%s' "$OUT" | jq -r '.counts.research')" "spec sync mixed: research=1"
    assert_eq "1" "$(printf '%s' "$OUT" | jq -r '.counts.done')" "spec sync mixed: done=1"
}

test_spec_flip_status_to_done_by_hand() {
    # Hand-editing a row to done removes it from todo and shifts sync counts.
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "Shippable" "$d" --status pending
    cap "$SPEC_PY" todo "$d"
    assert_contains "$OUT" "Shippable" "spec flip: pending before edit"
    # Flip the status cell from pending to done in place.
    sed -i 's/| Shippable | pending |/| Shippable | done |/' "$d/spec/README.md"
    cap "$SPEC_PY" todo "$d"
    assert_not_contains "$OUT" "Shippable" "spec flip: excluded from todo after flip"
    cap "$SPEC_PY" sync "$d" --json
    assert_eq "1" "$(printf '%s' "$OUT" | jq -r '.counts.done')" "spec flip: sync counts it as done"
    assert_eq "null" "$(printf '%s' "$OUT" | jq -r '.counts.pending')" "spec flip: no pending remaining"
}

test_spec_sync_uninitialized() {
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" sync "$d"
    assert_exit 3 "$RC" "spec sync uninit: exit 3"
    assert_contains "$OUT" "spec dir not initialized" "spec sync uninit: reports not initialized"
}

# ---------------------------------------------------------------------------
# set
# ---------------------------------------------------------------------------

test_spec_set_to_done() {
    # set flips a row to done, removing it from todo and shifting sync counts.
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "Shippable" "$d" --status pending
    cap "$SPEC_PY" set "Shippable" "$d" --status done
    assert_exit 0 "$RC" "spec set: exit 0"
    assert_contains "$OUT" "set Shippable -> done" "spec set: reports change"
    local readme; readme="$(< "$d/spec/README.md")"
    assert_contains "$readme" "| Shippable | done | [shippable.md](shippable.md) |" \
        "spec set: status cell rewritten, link preserved"
    cap "$SPEC_PY" todo "$d"
    assert_not_contains "$OUT" "Shippable" "spec set: excluded from todo after flip"
    cap "$SPEC_PY" sync "$d" --json
    assert_eq "1" "$(printf '%s' "$OUT" | jq -r '.counts.done')" "spec set: sync counts it as done"
}

test_spec_set_to_research() {
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "Half Done" "$d" --status pending
    cap "$SPEC_PY" set "Half Done" "$d" --status research
    assert_exit 0 "$RC" "spec set research: exit 0"
    local readme; readme="$(< "$d/spec/README.md")"
    assert_contains "$readme" "| Half Done | research |" "spec set research: status cell rewritten"
}

test_spec_set_no_match() {
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" add "Shippable" "$d" --status pending
    cap "$SPEC_PY" set "Nonexistent" "$d" --status done
    assert_exit 3 "$RC" "spec set no match: exit 3"
    assert_contains "$OUT" "no table row matching feature" "spec set no match: reports failure"
}

test_spec_set_uninitialized() {
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" set "Anything" "$d" --status done
    assert_exit 3 "$RC" "spec set uninit: exit 3"
    assert_contains "$OUT" "spec dir not initialized" "spec set uninit: reports not initialized"
}

test_spec_set_requires_status() {
    local d; d="$(mktemp_d)"
    cap "$SPEC_PY" init "$d"
    cap "$SPEC_PY" set "Shippable" "$d"
    assert_exit 2 "$RC" "spec set no --status: exit 2 (argparse usage error)"
}

# ---------------------------------------------------------------------------
# dispatch: unknown command and no-arg
# ---------------------------------------------------------------------------

test_spec_unknown_command() {
    cap "$SPEC_PY" bogus
    assert_exit 2 "$RC" "spec unknown command: exit 2"
    assert_contains "$OUT" "unknown command" "spec unknown command: reports unknown"
}

test_spec_no_args() {
    cap "$SPEC_PY"
    assert_exit 2 "$RC" "spec no args: exit 2"
}

register \
    test_spec_init_fresh \
    test_spec_init_idempotent \
    test_spec_init_dir_override \
    test_spec_resolve_dir_override_used_by_add \
    test_spec_resolve_dir_autodetect_specs \
    test_spec_resolve_dir_prefers_spec_over_specs \
    test_spec_add_basic \
    test_spec_add_with_desc \
    test_spec_add_done_status \
    test_spec_add_default_status_pending \
    test_spec_add_overwrite_refused \
    test_spec_add_uninitialized \
    test_spec_add_prefix_multiword_punct \
    test_spec_add_starter_id_short_name \
    test_spec_add_desc_paragraph_absent_by_default \
    test_spec_add_empty_slug_rejected \
    test_spec_add_slug_collision_different_name \
    test_spec_add_rows_contiguous_in_table \
    test_spec_todo_lists_pending \
    test_spec_todo_empty \
    test_spec_todo_json \
    test_spec_todo_tab_shape \
    test_spec_todo_json_all_fields \
    test_spec_todo_uninitialized \
    test_spec_sync_clean \
    test_spec_sync_missing_doc \
    test_spec_sync_orphan_doc \
    test_spec_sync_json \
    test_spec_sync_missing_and_orphan_together \
    test_spec_sync_both_json \
    test_spec_sync_counts_mixed_statuses \
    test_spec_flip_status_to_done_by_hand \
    test_spec_sync_uninitialized \
    test_spec_set_to_done \
    test_spec_set_to_research \
    test_spec_set_no_match \
    test_spec_set_uninitialized \
    test_spec_set_requires_status \
    test_spec_unknown_command \
    test_spec_no_args
