#!/usr/bin/env bash
# hermetic-verify skill: the probe.sh runner template.

PROBE_TMPL="$REPO/skills/hermetic-verify/resources/probe.sh"

test_hermetic_probe_template_shippable() {
    assert_file "$PROBE_TMPL" "probe template: file exists"
    assert_exec "$PROBE_TMPL" "probe template: executable bit set"
    local first; first="$(head -n1 "$PROBE_TMPL")"
    assert_eq '#!/usr/bin/env bash' "$first" "probe template: has bash shebang"
}

test_hermetic_probe_template_guard() {
    # Unadapted, the template must refuse to run rather than silently probe
    # nothing, so a copy that was never filled in fails loudly. It exits before
    # the mktemp workdir, so running it here touches no state.
    cap bash "$PROBE_TMPL"
    assert_exit 3 "$RC" "probe template: unadapted run exits 3"
    assert_contains "$OUT" "not adapted" "probe template: unadapted run explains why"
}

register test_hermetic_probe_template_shippable test_hermetic_probe_template_guard
