# shellcheck shell=bash
# shellcheck disable=SC2034  # settings for the scripts that source this file
# Shared by the kit's runtime scripts in ~/server/bin (backup-*, restore-*, update-*,
# copy-backups): paths, runtime.conf, logging, maintenance windows, image pins and release tags.
# Sourced, not run. Installed by mac-server-kit; ./kit install replaces it. ./kit install sources
# it from the repo too, for the release-tag lookup (one copy of that code).

export PATH="${KIT_TEST_PATH:+$KIT_TEST_PATH:}$HOME/.orbstack/bin:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
SERVER="${KIT_SERVER_DIR:-$HOME/server}"
BIN="$SERVER/bin"
BACKUPS="$SERVER/backups"
MAINT_FILE="$SERVER/logs/health/.maintenance"

# Filled in by runtime.conf (see lib/runtime.sh)
PROJECTS=""
BACKUP_PROJECTS=""
BACKUP_DRIVE=""
KEEP=8
EXTERNAL_KEEP=26
NATIVE_MODULES=""
APPS_DIR=/Applications
JOB_PREFIX=io.github.andy327.mac-server-kit.
# shellcheck disable=SC1091
[ -f "$SERVER/kit/runtime.conf" ] && . "$SERVER/kit/runtime.conf"

ME=${ME:-$(basename "$0")}
log()  { printf '%s  %s\n' "$(date '+%H:%M:%S')" "$*"; }
warn() { printf '%s  WARNING: %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
die()  { printf '%s: %s\n' "$ME" "$*" >&2; exit 1; }

dk() { "${KIT_DOCKER:-docker}" "$@"; }
tilde() { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }

proj_var() { printf '%s_%s' "$1" "${2//-/_}"; }      # PREFIX project -> PREFIX_project_name
proj_setting() { local v; v=$(proj_var "$1" "$2"); printf '%s' "${!v:-}"; }

# ---------------------------------------------------------------- maintenance windows

# Open one unless an unexpired window is open already (then leave that one alone). Sets
# MAINT_OPENED=1 when this script opened it, so maint_end closes only its own.
MAINT_OPENED=0
maint_begin() {     # reason
    local exp
    exp=$(cut -f2 "$MAINT_FILE" 2>/dev/null || true)
    if [[ $exp =~ ^[0-9]+$ ]] && [ "$exp" -gt "$(date +%s)" ]; then
        log "Maintenance window already open; leaving it as is"
        return 0
    fi
    if "$BIN/start-maintenance" "$1" >/dev/null 2>&1; then MAINT_OPENED=1; else warn "couldn't open a maintenance window"; fi
}
maint_end() {
    [ "$MAINT_OPENED" = 1 ] || return 0
    "$BIN/end-maintenance" >/dev/null 2>&1 || true
    MAINT_OPENED=0
}

# ---------------------------------------------------------------- backups

keep_newest() {     # folder name-prefix count: remove all but the newest <prefix>-<date> folders
    local d
    # shellcheck disable=SC2012  # the kit's own folder names
    ls -1d "$1/$2"-[0-9]* 2>/dev/null | sort -r | tail -n +"$(($3 + 1))" | while IFS= read -r d; do
        log "Removing old backup $(basename "$d")"
        rm -rf "$d"
    done
    return 0
}

newest_backup() {   # folder name-prefix -> the newest <prefix>-<date> folder
    # shellcheck disable=SC2012
    ls -1d "$1/$2"-[0-9]* 2>/dev/null | sort | tail -n 1
}

confirm_restore() { # what -> 0 when the user typed restore (or RESTORE_YES=1)
    [ "${RESTORE_YES:-0}" = 1 ] && return 0
    [ -t 0 ] || die "nothing restored: run it in Terminal to confirm, or set RESTORE_YES=1"
    local a
    read -r -p "Type 'restore' to replace $1: " a
    [ "$a" = restore ]
}

# ---------------------------------------------------------------- image pins
#
# ~/server/<p>/images.lock: "service repo:tag@sha256:... [track]" per line. track is the tag the
# service follows when it differs from the pinned one: a release series like v2.* (the newest
# matching release tag). compose.d/zz-images.yml applies the pins.

lock_pin()   { awk -v s="$2" '$1 == s { p = $2 } END { if (p == "") exit 1; print p }' "$1"; }
lock_track() { awk -v s="$2" '$1 == s { t = $3 } END { print t }' "$1"; }
lock_put() {        # lock service pin [track]
    local tmp
    tmp=$(mktemp "$(dirname "$1")/.kit.XXXXXX") || return 1
    awk -v s="$2" -v p="$3" -v t="${4:-}" '
        function line() { return s " " p (t != "" ? " " t : "") }
        $1 == s { if (!d) print line(); d = 1; next } { print } END { if (!d) print line() }' "$1" >"$tmp" \
        && mv -f "$tmp" "$1" && return 0
    rm -f "$tmp"
    return 1
}

# Rewrite zz-images.yml's image lines from the lock (its services stay as the install chose)
zz_refresh() {      # project-dir
    local zz=$1/compose.d/zz-images.yml tmp
    [ -f "$zz" ] || return 0
    tmp=$(mktemp "$1/compose.d/.kit.XXXXXX") || return 1
    awk 'NR == FNR { pin[$1] = $2; next }
         /^  [a-z0-9][a-z0-9_-]*:$/ { svc = $1; sub(/:$/, "", svc) }
         /^    image: / && (svc in pin) { print "    image: " pin[svc]; next }
         { print }' <(grep -v '^#' "$1/images.lock") "$zz" >"$tmp" && mv -f "$tmp" "$zz" && return 0
    rm -f "$tmp"
    return 1
}

zz_services() { awk '/^  [a-z0-9][a-z0-9_-]*:$/ { s = $1; sub(/:$/, "", s); print s }' "$1/compose.d/zz-images.yml"; }

image_digest() {    # repo:tag (pulled) -> sha256:...
    local line
    line=$(dk image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$1" 2>/dev/null \
        | awk -v r="${1%:*}@" 'NF { if (index($0, r) == 1) { print; f = 1; exit } if (!first) first = $0 }
                                END { if (!f && first) print first }')
    case "$line" in *@sha256:*) printf '%s' "${line#*@}" ;; *) return 1 ;; esac
}

# Release tags (newest_tag), shared with ./kit install
# shellcheck source=kit-registry.sh
. "$(dirname "${BASH_SOURCE[0]}")/kit-registry.sh"

# ---------------------------------------------------------------- native apps

app_path() {        # name -> name.app in APPS_DIR, /Applications or ~/Applications
    local d
    for d in "$APPS_DIR" "${KIT_SYSTEM_APPS:-/Applications}" "$HOME/Applications"; do
        [ -d "$d/$1.app" ] && { printf '%s' "$d/$1.app"; return 0; }
    done
    return 1
}

# Where Glances may be: uv's tool folder, then Homebrew's (Apple Silicon, Intel)
glances_path() {
    local p
    for p in ${KIT_GLANCES_PATHS:-$HOME/.local/bin/glances /opt/homebrew/bin/glances /usr/local/bin/glances}; do
        [ -x "$p" ] && { printf '%s' "$p"; return 0; }
    done
    return 1
}

# Run a native app in the foreground for its launchd job ("always" in a jobs file), which starts
# it again if it crashes. If it's already running, started some other way (its own login item,
# say), watch that one instead of starting a second, and end when it does.
run_app() {         # pgrep-pattern command...
    local pat=$1
    shift
    if pgrep -U "$(id -u)" -f "$pat" >/dev/null 2>&1; then
        log "Already running (started some other way); watching it instead of starting another"
        while pgrep -U "$(id -u)" -f "$pat" >/dev/null 2>&1; do sleep 60; done
        log "It stopped"
        exit 0
    fi
    log "Starting $1"
    exec "$@"
}

job_domain() { printf 'gui/%s' "$(id -u)"; }
job_plist_of() { printf '%s/Library/LaunchAgents/%s%s.plist' "$HOME" "$JOB_PREFIX" "$1"; }
job_stop() {        # name: unload the kit's job (its app stops with it)
    "${KIT_LAUNCHCTL:-launchctl}" bootout "$(job_domain)/$JOB_PREFIX$1" >/dev/null 2>&1 || true
}
job_start() {       # name: load it again (an "always" job starts its app)
    local f
    f=$(job_plist_of "$1")
    [ -f "$f" ] || return 1
    "${KIT_LAUNCHCTL:-launchctl}" bootstrap "$(job_domain)" "$f" >/dev/null 2>&1 ||
        "${KIT_LAUNCHCTL:-launchctl}" kickstart "$(job_domain)/$JOB_PREFIX$1" >/dev/null 2>&1
}
job_restart() { "${KIT_LAUNCHCTL:-launchctl}" kickstart -k "$(job_domain)/$JOB_PREFIX$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- after a start

wait_healthy() {    # project-dir [seconds]: every container running and healthy (or no healthcheck)
    (cd "$1" && dk compose up -d --wait --wait-timeout "${2:-300}") >/dev/null 2>&1
}

after_start() {     # project: the project's own check (AFTER_START_<project> in runtime.conf)
    local cmd
    cmd=$(proj_setting AFTER_START "$1")
    [ -n "$cmd" ] || return 0
    log "Checking: $cmd"
    "$BIN/$cmd"
}
