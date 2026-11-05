# shellcheck shell=bash
# Module discovery, validation and dependency order. Sourced by ./kit after config.sh.
#
# A module is a folder with a module.conf, in the repo's modules/ or in ~/server/local-modules/
# (same layout). module.conf keys:
#   DESCRIPTION       one line, shown by ./kit status
#   KIND              base (always enabled) | optional (enabled with ./kit add); local modules are optional
#   PROJECT           compose project the module belongs to (empty: no containers)
#   REQUIRES          modules that must all be enabled
#   REQUIRES_ONE_OF   at least one of these must be enabled
#   TS_NODES          Tailscale node ids the module owns
#   BACKUP_ORDER      order for backup-all and update-all (lower first)
#   NATIVE_HEALTH     native apps check-health watches: name|port|path|fail or warn|how to start|
#                     extra logs, several separated by ";" (see modules/health/bin/check-health)
#   (hints file: service|text lines, shown when that service fails to start)
#   (bin/: runtime scripts for ~/server/bin; jobs: launchd jobs; see lib/runtime.sh)
#   (homarr-widget.json and .jsx: a Homarr custom widget; see lib/homarr.sh)

KIT_MODULES_DIR=${KIT_MODULES_DIR:-$KIT_DIR/modules}
LOCAL_MODULES_DIR=$SERVER_DIR/local-modules
ENABLED_FILE=$KIT_STATE/enabled

MODULES_ALL=''      # every discovered module, repo first, then local
MODULE_NAME_RE='^[a-z0-9][a-z0-9-]*$'

mod_var() { printf 'KIT_MODDIR_%s' "${1//-/_}"; }

mod_dir() {         # name -> module folder
    local v
    v=$(mod_var "$1")
    [ -n "${!v:-}" ] || die "unknown module: $1"
    printf '%s' "${!v}"
}

mod_exists() { local v; v=$(mod_var "$1"); [ -n "${!v:-}" ]; }

mod_conf() {        # name key -> value ("" when unset)
    kv_get "$(mod_dir "$1")/module.conf" "$2" || true
}

modules_discover() {
    local root dir name kind v errors='' source
    for name in $MODULES_ALL; do unset "$(mod_var "$name")"; done     # safe to call again
    MODULES_ALL=''
    for root in "$KIT_MODULES_DIR" "$LOCAL_MODULES_DIR"; do
        [ -d "$root" ] || continue
        source=repo
        [ "$root" = "$LOCAL_MODULES_DIR" ] && source=local
        for dir in "$root"/*/; do
            [ -f "$dir/module.conf" ] || continue
            dir=${dir%/}
            name=$(basename "$dir")
            if ! [[ $name =~ $MODULE_NAME_RE ]]; then
                errors="$errors
$(tilde "$dir"): module names are lowercase letters, digits and dashes"
                continue
            fi
            if mod_exists "$name"; then
                errors="$errors
$(tilde "$dir"): a module named $name already exists in $(tilde "$(mod_dir "$name")")"
                continue
            fi
            kind=$(kv_get "$dir/module.conf" KIND || true)
            case "$source:$kind" in
                repo:base|repo:optional|local:optional) ;;
                local:base)
                    errors="$errors
$(tilde "$dir"): local modules must be KIND=optional"
                    continue ;;
                *)
                    errors="$errors
$(tilde "$dir")/module.conf: KIND must be base or optional"
                    continue ;;
            esac
            v=$(mod_var "$name")
            printf -v "$v" '%s' "$dir"
            MODULES_ALL=$(list_add "$MODULES_ALL" "$name")
        done
    done
    if [ -n "$errors" ]; then
        printf '%s\n' "$errors" | sed '/^$/d' | while IFS= read -r line; do err "$line"; done
        die "fix the module folders above"
    fi
    [ -n "$MODULES_ALL" ] || die "no modules found in $KIT_MODULES_DIR"
}

modules_base() {    # -> base modules, in discovery order
    local m out=''
    for m in $MODULES_ALL; do
        [ "$(mod_conf "$m" KIND)" = base ] && out=$(list_add "$out" "$m")
    done
    printf '%s' "$out"
}

media_server_modules() {
    case "$(answer MEDIA_SERVER)" in
        plex) printf 'plex' ;;
        jellyfin) printf 'jellyfin' ;;
        both) printf 'plex jellyfin' ;;
    esac
}

modules_requested() {   # -> base + media server choice + MODULES=, deduplicated
    local m out
    out=$(modules_base)
    for m in $(media_server_modules) $(answer MODULES || true); do
        out=$(list_add "$out" "$m")
    done
    printf '%s' "$out"
}

# Check the requested set and print it in dependency order (a module after everything it needs).
# Prints every problem before failing.
modules_resolve() {     # [modules...] (default: modules_requested)
    local set m r deps any found remaining next out='' progressed errors=''
    set=${*:-$(modules_requested)}
    for m in $set; do
        if ! mod_exists "$m"; then
            errors="$errors
unknown module: $m"
            continue
        fi
        for r in $(mod_conf "$m" REQUIRES); do
            in_list "$r" "$set" || errors="$errors
$m requires $r (./kit add $r)"
        done
        any=$(mod_conf "$m" REQUIRES_ONE_OF)
        if [ -n "$any" ]; then
            found=0
            for r in $any; do in_list "$r" "$set" && found=1; done
            [ $found = 1 ] || errors="$errors
$m requires one of: $any"
        fi
    done
    if [ -n "$errors" ]; then
        printf '%s\n' "$errors" | sed '/^$/d' | while IFS= read -r line; do err "$line"; done
        return 1
    fi

    remaining=$set
    while [ -n "$remaining" ]; do
        next=''
        progressed=0
        for m in $remaining; do
            deps=$(mod_conf "$m" REQUIRES)
            for r in $(mod_conf "$m" REQUIRES_ONE_OF); do
                in_list "$r" "$set" && deps="$deps $r"
            done
            found=1
            for r in $deps; do in_list "$r" "$out" || found=0; done
            if [ $found = 1 ]; then
                out=$(list_add "$out" "$m")
                progressed=1
            else
                next=$(list_add "$next" "$m")
            fi
        done
        if [ $progressed = 0 ]; then
            err "dependency cycle among: $next"
            return 1
        fi
        remaining=$next
    done
    printf '%s' "$out"
}

write_enabled() {   # modules... -> ~/server/kit/enabled, one per line, in dependency order
    {
        echo "# Generated by ./kit install: enabled modules in dependency order. Do not edit."
        for m in "$@"; do echo "$m"; done
    } | write_generated "$ENABLED_FILE"
}

read_enabled() {    # -> the modules in ~/server/kit/enabled, space-separated
    [ -f "$ENABLED_FILE" ] || return 1
    grep -v '^#' "$ENABLED_FILE" | grep -v '^$' | tr '\n' ' ' | sed 's/ $//'
}

by_backup_order() { # modules... -> the same modules sorted by BACKUP_ORDER (stable; unset = 50)
    local m o i=0
    for m in "$@"; do
        i=$((i + 1))
        o=$(mod_conf "$m" BACKUP_ORDER)
        printf '%s %04d %s\n' "${o:-50}" "$i" "$m"
    done | sort -n -k1,1 -k2,2 | awk '{ print $3 }' | tr '\n' ' ' | sed 's/ $//'
}
