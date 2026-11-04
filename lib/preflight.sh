# shellcheck shell=bash
# Host preflight: checks that run before anything is installed. Sourced by ./kit.
# Each check prints one line. Two kinds of problem:
#   can't run   this Mac can't run the kit (macOS too old, unsupported CPU)
#   to do       something to install or start first (OrbStack), listed as a step
# preflight_host returns 1 when there's either; PREFLIGHT_BAD and PREFLIGHT_TODO say which.

ORBSTACK_URL='https://orbstack.dev/download'
MIN_MACOS=13        # OrbStack's minimum
MIN_COMPOSE=2.24    # COMPOSE_FILE lists, up --wait and --wait-timeout
MIN_FREE_GB=20
MIN_MEM_GB=8        # a warning, not a refusal: the base stack plus Plex

export PATH="$HOME/.orbstack/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

have_brew() { command -v brew >/dev/null 2>&1; }

# Use OrbStack's Docker context when it exists, even if another Docker (Desktop) is the default.
use_orbstack_context() {
    if [ -z "${DOCKER_CONTEXT:-}" ] && dk context inspect orbstack >/dev/null 2>&1; then
        export DOCKER_CONTEXT=orbstack
    fi
}

orbstack_app() {    # -> the OrbStack.app folder, if there is one
    local d
    for d in /Applications/OrbStack.app "$HOME/Applications/OrbStack.app"; do
        [ -d "$d" ] && { printf '%s' "$d"; return 0; }
    done
    return 1
}
orbstack_installed() { orbstack_app >/dev/null || command -v orb >/dev/null 2>&1; }
docker_up() { dk info >/dev/null 2>&1; }

PREFLIGHT_BAD=0
PREFLIGHT_TODO=''
pf_fail() { err "$1"; [ -n "${2:-}" ] && note "    $2"; PREFLIGHT_BAD=1; }
pf_todo() {         # problem step
    err "$1"
    PREFLIGHT_TODO="${PREFLIGHT_TODO:+$PREFLIGHT_TODO
}$2"
}

preflight_host() {
    local v major arch free_gb mem_gb compose app
    PREFLIGHT_BAD=0
    PREFLIGHT_TODO=''
    section "This Mac"

    v=$(sw_vers -productVersion 2>/dev/null)
    major=${v%%.*}
    if [ -z "$v" ]; then
        pf_fail "this doesn't look like macOS (no sw_vers)"
    elif [ "$major" -lt "$MIN_MACOS" ] 2>/dev/null; then
        pf_fail "macOS $v: the kit needs macOS $MIN_MACOS or newer (OrbStack's minimum)"
    else
        ok "macOS $v"
    fi

    arch=$(uname -m)
    case "$arch" in
        arm64) ok "Apple Silicon" ;;
        x86_64) ok "Intel" ;;
        *) pf_fail "unsupported CPU architecture: $arch" ;;
    esac

    mem_gb=$(sysctl -n hw.memsize 2>/dev/null | awk '{ printf "%d", $1 / 1073741824 }')
    if [ -z "$mem_gb" ]; then
        warn "couldn't read the amount of memory"
    elif [ "$mem_gb" -lt "$MIN_MEM_GB" ]; then
        warn "${mem_gb} GB of memory: $MIN_MEM_GB GB or more is recommended for the apps plus Plex or Jellyfin"
    else
        ok "${mem_gb} GB of memory"
    fi

    free_gb=$(df -Pk "$HOME" | awk 'NR == 2 { printf "%d", $4 / 1048576 }')
    if [ "${free_gb:-0}" -lt "$MIN_FREE_GB" ]; then
        warn "only ${free_gb} GB free on the startup disk (images and app data need about $MIN_FREE_GB GB)"
    else
        ok "${free_gb} GB free"
    fi

    if have_brew; then ok "Homebrew found"; else info "No Homebrew: native apps are installed without it"; fi

    section "OrbStack (runs Docker)"
    if ! orbstack_installed; then
        if have_brew; then
            pf_todo "OrbStack is not installed" "Install OrbStack: brew install --cask orbstack, then open it once"
        else
            pf_todo "OrbStack is not installed" "Install OrbStack: download it from $ORBSTACK_URL, then open it once"
        fi
    else
        use_orbstack_context
        app=$(orbstack_app || true)
        if ! docker_up && is_interactive && [ -n "$app" ]; then
            info "OrbStack isn't running; starting it (finish its first-run steps on screen if it asks)"
            open "$app"
            wait_for_docker 180
        fi
        if ! docker_up; then
            pf_todo "OrbStack is installed but Docker isn't answering" "Open OrbStack and wait until it says it's running"
        else
            ok "OrbStack running (Docker context: ${DOCKER_CONTEXT:-default})"
            compose=$(dk compose version --short 2>/dev/null | sed 's/^v//')
            if [ -z "$compose" ]; then
                pf_todo "docker compose is missing" "Update OrbStack (its menu: Check for Updates)"
            elif ! vers_ge "$compose" "$MIN_COMPOSE"; then
                pf_todo "docker compose $compose is too old (needs $MIN_COMPOSE or newer)" "Update OrbStack (its menu: Check for Updates)"
            else
                ok "docker compose $compose"
            fi
        fi
    fi

    [ $PREFLIGHT_BAD = 0 ] && [ -z "$PREFLIGHT_TODO" ]
}

# After preflight_host: one verdict line, then the to-do steps.
preflight_summary() {
    local line
    if [ $PREFLIGHT_BAD = 1 ]; then
        err "This Mac can't run the kit (above)."
        return
    fi
    if [ -n "$PREFLIGHT_TODO" ]; then
        section "To do first"
        ok "This Mac can run the kit. Before installing:"
        printf '%s\n' "$PREFLIGHT_TODO" | while IFS= read -r line; do info "- $line"; done
        info "Then run ./kit check again."
    fi
}

wait_for_docker() {     # seconds
    local i=0
    while [ $i -lt "$1" ]; do
        docker_up && return 0
        sleep 3
        i=$((i + 3))
    done
    return 1
}
