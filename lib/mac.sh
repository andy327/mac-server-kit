# shellcheck shell=bash
# Mac settings: on a server, the power settings that keep it answering (never sleep, start up
# again by itself after a power cut, wake for network access). They need an admin, so the
# install shows what it would change and applies it with sudo only after you agree; run from a
# script, it prints the command instead. A laptop's settings are left alone. Sourced by ./kit.

kpmset() { "${KIT_PMSET:-pmset}" "$@"; }
ksudo() { "${KIT_SUDO:-sudo}" "$@"; }
kdefaults() { "${KIT_DEFAULTS:-defaults}" "$@"; }

# name value: sleep never, disks never spin down, restart after a power failure, wake on
# network access, no Power Nap (it wakes the Mac to half-run apps)
MAC_POWER="sleep 0
disksleep 0
autorestart 1
womp 1
powernap 0"

mac_power_changes() {   # -> "name value" pairs this Mac supports and doesn't have yet
    local cap cur name want have
    cap=$(kpmset -g cap 2>/dev/null)
    cur=$(kpmset -g 2>/dev/null)
    while read -r name want; do
        [ -n "$name" ] || continue
        printf '%s\n' "$cap" | awk -v n="$name" '$1 == n { f = 1 } END { exit !f }' || continue
        have=$(printf '%s\n' "$cur" | awk -v n="$name" '$1 == n { print $2; exit }')
        [ "$have" = "$want" ] || printf '%s %s ' "$name" "$want"
    done <<EOF
$MAC_POWER
EOF
}

mac_settings() {
    if [ "$(answer MACHINE_ROLE || echo server)" = laptop ]; then
        note "Power settings: left alone (MACHINE_ROLE=laptop)"
        return 0
    fi
    local changes
    changes=$(mac_power_changes)
    changes=${changes% }
    if [ -z "$changes" ]; then
        ok "Power settings: never sleeps, restarts after a power cut (already set)"
        return 0
    fi
    note "Power settings to change: $changes"
    if is_interactive && confirm "Apply them now? sudo asks for your password (an admin's)" y; then
        # shellcheck disable=SC2086  # name value pairs
        if ksudo "${KIT_PMSET:-pmset}" -a $changes; then
            ok "Power settings: never sleeps, restarts after a power cut"
            return 0
        fi
        warn "Power settings weren't changed. An admin can run: sudo pmset -a $changes"
    else
        note "Not changed. To apply them (as an admin): sudo pmset -a $changes"
    fi
}

# Whether this account logs in by itself after a restart (core's ready: done:auto-login). Only
# noted for the Still to do list; turning it on is the owner's call (FileVault prevents it).
mac_auto_login() {
    local u
    u=$(kdefaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || true)
    if [ -n "$u" ] && [ "$u" = "$(id -un)" ]; then todo_mark auto-login yes; else todo_mark auto-login no; fi
}
