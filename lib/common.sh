# shellcheck shell=bash
# Output helpers, prompts and key=value files. Sourced by ./kit.
#
# key=value files (answers, secrets, module.conf, ...) are parsed here and never sourced:
#   KEY=value              value runs to the end of the line; " # comment" is dropped
#   KEY="value # kept"     double quotes: everything between the first and the last quote is
#                          the value, taken literally (no escapes, no expansion)
#   # comment              ignored, as are blank lines
# When a key appears more than once, the last line wins.

# Colors only on a terminal, and never with NO_COLOR set (no-color.org) or TERM=dumb
# shellcheck disable=SC2034  # C_UL is used in project.sh
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != dumb ]; then
    C_RED=$'\033[31m' C_GRN=$'\033[32m' C_YEL=$'\033[33m' C_CYN=$'\033[36m' C_BLD=$'\033[1m' C_DIM=$'\033[2m'
    C_UL=$'\033[4m' C_OFF=$'\033[0m'
else
    C_RED='' C_GRN='' C_YEL='' C_CYN='' C_BLD='' C_DIM='' C_UL='' C_OFF=''
fi

# What an install did, for its summary at the end: every warning, the ✓ lines while
# KIT_RUN_RECORD=1 (the wiring), and restarts. A file (KIT_RUN_LOG), since hooks run in subshells.
run_record() {      # kind text
    [ -n "${KIT_RUN_LOG:-}" ] && printf '%s|%s\n' "$1" "$2" >>"$KIT_RUN_LOG"
    return 0
}

section() { printf '\n%s%s%s%s\n' "$C_BLD" "$C_CYN" "$*" "$C_OFF"; }
info()    { printf '  %s\n' "$*"; }
note()    { printf '  %s%s%s\n' "$C_DIM" "$*" "$C_OFF"; }
ok()      { printf '  %s✓%s %s\n' "$C_GRN" "$C_OFF" "$*"; [ "${KIT_RUN_RECORD:-0}" != 1 ] || run_record new "$*"; }
ok_again() { printf '  %s✓%s %s\n' "$C_GRN" "$C_OFF" "$*"; }   # a check that holds on every run: not "new"
warn()    { printf '  %s!%s %s\n' "$C_YEL" "$C_OFF" "$*" >&2; run_record warn "$*"; }
err()     { printf '  %s✗%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; }
die()     { printf '%skit:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

# Space-separated word lists (module names, keys). No arrays, so nothing trips over bash 3.2's
# empty-array handling.
in_list() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }   # word list
list_add() { if in_list "$2" "$1"; then printf '%s' "$1"; else printf '%s' "${1:+$1 }$2"; fi; }   # list word

# ---------------------------------------------------------------- prompts

# Prompts read from stdin. They're interactive when stdin is a terminal, or when
# KIT_INTERACTIVE=1 (tests pipe answers in). KIT_INTERACTIVE=0 forces defaults.
is_interactive() {
    case "${KIT_INTERACTIVE:-auto}" in
        1) return 0 ;;
        0) return 1 ;;
    esac
    [ -t 0 ]
}

# Returns 1 when input has ended (Ctrl-D, or a pipe ran out), so callers never loop forever.
ask_line() {    # question default [silent] -> the answer on stdout (default when left empty)
    local q=$1 def=$2 reply='' rc=0
    if [ -n "$def" ]; then printf '  %s [%s]: ' "$q" "$def" >&2; else printf '  %s: ' "$q" >&2; fi
    if [ "${3:-}" = silent ] && [ -t 0 ]; then
        IFS= read -rs reply || rc=1
        printf '\n' >&2
    else
        IFS= read -r reply || rc=1
    fi
    [ $rc -eq 0 ] || [ -n "$reply" ] || return 1
    [ -n "$reply" ] || reply=$def
    printf '%s' "$reply"
}

confirm() {     # question [y|n default] -> 0 for yes
    local def=${2:-n} reply hint='y/N'
    [ "$def" = y ] && hint='Y/n'
    is_interactive || { [ "$def" = y ]; return; }
    printf '  %s [%s]: ' "$1" "$hint" >&2
    IFS= read -r reply || reply=''
    [ -n "$reply" ] || reply=$def
    case "$reply" in [Yy]|[Yy][Ee][Ss]) return 0 ;; esac
    return 1
}

# ---------------------------------------------------------------- key=value files

KV_KEY_RE='^[A-Za-z_][A-Za-z0-9_.-]*$'

kv_get() {      # file key -> value on stdout; returns 1 when the key isn't set
    [ -f "$1" ] || return 1
    awk -v k="$2" '
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
        {
            line = $0; sub(/^[ \t]+/, "", line)
            if (index(line, k "=") != 1) next
            v = trim(substr(line, length(k) + 2))
            if (substr(v, 1, 1) == "\"" && match(substr(v, 2), /"[^"]*$/)) {
                v = substr(v, 2, RSTART - 1)
            } else if (substr(v, 1, 1) == "#") {
                v = ""
            } else {
                sub(/[ \t]+#.*$/, "", v); v = trim(v)
            }
            val = v; found = 1
        }
        END { if (!found) exit 1; printf "%s", val }' "$1"
}

kv_comment() {  # file key -> the " # comment" after the key's last value, without the "#"
    [ -f "$1" ] || return 1
    awk -v k="$2" '
        {
            line = $0; sub(/^[ \t]+/, "", line)
            if (index(line, k "=") != 1) next
            v = substr(line, length(k) + 2); sub(/^[ \t]+/, "", v)
            c = ""
            if (substr(v, 1, 1) == "\"" && match(substr(v, 2), /"[^"]*$/)) v = substr(v, RSTART + 2)
            if (match(v, /(^|[ \t])#/)) { c = substr(v, RSTART + RLENGTH); sub(/^[ \t]+/, "", c); sub(/[ \t\r]+$/, "", c) }
            found = 1
        }
        END { if (!found) exit 1; printf "%s", c }' "$1"
}

kv_has() { kv_get "$1" "$2" >/dev/null; }

kv_keys() {     # file -> every key set in it, once each, in file order
    [ -f "$1" ] || return 0
    awk '{ s = $0; sub(/^[ \t]+/, "", s) }
         s ~ /^[A-Za-z_][A-Za-z0-9_.-]*=/ { sub(/=.*/, "", s); if (!(s in seen)) { seen[s] = 1; print s } }' "$1"
}

kv_needs_quotes() {
    case "$1" in
        *' #'*|*$'\t#'*|' '*|*' '|$'\t'*|*$'\t'|'"'*) return 0 ;;
    esac
    return 1
}

# Add KEY=value unless the key is already there. Never changes or reorders existing lines, so it
# is safe on user-owned files. "quote" always writes the value in double quotes (secrets).
# "force" appends even when the key is there (to fill a key left empty: the last line wins).
kv_append() {   # file key value [quote] [force]
    local file=$1 key=$2 val=$3
    [[ $key =~ $KV_KEY_RE ]] || die "bad key name: $key"
    case "$val" in *$'\n'*|*$'\r'*) die "the value for $key has a line break" ;; esac
    [ "${5:-}" = force ] || ! kv_has "$file" "$key" || return 0
    if [ "${4:-}" = quote ] || kv_needs_quotes "$val"; then val="\"$val\""; fi
    if [ -s "$file" ] && [ -n "$(tail -c 1 "$file")" ]; then printf '\n' >>"$file"; fi
    printf '%s=%s\n' "$key" "$val" >>"$file" || die "could not write $file"
}

# Set one key's line in place: the first line with the key is replaced, later ones dropped, every
# other line kept as it is (comments too). Appends when the key is missing. For simple values only
# (the MODULES= line); file permissions are kept.
kv_replace() {  # file key value
    local file=$1 key=$2 tmp rc
    [[ $key =~ $KV_KEY_RE ]] || die "bad key name: $key"
    case "$3" in *$'\n'*|*\\*) die "kv_replace: unsupported value for $key" ;; esac
    [ -f "$file" ] || : >"$file" || die "could not create $file"
    tmp=$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX") || die "mktemp failed"
    awk -v k="$key" -v l="$key=$3" '
        { s = $0; sub(/^[ \t]+/, "", s) }
        index(s, k "=") == 1 { if (!done) print l; done = 1; next }
        { print }
        END { if (!done) print l }' "$file" >"$tmp" && cat "$tmp" >"$file"
    rc=$?
    rm -f "$tmp"
    [ $rc -eq 0 ] || die "could not update $key in $file"
}

# Write a generated file atomically (temp file, then rename). Content comes from stdin.
write_generated() {     # file [mode]
    local file=$1 tmp
    tmp=$(mktemp "$(dirname "$file")/.kit.XXXXXX") || die "could not write $file"
    cat >"$tmp" || { rm -f "$tmp"; die "could not write $file"; }
    if ! { chmod "${2:-644}" "$tmp" && mv -f "$tmp" "$file"; }; then
        rm -f "$tmp"
        die "could not write $file"
    fi
}

# ---------------------------------------------------------------- misc

vers_ge() {     # a b -> 0 when version a >= b (dotted numbers)
    awk -v a="$1" -v b="$2" 'BEGIN {
        na = split(a, x, "."); nb = split(b, y, "."); n = na > nb ? na : nb
        for (i = 1; i <= n; i++) { p = x[i] + 0; q = y[i] + 0; if (p > q) exit 0; if (p < q) exit 1 }
        exit 0 }'
}

tilde() { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }

# Docker, through one function so tests can swap in a fake (KIT_DOCKER).
dk() { "${KIT_DOCKER:-docker}" "$@"; }
