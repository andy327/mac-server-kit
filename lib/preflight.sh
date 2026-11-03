# shellcheck shell=bash
# Host preflight: checks that run before anything is installed. Sourced by ./kit.
# Each check prints one line. preflight_host returns 1 when a check failed.

ORBSTACK_URL='https://orbstack.dev/download'
MIN_MACOS=13        # OrbStack's minimum
MIN_COMPOSE=2.24    # COMPOSE_FILE lists, up --wait and --wait-timeout
MIN_FREE_GB=20

export PATH="$HOME/.orbstack/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

have_brew() { command -v brew >/dev/null 2>&1; }

# Use OrbStack's Docker context when it exists, even if another Docker (Desktop) is the default.
use_orbstack_context() {
    if [ -z "${DOCKER_CONTEXT:-}" ] && docker context inspect orbstack >/dev/null 2>&1; then
        export DOCKER_CONTEXT=orbstack
    fi
}

orbstack_installed() { [ -d /Applications/OrbStack.app ] || command -v orb >/dev/null 2>&1; }
docker_up() { docker info >/dev/null 2>&1; }

PREFLIGHT_BAD=0
pf_fail() { err "$1"; [ -n "${2:-}" ] && note "    $2"; PREFLIGHT_BAD=1; }

preflight_host() {
    local v major arch free_gb compose
    PREFLIGHT_BAD=0
    section "Host"

    v=$(sw_vers -productVersion 2>/dev/null)
    major=${v%%.*}
    if [ -z "$v" ]; then
        pf_fail "this doesn't look like macOS (no sw_vers)"
    elif [ "$major" -lt "$MIN_MACOS" ] 2>/dev/null; then
        pf_fail "macOS $v: OrbStack needs macOS $MIN_MACOS or newer"
    else
        ok "macOS $v"
    fi

    arch=$(uname -m)
    case "$arch" in
        arm64) ok "Apple Silicon" ;;
        x86_64) ok "Intel" ;;
        *) pf_fail "unsupported CPU architecture: $arch" ;;
    esac

    if have_brew; then ok "Homebrew found"; else info "No Homebrew: native apps are installed without it"; fi

    free_gb=$(df -Pk "$HOME" | awk 'NR == 2 { printf "%d", $4 / 1048576 }')
    if [ "${free_gb:-0}" -lt "$MIN_FREE_GB" ]; then
        warn "only ${free_gb} GB free on the startup disk (images and app data need about $MIN_FREE_GB GB)"
    else
        ok "${free_gb} GB free"
    fi

    section "OrbStack"
    if ! orbstack_installed; then
        if have_brew; then
            pf_fail "OrbStack is not installed" "Install it with: brew install --cask orbstack (then open it once)"
        else
            pf_fail "OrbStack is not installed" "Download it from $ORBSTACK_URL, open it once, then run ./kit again"
        fi
        return 1
    fi
    use_orbstack_context
    if ! docker_up && is_interactive && [ -d /Applications/OrbStack.app ]; then
        info "OrbStack isn't running; starting it (finish its first-run steps on screen if it asks)"
        open -a OrbStack
        wait_for_docker 180
    fi
    if ! docker_up; then
        pf_fail "OrbStack is installed but Docker isn't answering" "Open OrbStack and wait until it says it's running"
        return 1
    fi
    ok "OrbStack running (Docker context: ${DOCKER_CONTEXT:-default})"

    compose=$(docker compose version --short 2>/dev/null | sed 's/^v//')
    if [ -z "$compose" ]; then
        pf_fail "docker compose is missing" "Update OrbStack"
    elif ! vers_ge "$compose" "$MIN_COMPOSE"; then
        pf_fail "docker compose $compose is too old (needs $MIN_COMPOSE or newer)" "Update OrbStack"
    else
        ok "docker compose $compose"
    fi
    return $PREFLIGHT_BAD
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
