# shellcheck shell=bash
# Helpers for tests/run. Every test gets a fresh temporary ~/server (KIT_SERVER_DIR) and, when it
# calls fake_modules, its own module folder in place of the repo's.

# Fake keys in the right formats, shared by every test
# shellcheck disable=SC2034  # used by the test files
FAKE_WG='kGyBWqcVhzpzkFpWbUAYcIY+xGqoUZpDe1rqAqKDdHc='  # check-private: allow
FAKE_TSKEY='tskey-auth-kAbC123CNTRL-AbCdEf123456'  # check-private: allow
FAKE_HC_URL='https://hc-ping.com/0f8a1d2c-1111-4a4a-9b9b-123456789abc'  # check-private: allow

TEST_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

test_setup() {
    TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/kit-test.XXXXXX") || exit 1
    # shellcheck disable=SC2064
    trap "rm -rf '$TEST_TMP'" EXIT
    # A home folder of its own, so nothing touches the real one (~/.zprofile, ~/Media)
    export HOME=$TEST_TMP/home
    mkdir -p "$HOME"
    export KIT_SERVER_DIR=$TEST_TMP/server
    export KIT_SKIP_HOST_CHECKS=1
    export KIT_INTERACTIVE=0
    # Every docker call goes to the fake, which logs it; no test reaches the real Docker
    export KIT_DOCKER=$TEST_ROOT/tests/fake-docker
    export FAKE_DOCKER_LOG=$TEST_TMP/docker.log
    unset KIT_MODULES_DIR
}

load_libs() {   # source the kit's libraries the way ./kit does
    KIT_DIR=$TEST_ROOT
    # shellcheck source=../lib/common.sh
    . "$KIT_DIR/lib/common.sh"
    # shellcheck source=../lib/config.sh
    . "$KIT_DIR/lib/config.sh"
    # shellcheck source=../lib/modules.sh
    . "$KIT_DIR/lib/modules.sh"
    # shellcheck source=../lib/project.sh
    . "$KIT_DIR/lib/project.sh"
}

kit() { /bin/bash "$TEST_ROOT/kit" "$@"; }

# Module folders for tests: fake_modules, then mkmod name KEY=value...
fake_modules() {
    export KIT_MODULES_DIR=$TEST_TMP/modules
    mkdir -p "$KIT_MODULES_DIR"
}
mkmod() {       # name KEY=value... (KIND defaults to optional); root via MKMOD_ROOT
    local root=${MKMOD_ROOT:-$KIT_MODULES_DIR} name=$1
    shift
    mkdir -p "$root/$name"
    printf 'KIND=optional\n' >"$root/$name/module.conf"
    for kv in "$@"; do printf '%s\n' "$kv" >>"$root/$name/module.conf"; done
}

fail()  { printf 'assertion failed: %s\n' "$*" >&2; exit 1; }
assert_eq() {           # expected actual [message]
    [ "$1" = "$2" ] || fail "${3:-values differ}
      expected: [$1]
      actual:   [$2]"
}
assert_contains() {     # haystack needle
    case "$1" in *"$2"*) ;; *) fail "expected to find [$2] in:
$1" ;; esac
}
assert_not_contains() {
    case "$1" in *"$2"*) fail "did not expect [$2] in:
$1" ;; esac
}
assert_fails() {        # command...: must exit non-zero
    if ( "$@" ) >/dev/null 2>&1; then fail "expected failure: $*"; fi
}
assert_ok() {
    local out
    out=$( ( "$@" ) 2>&1 ) || fail "expected success: $*
$out"
}
