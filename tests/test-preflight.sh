# shellcheck shell=bash
# Host preflight (lib/preflight.sh) with the host's commands replaced by functions

# A capable Mac with OrbStack running; each test changes one thing.
# shellcheck disable=SC2329,SC2317  # the stubs are called by preflight_host
fake_mac() {
    load_libs
    # shellcheck source=../lib/preflight.sh
    . "$TEST_ROOT/lib/preflight.sh"
    MAC_VERSION=15.1 MAC_ARCH=arm64 MAC_MEM=17179869184 MAC_FREE_KB=104857600
    MAC_ORBSTACK=1 MAC_DOCKER=1 MAC_COMPOSE=2.31.0
    sw_vers() { printf '%s\n' "$MAC_VERSION"; }
    uname() { printf '%s\n' "$MAC_ARCH"; }
    sysctl() { printf '%s\n' "$MAC_MEM"; }
    df() { printf 'Filesystem 1024-blocks Used Available Capacity Mounted\n/dev/disk3 0 0 %s 1%% /\n' "$MAC_FREE_KB"; }
    have_brew() { return 1; }
    orbstack_installed() { [ "$MAC_ORBSTACK" = 1 ]; }
    orbstack_app() { return 1; }
    dk() {
        case "$1" in
            info) [ "$MAC_DOCKER" = 1 ] ;;
            context) return 1 ;;
            compose) printf '%s\n' "$MAC_COMPOSE" ;;
        esac
    }
}

test_capable_and_ready() {
    fake_mac
    local out
    out=$(preflight_host 2>&1) || fail "preflight failed: $out"
    assert_contains "$out" 'macOS 15.1'
    assert_contains "$out" '16 GB of memory'
    assert_contains "$out" '100 GB free'
    assert_contains "$out" 'docker compose 2.31.0'
}

test_old_macos_cant_run() {
    fake_mac
    MAC_VERSION=12.7
    preflight_host >/dev/null 2>&1 && fail "should fail"
    assert_eq 1 "$PREFLIGHT_BAD"
    assert_contains "$(preflight_summary 2>&1)" "This Mac can't run the kit"
}

test_unsupported_cpu_cant_run() {
    fake_mac
    MAC_ARCH=ppc
    preflight_host >/dev/null 2>&1 && fail "should fail"
    assert_eq 1 "$PREFLIGHT_BAD"
}

test_missing_orbstack_is_a_step_not_a_verdict() {
    fake_mac
    MAC_ORBSTACK=0
    preflight_host >/dev/null 2>&1 && fail "should fail"
    assert_eq 0 "$PREFLIGHT_BAD"
    local out
    out=$(preflight_summary 2>&1)
    assert_contains "$out" 'This Mac can run the kit. Before installing:'
    assert_contains "$out" 'orbstack.dev/download'
    assert_not_contains "$out" "can't run"
}

test_stopped_orbstack_and_old_compose_are_steps() {
    fake_mac
    MAC_DOCKER=0
    preflight_host >/dev/null 2>&1 && fail "should fail"
    assert_contains "$PREFLIGHT_TODO" 'Open OrbStack'
    fake_mac
    MAC_COMPOSE=2.20.0
    preflight_host >/dev/null 2>&1 && fail "should fail"
    assert_contains "$PREFLIGHT_TODO" 'Update OrbStack'
}

test_low_memory_and_disk_only_warn() {
    fake_mac
    MAC_MEM=4294967296 MAC_FREE_KB=5242880
    local out
    out=$(preflight_host 2>&1) || fail "low memory or disk should only warn: $out"
    assert_contains "$out" '4 GB of memory: 8 GB or more is recommended'
    assert_contains "$out" 'only 5 GB free'
}
