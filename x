#!/usr/bin/env bash
# x - manage this agents+skills library.
#
# Installs agent and skill definitions to a generic, tool-agnostic location
# ($AGENTS_HOME, default ~/.agents) and symlinks them into Claude's discovery
# locations ($CLAUDE_HOME, default ~/.claude). Install is hash-aware: an item whose
# source matches what is already installed is skipped.
#
# Subcommands:
#   install   [NAME ...] [--agents-only|--skills-only] [--force] [--dry-run]
#   uninstall [NAME ...] [--agents-only|--skills-only] [--dry-run]
#   status    [NAME ...] [--json]
#   check     [NAME ...] [--strict]
#   review    NAME [--fix] [--model ID] [--write-prompt]
#   config    [diff|apply|pull]   sync config/ <-> live $CLAUDE_HOME
#   help
#
# NAME is an item id: a bare name (matches an agent and/or skill of that name),
# or an explicit "agent:<name>" / "skill:<name>", or "resources" for the shared
# resources dir. With no NAME, operates on all items.
#
# Env overrides (the test seam - tests point these at temp dirs):
#   AGENTS_HOME  copy destination (default ~/.agents)
#   CLAUDE_HOME  symlink destination (default ~/.claude)
#   AGENTS_REPO  source repo root (default: dir containing this script)
#   CLAUDE_BIN   claude binary used by `review` (default: claude)
#
# Exit codes: 0 ok, 1 check/operation failure, 2 usage error.

set -euo pipefail

# --- environment ------------------------------------------------------------

SELF="${BASH_SOURCE[0]}"
while [[ -L "$SELF" ]]; do SELF="$(readlink "$SELF")"; done
AGENTS_REPO="${AGENTS_REPO:-$(cd "$(dirname "$SELF")" && pwd)}"
AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"

# --- option globals (set by parse_args) -------------------------------------

SUBCMD=""
NAMES=()
AGENTS_ONLY=0
SKILLS_ONLY=0
FORCE=0
DRY_RUN=0
STRICT=0
JSON=0
WRITE_PROMPT=0
FIX=0
MODEL=""
TARGETS=()
CHECK_FAILS=0
CHECK_WARNS=0

# Genericity lint: hardcoded build/test/ci commands or repo-specific tokens that should be
# routed through resources/detect-project.sh. Matches command-like usage, not bare ecosystem
# names used as cross-ecosystem examples (e.g. "Cargo.toml" or "do not hardcode cargo").
GENERICITY_RE='(make ci|origin/master|cached_proc_macro|cargo (build|test|run|check|clippy|doc|readme|fmt|bench))'

# Recursive JSON merge used by `config apply`: backup (.[1]) merged ONTO live (.[0]).
# Objects merge key-by-key, arrays union (so live-only permission entries survive), and
# scalars take the backup value. Live-only keys are preserved.
JQ_DEEPMERGE='
def deepmerge($a; $b):
  if ($a|type)=="object" and ($b|type)=="object"
  then reduce ($b|keys_unsorted[]) as $k ($a; .[$k] = deepmerge($a[$k]; $b[$k]))
  elif ($a|type)=="array" and ($b|type)=="array"
  then ($a + $b | unique)
  else $b end;
deepmerge(.[0]; .[1])'

usage() {
    cat <<'EOF'
usage: x <command> [NAME ...] [options]

commands:
  install    copy items to $AGENTS_HOME and symlink into $CLAUDE_HOME
  uninstall  remove the symlinks and copies for items
  status     show per-item state (not-installed/up-to-date/needs-upgrade/drift)
  check      lint agent + skill files and their resources
  review     run an opus critique of one agent or skill (--fix applies the suggestions)
  config     sync config/ backups with live $CLAUDE_HOME (config diff|apply|pull)
  help       show this message

options:
  --agents-only | --skills-only   limit install/uninstall to one kind
  --force                         reinstall even if up-to-date; clobber real files
  --dry-run                       print planned actions, change nothing
  --strict                        check: treat warnings (e.g. genericity) as failures
  --json                          status: machine-readable output
  --model ID                      review: model id (default: opus)
  --fix                           review: apply the suggested fixes in place (edits files)
  --write-prompt                  review: print the assembled prompt, do not call claude

NAME: bare name, agent:<name>, skill:<name>, or resources (default: all items)
EOF
}

die() { echo "x: $1" >&2; exit "${2:-1}"; }

# Show the directories an operation reads from / writes to, for context.
context_banner() {
    echo "repo:        $AGENTS_REPO"
    echo "agents-home: $AGENTS_HOME"
    echo "claude-home: $CLAUDE_HOME"
    echo "---"
}

# --- hashing ----------------------------------------------------------------

hash_file() { sha256sum "$1" | cut -d' ' -f1; }

# Directory manifest hash: per-file mode marker + content hash + relpath, ordered
# by relpath, hashed together. Catches added/removed/renamed files and lost +x bits.
hash_dir() {
    local dir="$1"
    ( cd "$dir" && find . -type f -printf '%P\n' | LC_ALL=C sort | while IFS= read -r rel; do
        local mode='-'
        if [[ -x "$rel" ]]; then mode='x'; fi
        printf '%s %s  %s\n' "$mode" "$(hash_file "$rel")" "$rel"
      done ) | sha256sum | cut -d' ' -f1
}

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# --- discovery --------------------------------------------------------------

list_agents() {
    local f
    shopt -s nullglob
    for f in "$AGENTS_REPO"/agents/*.md; do basename "$f" .md; done
    shopt -u nullglob
}

list_skills() {
    local d
    shopt -s nullglob
    for d in "$AGENTS_REPO"/skills/*/; do
        [[ -f "${d}SKILL.md" ]] && basename "$d"
    done
    shopt -u nullglob
}

agent_exists() { [[ -f "$AGENTS_REPO/agents/$1.md" ]]; }
skill_exists() { [[ -f "$AGENTS_REPO/skills/$1/SKILL.md" ]]; }

all_ids() {
    local n
    for n in $(list_agents); do echo "agent:$n"; done
    for n in $(list_skills); do echo "skill:$n"; done
    [[ -d "$AGENTS_REPO/resources" ]] && echo "shared:resources"
}

# Populate TARGETS from NAMES (or everything when NAMES is empty).
resolve_targets() {
    TARGETS=()
    if [[ ${#NAMES[@]} -eq 0 ]]; then
        local n
        if [[ $SKILLS_ONLY -eq 0 ]]; then
            for n in $(list_agents); do TARGETS+=("agent:$n"); done
        fi
        if [[ $AGENTS_ONLY -eq 0 ]]; then
            for n in $(list_skills); do TARGETS+=("skill:$n"); done
        fi
        if [[ $AGENTS_ONLY -eq 0 && $SKILLS_ONLY -eq 0 && -d "$AGENTS_REPO/resources" ]]; then
            TARGETS+=("shared:resources")
        fi
        return
    fi
    local name matched
    for name in "${NAMES[@]}"; do
        case "$name" in
            agent:*) agent_exists "${name#agent:}" || die "no such agent: ${name#agent:}" 2; TARGETS+=("$name") ;;
            skill:*) skill_exists "${name#skill:}" || die "no such skill: ${name#skill:}" 2; TARGETS+=("$name") ;;
            shared:resources|shared|resources)
                [[ -d "$AGENTS_REPO/resources" ]] || die "no shared resources dir" 2
                TARGETS+=("shared:resources") ;;
            *)
                matched=0
                if agent_exists "$name"; then TARGETS+=("agent:$name"); matched=1; fi
                if skill_exists "$name"; then TARGETS+=("skill:$name"); matched=1; fi
                [[ $matched -eq 1 ]] || die "unknown item '$name'; valid ids:"$'\n'"$(all_ids)" 2
                ;;
        esac
    done
}

# --- path mapping -----------------------------------------------------------

id_type() { printf '%s' "${1%%:*}"; }
id_name() { printf '%s' "${1#*:}"; }

src_path() {
    case "$(id_type "$1")" in
        agent) printf '%s' "$AGENTS_REPO/agents/$(id_name "$1").md" ;;
        skill) printf '%s' "$AGENTS_REPO/skills/$(id_name "$1")" ;;
        shared) printf '%s' "$AGENTS_REPO/resources" ;;
    esac
}
dest_path() {
    case "$(id_type "$1")" in
        agent) printf '%s' "$AGENTS_HOME/agents/$(id_name "$1").md" ;;
        skill) printf '%s' "$AGENTS_HOME/skills/$(id_name "$1")" ;;
        shared) printf '%s' "$AGENTS_HOME/resources" ;;
    esac
}
# Empty for shared (no symlink class).
link_path() {
    case "$(id_type "$1")" in
        agent) printf '%s' "$CLAUDE_HOME/agents/$(id_name "$1").md" ;;
        skill) printf '%s' "$CLAUDE_HOME/skills/$(id_name "$1")" ;;
        shared) printf '' ;;
    esac
}

repo_hash() {
    if [[ "$(id_type "$1")" == "agent" ]]; then hash_file "$(src_path "$1")"; else hash_dir "$(src_path "$1")"; fi
}
disk_hash() {
    local dest; dest="$(dest_path "$1")"
    if [[ "$(id_type "$1")" == "agent" ]]; then
        if [[ -f "$dest" ]]; then hash_file "$dest"; else printf ''; fi
    else
        if [[ -d "$dest" ]]; then hash_dir "$dest"; else printf ''; fi
    fi
}

link_ok() {
    local lp; lp="$(link_path "$1")"
    [[ -z "$lp" ]] && return 0
    [[ -L "$lp" ]] || return 1
    [[ "$(readlink "$lp")" == "$(dest_path "$1")" ]]
}

# --- manifest ---------------------------------------------------------------

manifest_file() { printf '%s' "$AGENTS_HOME/manifest.json"; }

manifest_ensure() {
    local mf; mf="$(manifest_file)"
    if [[ ! -f "$mf" ]]; then
        mkdir -p "$AGENTS_HOME"
        echo '{"version":1,"items":{}}' > "$mf"
    fi
}

manifest_hash() {
    local mf; mf="$(manifest_file)"
    [[ -f "$mf" ]] || { printf ''; return 0; }
    jq -r --arg k "$1" '.items[$k].hash // ""' "$mf"
}

files_json() {
    local src; src="$(src_path "$1")"
    if [[ "$(id_type "$1")" == "agent" ]]; then
        printf '%s' "[\"$(id_name "$1").md\"]"
    else
        ( cd "$src" && find . -type f -printf '%P\n' | LC_ALL=C sort ) | jq -R . | jq -s -c .
    fi
}

manifest_set() {
    manifest_ensure
    local mf tmp; mf="$(manifest_file)"; tmp="$mf.tmp.$$"
    jq --arg k "$1" --arg t "$2" --arg h "$3" --argjson f "$4" --arg ts "$(now)" \
        '.items[$k] = {type:$t, hash:$h, installed_at:$ts, files:$f}' "$mf" > "$tmp"
    mv "$tmp" "$mf"
}

manifest_del() {
    local mf; mf="$(manifest_file)"
    [[ -f "$mf" ]] || return 0
    local tmp="$mf.tmp.$$"
    jq --arg k "$1" 'del(.items[$k])' "$mf" > "$tmp"
    mv "$tmp" "$mf"
}

# --- install / uninstall ----------------------------------------------------

install_one() {
    local id="$1" type name dest lp src h_repo h_inst h_disk
    type="$(id_type "$id")"; name="$(id_name "$id")"
    dest="$(dest_path "$id")"; lp="$(link_path "$id")"; src="$(src_path "$id")"
    h_repo="$(repo_hash "$id")"; h_inst="$(manifest_hash "$id")"; h_disk="$(disk_hash "$id")"

    if [[ $FORCE -eq 0 && -n "$h_disk" && "$h_repo" == "$h_inst" && "$h_inst" == "$h_disk" ]] && link_ok "$id"; then
        echo "skip      $id (up-to-date)"
        return 0
    fi

    if [[ -n "$lp" && -e "$lp" && ! -L "$lp" && $FORCE -eq 0 ]]; then
        echo "skip      $id (refusing to clobber real file at $lp; use --force)" >&2
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "install   $id -> $dest${lp:+  symlink $lp}"
        return 0
    fi

    case "$type" in
        agent)
            mkdir -p "$(dirname "$dest")"
            cp -p "$src" "$dest"
            ;;
        skill|shared)
            mkdir -p "$(dirname "$dest")"
            rm -rf "$dest"
            cp -Rp "$src" "$dest"
            ;;
    esac
    if [[ -n "$lp" ]]; then
        mkdir -p "$(dirname "$lp")"
        ln -sfn "$dest" "$lp"
    fi
    manifest_set "$id" "$type" "$h_repo" "$(files_json "$id")"
    echo "install   $id"
}

uninstall_one() {
    local id="$1" lp dest
    lp="$(link_path "$id")"; dest="$(dest_path "$id")"

    if [[ $DRY_RUN -eq 1 ]]; then
        echo "uninstall $id"
        return 0
    fi

    # Remove the symlink only if it is a symlink pointing into AGENTS_HOME.
    if [[ -n "$lp" && -L "$lp" ]]; then
        local tgt; tgt="$(readlink "$lp")"
        if [[ "$tgt" == "$AGENTS_HOME"/* ]]; then rm -f "$lp"; fi
    fi
    if [[ "$(id_type "$id")" == "agent" ]]; then rm -f "$dest"; else rm -rf "$dest"; fi
    manifest_del "$id"
    echo "uninstall $id"
}

# --- status -----------------------------------------------------------------

status_state() {
    local id="$1" h_repo h_inst h_disk
    h_repo="$(repo_hash "$id")"; h_inst="$(manifest_hash "$id")"; h_disk="$(disk_hash "$id")"
    if [[ -z "$h_inst" && -z "$h_disk" ]]; then echo "not-installed"
    elif [[ -z "$h_inst" ]]; then echo "drift"
    elif [[ "$h_repo" != "$h_inst" ]]; then echo "needs-upgrade"
    elif [[ "$h_inst" != "$h_disk" ]] || ! link_ok "$id"; then echo "drift"
    else echo "up-to-date"; fi
}

cmd_status() {
    resolve_targets
    if [[ $JSON -eq 0 ]]; then context_banner; fi
    if [[ $JSON -eq 1 ]]; then
        local id objs=()
        for id in "${TARGETS[@]}"; do
            objs+=("$(jq -nc --arg id "$id" --arg type "$(id_type "$id")" --arg name "$(id_name "$id")" \
                --arg state "$(status_state "$id")" --arg repo "$(repo_hash "$id")" --arg installed "$(manifest_hash "$id")" \
                '{id:$id,type:$type,name:$name,state:$state,repo:$repo,installed:$installed}')")
        done
        printf '%s\n' "${objs[@]}" | jq -s .
        return 0
    fi
    printf '%-9s %-32s %-13s %s\n' "TYPE" "NAME" "STATE" "REPO/INSTALLED"
    local id
    for id in "${TARGETS[@]}"; do
        local repo inst
        repo="$(repo_hash "$id")"; inst="$(manifest_hash "$id")"
        printf '%-9s %-32s %-13s %s\n' "$(id_type "$id")" "$(id_name "$id")" "$(status_state "$id")" \
            "${repo:0:8}/${inst:0:8}"
    done
}

# --- check ------------------------------------------------------------------

has_frontmatter() {
    local first; IFS= read -r first < "$1" || return 1
    [[ "$first" == "---" ]] || return 1
    awk 'NR>1 && $0=="---"{found=1} END{exit found?0:1}' "$1"
}

fm_field() {
    awk -v key="$2" '
        NR==1 && $0=="---"{f=1; next}
        f && $0=="---"{exit}
        f { if (match($0, "^"key"[ \t]*:[ \t]*")) { print substr($0, RLENGTH+1); exit } }
    ' "$1"
}

body_after_fm() {
    awk 'NR==1 && $0=="---"{f=1; next} f && $0=="---"{f=0; b=1; next} b{print}' "$1"
}

py_syntax() { python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$1"; }

# report ID PROBLEMS_ARRAYNAME WARNS_ARRAYNAME
report() {
    local id="$1"; local -n _probs="$2"; local -n _warns="$3"
    if [[ $STRICT -eq 1 && ${#_warns[@]} -gt 0 ]]; then
        _probs+=("${_warns[@]}")
        _warns=()
    fi
    if [[ ${#_probs[@]} -eq 0 && ${#_warns[@]} -eq 0 ]]; then
        echo "OK   $id"
        return 0
    fi
    local p
    for p in "${_probs[@]}"; do echo "FAIL $id: $p"; CHECK_FAILS=$((CHECK_FAILS+1)); done
    for p in "${_warns[@]}"; do echo "WARN $id: $p"; CHECK_WARNS=$((CHECK_WARNS+1)); done
}

check_resources_dir() {
    # $1 = resources dir, $2 = problems array name (nameref)
    local rdir="$1"; local -n _p="$2"
    [[ -d "$rdir" ]] || return 0
    local rf rel firstline
    while IFS= read -r rf; do
        rel="${rf#"$AGENTS_REPO"/}"
        firstline=""
        IFS= read -r firstline < "$rf" || true
        local has_shebang=0 is_exec=0
        if [[ "$firstline" == '#!'* ]]; then has_shebang=1; fi
        if [[ -x "$rf" ]]; then is_exec=1; fi
        if [[ $has_shebang -eq 1 && $is_exec -eq 0 ]]; then _p+=("$rel: has shebang but not executable"); fi
        if [[ $is_exec -eq 1 && $has_shebang -eq 0 ]]; then _p+=("$rel: executable but no shebang"); fi
        case "$rf" in
            *.sh) bash -n "$rf" 2>/dev/null || _p+=("$rel: failed bash -n") ;;
            *.py) py_syntax "$rf" 2>/dev/null || _p+=("$rel: failed python syntax check") ;;
        esac
    done < <(find "$rdir" -type f | LC_ALL=C sort)
}

check_agent() {
    local name="$1" file="$AGENTS_REPO/agents/$1.md"
    local -a problems=() warns=()
    if ! has_frontmatter "$file"; then problems+=("missing or unclosed frontmatter"); fi
    local nm; nm="$(fm_field "$file" name)"
    if [[ -z "$nm" ]]; then problems+=("frontmatter: empty name"); fi
    if [[ -n "$nm" && "$nm" != "$name" ]]; then problems+=("frontmatter name '$nm' != filename '$name'"); fi
    local k
    for k in model tools description; do
        if [[ -z "$(fm_field "$file" "$k")" ]]; then problems+=("frontmatter: empty $k"); fi
    done
    local mdl; mdl="$(fm_field "$file" model)"
    case "$mdl" in sonnet|opus|haiku|inherit|"") ;; *) warns+=("unusual model '$mdl'") ;; esac
    # A typo'd permissionMode is silently ignored by the harness, which would let a
    # spawned agent fall back to interactive prompts and stall a handoff. Pin it.
    local pm; pm="$(fm_field "$file" permissionMode)"
    case "$pm" in default|acceptEdits|auto|dontAsk|bypassPermissions|plan|"") ;; *) problems+=("invalid permissionMode '$pm'") ;; esac
    if [[ -z "$(body_after_fm "$file" | tr -d '[:space:]')" ]]; then problems+=("empty body"); fi
    if grep -qiE "$GENERICITY_RE" "$file"; then
        warns+=("hardcoded project-specific command(s) - route through detect-project.sh")
    fi
    report "agent:$name" problems warns
}

check_skill() {
    local name="$1" dir="$AGENTS_REPO/skills/$1" sf="$AGENTS_REPO/skills/$1/SKILL.md"
    local -a problems=() warns=()
    if ! has_frontmatter "$sf"; then problems+=("SKILL.md missing or unclosed frontmatter"); fi
    local nm; nm="$(fm_field "$sf" name)"
    if [[ -z "$nm" ]]; then problems+=("empty name"); fi
    if [[ -n "$nm" && "$nm" != "$name" ]]; then problems+=("name '$nm' != dir '$name'"); fi
    if [[ -z "$(fm_field "$sf" description)" ]]; then problems+=("empty description"); fi
    check_resources_dir "$dir/resources" problems
    # SKILL.md resource references must exist (in this skill or in shared resources/)
    local ref
    while IFS= read -r ref; do
        [[ -n "$ref" ]] || continue
        while [[ "$ref" == *. ]]; do ref="${ref%.}"; done   # drop trailing prose punctuation
        if [[ ! -e "$dir/$ref" && ! -e "$AGENTS_REPO/$ref" ]]; then problems+=("SKILL.md references missing $ref"); fi
    done < <(grep -oE 'resources/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*' "$sf" 2>/dev/null | LC_ALL=C sort -u || true)
    if grep -qiE "$GENERICITY_RE" "$sf"; then
        warns+=("hardcoded project-specific command(s) - route through detect-project.sh")
    fi
    report "skill:$name" problems warns
}

check_shared() {
    local -a problems=() warns=()
    check_resources_dir "$AGENTS_REPO/resources" problems
    report "shared:resources" problems warns
}

# Cross-agent audit: every agent should declare a color, and colors must be distinct.
# Runs only on a full check (no explicit NAME), since it is a global invariant.
audit_agent_colors() {
    local n color
    local -A seen=()
    for n in $(list_agents); do
        color="$(fm_field "$AGENTS_REPO/agents/$n.md" color)"
        if [[ -z "$color" ]]; then
            echo "WARN agent:$n: no color set"; CHECK_WARNS=$((CHECK_WARNS+1)); continue
        fi
        if [[ -n "${seen[$color]:-}" ]]; then
            echo "FAIL agent:$n: color '$color' already used by agent:${seen[$color]}"
            CHECK_FAILS=$((CHECK_FAILS+1))
        else
            seen[$color]="$n"
        fi
    done
}

cmd_check() {
    resolve_targets
    CHECK_FAILS=0; CHECK_WARNS=0
    local id
    for id in "${TARGETS[@]}"; do
        case "$(id_type "$id")" in
            agent) check_agent "$(id_name "$id")" ;;
            skill) check_skill "$(id_name "$id")" ;;
            shared) check_shared ;;
        esac
    done
    [[ ${#NAMES[@]} -eq 0 ]] && audit_agent_colors
    echo "---"
    echo "check: $CHECK_FAILS failure(s), $CHECK_WARNS warning(s)"
    [[ $CHECK_FAILS -eq 0 ]]
}

# --- config -----------------------------------------------------------------
# Sync the repo's config/ backups (the user's personal ~/.claude files) with the
# live $CLAUDE_HOME. JSON files are merged (preserving live-only keys); other files
# (e.g. CLAUDE.md) are overwritten. A timestamped-free `.bak` of the prior live file
# is kept on every change.

config_files() {
    local f
    shopt -s nullglob
    for f in "$AGENTS_REPO"/config/*; do
        [[ -f "$f" ]] && basename "$f"
    done
    shopt -u nullglob
}

config_apply_one() {
    local name="$1" src="$AGENTS_REPO/config/$1" dst="$CLAUDE_HOME/$1"
    mkdir -p "$CLAUDE_HOME"
    case "$name" in
        *.json)
            if [[ ! -f "$dst" ]]; then cp -p "$src" "$dst"; echo "create   $name (no live file)"; return 0; fi
            local tmp="$dst.tmp.$$"
            jq -s "$JQ_DEEPMERGE" "$dst" "$src" > "$tmp" || { rm -f "$tmp"; die "jq merge failed for $name" 1; }
            if jq -e --slurpfile cur "$dst" '. == $cur[0]' "$tmp" >/dev/null; then
                rm -f "$tmp"; echo "ok       $name (already up-to-date)"; return 0
            fi
            cp -p "$dst" "$dst.bak"; mv "$tmp" "$dst"
            echo "merge    $name -> live (backup: $name.bak)"
            ;;
        *)
            if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then echo "ok       $name (already up-to-date)"; return 0; fi
            [[ -f "$dst" ]] && cp -p "$dst" "$dst.bak"
            cp -p "$src" "$dst"
            echo "apply    $name -> live${dst:+}"
            ;;
    esac
}

config_diff_one() {
    local name="$1" src="$AGENTS_REPO/config/$1" dst="$CLAUDE_HOME/$1"
    if [[ ! -f "$dst" ]]; then echo "[create] $name (no live file yet)"; return 0; fi
    case "$name" in
        *.json)
            local merged; merged="$(jq -s "$JQ_DEEPMERGE" "$dst" "$src")"
            if diff -q <(jq -S . "$dst") <(printf '%s' "$merged" | jq -S .) >/dev/null; then
                echo "[ok]     $name (apply would change nothing)"
            else
                echo "[change] $name (apply would merge in):"
                diff <(jq -S . "$dst") <(printf '%s' "$merged" | jq -S .) | sed 's/^/    /' || true
            fi
            ;;
        *)
            if cmp -s "$src" "$dst"; then echo "[ok]     $name (identical)"
            else echo "[change] $name (apply would overwrite live):"; diff "$dst" "$src" | sed 's/^/    /' || true; fi
            ;;
    esac
}

config_pull_one() {
    local name="$1" src="$CLAUDE_HOME/$1" dst="$AGENTS_REPO/config/$1"
    if [[ ! -f "$src" ]]; then echo "skip     $name (no live file to pull)"; return 0; fi
    if cmp -s "$src" "$dst"; then echo "ok       $name (backup current)"; return 0; fi
    cp -p "$src" "$dst"; echo "pull     $name (live -> config/)"
}

cmd_config() {
    [[ -d "$AGENTS_REPO/config" ]] || die "no config/ directory in $AGENTS_REPO" 1
    local action="${NAMES[0]:-diff}"
    echo "config-dir:  $AGENTS_REPO/config"
    echo "claude-home: $CLAUDE_HOME"
    echo "---"
    local name
    case "$action" in
        diff)  for name in $(config_files); do config_diff_one "$name"; done ;;
        apply) for name in $(config_files); do config_apply_one "$name"; done ;;
        pull)  for name in $(config_files); do config_pull_one "$name"; done ;;
        *) die "unknown config action '$action' (use: diff, apply, pull)" 2 ;;
    esac
}

# --- review -----------------------------------------------------------------

cmd_review() {
    [[ ${#NAMES[@]} -eq 1 ]] || die "review needs exactly one item NAME (e.g. 'x review skill:review'); run 'x status' to list ids" 2
    resolve_targets
    [[ ${#TARGETS[@]} -eq 1 ]] || die "'${NAMES[0]}' is ambiguous (matches ${#TARGETS[@]} items); qualify it as agent:NAME or skill:NAME" 2
    local id="${TARGETS[0]}" type name
    type="$(id_type "$id")"; name="$(id_name "$id")"
    local prompt_file="$AGENTS_REPO/resources/reviewer-prompt.md"
    [[ -f "$prompt_file" ]] || die "missing reviewer prompt: $prompt_file" 1

    local -a files=()
    case "$type" in
        agent) files=("$AGENTS_REPO/agents/$name.md") ;;
        skill)
            files=("$AGENTS_REPO/skills/$name/SKILL.md")
            if [[ -d "$AGENTS_REPO/skills/$name/resources" ]]; then
                while IFS= read -r f; do files+=("$f"); done \
                    < <(find "$AGENTS_REPO/skills/$name/resources" -type f | LC_ALL=C sort)
            fi ;;
        shared)
            while IFS= read -r f; do files+=("$f"); done \
                < <(find "$AGENTS_REPO/resources" -type f | LC_ALL=C sort) ;;
    esac

    # Mode header (first line of the prompt) tells claude review-only vs review-and-fix.
    local mode_header
    if [[ $FIX -eq 1 ]]; then
        mode_header="MODE: REVIEW-AND-FIX - find the issues per the rubric, then APPLY the fixes by editing the listed files in place (your working directory is the repo root), then summarize what you changed."
    else
        mode_header="MODE: REVIEW-ONLY - produce the prioritized critique; edit nothing."
    fi

    local prompt; prompt="$mode_header"$'\n\n'"$(cat "$prompt_file")"$'\n'
    local f rel
    for f in "${files[@]}"; do
        rel="${f#"$AGENTS_REPO"/}"
        prompt+=$'\n--- '"$rel"$' ---\n'"$(cat "$f")"$'\n'
    done

    if [[ $WRITE_PROMPT -eq 1 ]]; then
        printf '%s\n' "$prompt"
        return 0
    fi
    local model="${MODEL:-opus}"
    # Progress to stderr so stdout stays the pure output (pipeable). The call blocks
    # while claude runs, which can take ~30-60s with no intermediate output.
    # Redirect stdin from /dev/null: claude --print otherwise blocks ~3s waiting for
    # piped stdin (and warns), since we pass the prompt as an argument, not on stdin.
    if [[ $FIX -eq 1 ]]; then
        printf 'x review --fix: reviewing AND fixing %s with %s (calling %s; edits files in place)...\n' \
            "$id" "$model" "$CLAUDE_BIN" >&2
        # Run from the repo root with edit permission so claude can apply fixes in place.
        ( cd "$AGENTS_REPO" && "$CLAUDE_BIN" --model "$model" --permission-mode acceptEdits --print "$prompt" </dev/null )
    else
        printf 'x review: critiquing %s with %s (calling %s; this can take ~30-60s)...\n' \
            "$id" "$model" "$CLAUDE_BIN" >&2
        "$CLAUDE_BIN" --model "$model" --print "$prompt" </dev/null
    fi
}

# --- argument parsing -------------------------------------------------------

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            install|uninstall|status|check|review|config)
                if [[ -z "$SUBCMD" ]]; then SUBCMD="$1"; else NAMES+=("$1"); fi ;;
            help|-h|--help) SUBCMD="help" ;;
            --agents-only) AGENTS_ONLY=1 ;;
            --skills-only) SKILLS_ONLY=1 ;;
            --force) FORCE=1 ;;
            --dry-run) DRY_RUN=1 ;;
            --strict) STRICT=1 ;;
            --json) JSON=1 ;;
            --write-prompt) WRITE_PROMPT=1 ;;
            --fix) FIX=1 ;;
            --model) [[ $# -ge 2 ]] || die "--model needs an argument" 2; MODEL="$2"; shift ;;
            --model=*) MODEL="${1#--model=}" ;;
            --) ;;
            --*) die "unknown flag: $1" 2 ;;
            *) NAMES+=("$1") ;;
        esac
        shift
    done
}

main() {
    parse_args "$@"
    case "$SUBCMD" in
        "") usage; exit 2 ;;
        help) usage; exit 0 ;;
        install)   resolve_targets; context_banner; local rc=0; for id in "${TARGETS[@]}"; do install_one "$id" || rc=1; done; exit $rc ;;
        uninstall) resolve_targets; context_banner; for id in "${TARGETS[@]}"; do uninstall_one "$id"; done ;;
        status)    cmd_status ;;
        check)     cmd_check ;;
        review)    cmd_review ;;
        config)    cmd_config ;;
        *) die "unknown command: $SUBCMD" 2 ;;
    esac
}

main "$@"
