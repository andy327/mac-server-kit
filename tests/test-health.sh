# shellcheck shell=bash
# Health: the runtime scripts, runtime.conf and launchd jobs the install sets up
# (lib/runtime.sh), the alert channels it tries (modules/health/hooks/wire), and check-health's
# --log mode (samples, alerts, maintenance) against tests/fake-host

HC_URL='https://hc-ping.com/0c1d2e3f-4a5b-4c6d-8e7f-001122334455'  # check-private: allow
TOPIC='kit-test-topic-x7q'

secrets_full() {    # a secrets file with Healthchecks and ntfy set
    S=$TEST_TMP/secrets-src.conf
    printf '%s\n' "WIREGUARD_PRIVATE_KEY=\"$FAKE_WG\"" "TS_AUTHKEY=\"$FAKE_TSKEY\"" \
        "HEALTHCHECK_URL=\"$HC_URL\"" "NTFY_TOPIC=\"$TOPIC\"" >"$S"
}
plist() { printf '%s/Library/LaunchAgents/io.github.andy327.mac-server-kit.%s.plist' "$HOME" "$1"; }

test_install_sets_up_scripts_runtime_conf_and_the_job() {
    secrets_full
    local out
    out=$(kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    local b=$KIT_SERVER_DIR/bin f
    for f in check-health show-health-history export-health-status start-maintenance end-maintenance check-media-stack; do
        [ -x "$b/$f" ] || fail "$f not installed"
    done
    local rc=$KIT_SERVER_DIR/kit/runtime.conf
    assert_eq 600 "$(stat -f %Lp "$rc")"
    assert_contains "$(cat "$rc")" "PROJECTS='media-stack'"
    assert_contains "$(cat "$rc")" "HEALTHCHECK_URL='$HC_URL'"
    assert_contains "$(cat "$rc")" "NTFY_URL='https://ntfy.sh/$TOPIC'"
    assert_contains "$(cat "$rc")" "HOST_TAILSCALE='auto'"
    /bin/bash -c ". '$rc'" || fail "runtime.conf doesn't load in bash"
    local p; p=$(plist log-health)
    assert_contains "$(cat "$p")" "<string>$b/check-health</string>"
    assert_contains "$(cat "$p")" '<string>--log</string>'
    assert_contains "$(cat "$p")" '<integer>300</integer>'
    plutil -lint "$p" >/dev/null || fail "plist doesn't lint"
    assert_contains "$(cat "$FAKE_LAUNCHD_DIR/loaded")" 'io.github.andy327.mac-server-kit.log-health'
    assert_contains "$out" 'Job log-health: every 5 min'
    assert_contains "$out" 'Healthchecks.io: checked in'
    assert_contains "$out" 'ntfy: test message sent'
    assert_contains "$(cat "$FAKE_CURL_LOG")" "POST hc-ping.com/${HC_URL##*/}"
    assert_contains "$(cat "$FAKE_CURL_LOG")" "POST ntfy.sh/$TOPIC"
    # health-web is part of the media stack, behind the dashboard node at /health/
    assert_contains "$(cat "$KIT_SERVER_DIR/media-stack/tailscale/dashboard/serve.json")" '"/health/": { "Proxy": "http://health-web:80" }'
    [ -d "$KIT_SERVER_DIR/logs/health/web" ] || fail "no folder for health-web"
}

test_second_install_keeps_the_job_and_tests_ntfy_once() {
    secrets_full
    kit install --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    : >"$FAKE_LAUNCHD_LOG"
    local out
    out=$(kit install 2>&1) || fail "second install failed: $out"
    assert_contains "$out" 'Job log-health: every 5 min (already loaded)'
    assert_not_contains "$(cat "$FAKE_LAUNCHD_LOG")" 'bootstrap'
    assert_contains "$out" 'ntfy: test message sent before'
    assert_eq 1 "$(grep -c "POST ntfy.sh/$TOPIC" "$FAKE_CURL_LOG")"
    assert_eq 2 "$(grep -c "POST hc-ping.com/" "$FAKE_CURL_LOG")"     # a check-in each install
}

test_a_job_or_script_no_module_has_is_removed() {
    secrets_src_basic
    kit install --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    # Left over from a module that's gone: the kit's own, so it's removed; the user's stays
    local old; old=$(plist old-job)
    cp "$(plist log-health)" "$old"
    printf 'old-script\n' >>"$KIT_SERVER_DIR/kit/bin.list"
    printf '#!/bin/sh\n' >"$KIT_SERVER_DIR/bin/old-script"
    printf '#!/bin/sh\n' >"$KIT_SERVER_DIR/bin/my-own-script"
    local out
    out=$(kit install 2>&1) || fail "install failed: $out"
    [ ! -e "$old" ] || fail "the old job's plist is still there"
    assert_contains "$out" 'Job old-job: removed'
    assert_contains "$(cat "$FAKE_LAUNCHD_LOG")" 'bootout gui/'
    [ ! -e "$KIT_SERVER_DIR/bin/old-script" ] || fail "the old script is still there"
    [ -e "$KIT_SERVER_DIR/bin/my-own-script" ] || fail "the user's own script was removed"
}

test_no_alert_channels_means_no_calls() {
    secrets_src_basic
    local out
    out=$(kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_not_contains "$(cat "$FAKE_CURL_LOG")" 'hc-ping.com'
    assert_not_contains "$(cat "$FAKE_CURL_LOG")" 'ntfy'
    assert_contains "$(cat "$KIT_SERVER_DIR/kit/runtime.conf")" "NTFY_URL=''"
}

test_a_failing_alert_channel_only_warns() {
    secrets_full
    local out
    out=$(FAKE_CURL_DOWN=ntfy.sh kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$out" "ntfy didn't take a test message"
    [ ! -f "$KIT_SERVER_DIR/kit/ntfy-tested" ] || fail "marked as tested"
}

test_job_that_launchd_refuses_warns() {
    secrets_src_basic
    local out
    out=$(FAKE_LAUNCHD_FAIL=1 kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$out" "launchd didn't load it"
}

secrets_src_basic() {
    S=$TEST_TMP/secrets-src.conf
    printf '%s\n' "WIREGUARD_PRIVATE_KEY=\"$FAKE_WG\"" "TS_AUTHKEY=\"$FAKE_TSKEY\"" \
        'HEALTHCHECK_URL=""' 'NTFY_TOPIC=""' >"$S"
}

# ---------------------------------------------------------------- check-health --log

# check-health from the repo, on a fake Mac: no projects, the fake host commands first on PATH
health_setup() {
    H=$TEST_TMP/fakebin
    mkdir -p "$H" "$KIT_SERVER_DIR/kit" "$KIT_SERVER_DIR/bin"
    local c
    for c in docker orb sysctl memory_pressure df route ping dscacheutil pmset launchctl log zip; do
        ln -sf "$TEST_ROOT/tests/fake-host" "$H/$c"
    done
    ln -sf "$TEST_ROOT/tests/fake-curl" "$H/curl"
    cp "$TEST_ROOT"/modules/health/bin/* "$KIT_SERVER_DIR/bin/"
    printf '%s\n' "PROJECTS=''" "HEALTHCHECK_URL='$HC_URL'" "NTFY_URL='https://ntfy.sh/$TOPIC'" \
        "HOST_TAILSCALE='off'" 'NATIVE_APPS=()' >"$KIT_SERVER_DIR/kit/runtime.conf"
    export KIT_TEST_PATH=$H
}
# One sample, NOW seconds after the previous one (check-health reads the clock; the samples'
# epochs are moved back afterwards so the next run sees the right gap)
sample() { "$KIT_SERVER_DIR/bin/check-health" --log; }
samples_file() { ls "$KIT_SERVER_DIR"/logs/health/samples-*.tsv; }
last_status() { tail -n 1 "$(samples_file)" | cut -f3; }
age_samples() {     # seconds: make every sample that much older
    local f; f=$(samples_file)
    awk -F'\t' -v OFS='\t' -v d="$1" 'NR > 1 { $1 -= d } { print }' "$f" >"$f.new" && mv "$f.new" "$f"
}

test_log_records_samples_and_alerts_on_change() {
    health_setup
    sample
    assert_eq ok "$(last_status)"
    assert_contains "$(cat "$FAKE_CURL_LOG")" "POST hc-ping.com/${HC_URL##*/}"
    assert_not_contains "$(cat "$FAKE_CURL_LOG")" 'ntfy'
    age_samples 300
    FAKE_HOST_DOCKER=down sample
    assert_eq fail "$(last_status)"
    assert_contains "$(tail -n 1 "$(samples_file)" | cut -f13)" 'orbstack:down'
    assert_contains "$(cat "$FAKE_CURL_LOG")" "POST hc-ping.com/${HC_URL##*/}/fail"
    assert_eq 1 "$(grep -c "POST ntfy.sh/$TOPIC" "$FAKE_CURL_LOG")"
    ls -d "$KIT_SERVER_DIR"/logs/health/incidents/*-down >/dev/null 2>&1 || fail "no down snapshot"
    age_samples 300
    FAKE_HOST_DOCKER=down sample                   # still down: no second alert
    assert_eq 1 "$(grep -c "POST ntfy.sh/$TOPIC" "$FAKE_CURL_LOG")"
    age_samples 300
    sample
    assert_eq ok "$(last_status)"
    assert_eq 2 "$(grep -c "POST ntfy.sh/$TOPIC" "$FAKE_CURL_LOG")"   # recovered
    ls -d "$KIT_SERVER_DIR"/logs/health/incidents/*-recovered >/dev/null 2>&1 || fail "no recovered snapshot"
    assert_contains "$(cat "$KIT_SERVER_DIR/logs/health/web/status.json")" '"state": "ok"'
}

test_log_alerts_when_the_mac_is_back_after_a_gap() {
    health_setup
    sample
    age_samples 3600                               # no check-in for an hour
    sample
    assert_eq 1 "$(grep -c "POST ntfy.sh/$TOPIC" "$FAKE_CURL_LOG")"
    ls -d "$KIT_SERVER_DIR"/logs/health/incidents/*-gap >/dev/null 2>&1 || fail "no gap snapshot"
}

test_maintenance_window_logs_maint_and_stays_quiet() {
    health_setup
    sample
    "$KIT_SERVER_DIR/bin/start-maintenance" macOS update >/dev/null || fail "start-maintenance failed"
    age_samples 300
    FAKE_HOST_DOCKER=down sample
    assert_eq maint "$(last_status)"
    assert_not_contains "$(cat "$FAKE_CURL_LOG")" 'ntfy'
    assert_not_contains "$(cat "$FAKE_CURL_LOG")" '/fail'
    assert_eq 'macOS update' "$(tail -n 1 "$(samples_file)" | cut -f15)"
    "$KIT_SERVER_DIR/bin/end-maintenance" >/dev/null
    [ ! -f "$KIT_SERVER_DIR/logs/health/.maintenance" ] || fail "window still open"
}

test_summary_and_history_read_the_log() {
    health_setup
    local out
    out=$("$KIT_SERVER_DIR/bin/check-health" --summary)
    assert_contains "$out" 'No health samples yet'
    sample
    out=$("$KIT_SERVER_DIR/bin/check-health" --summary)
    assert_contains "$out" 'Healthy at'
    out=$("$KIT_SERVER_DIR/bin/show-health-history" 2>&1) || fail "show-health-history failed: $out"
    assert_contains "$out" '1 samples'
}

test_report_mode_explains_a_stopped_orbstack() {
    health_setup
    local out rc=0
    out=$(FAKE_HOST_DOCKER=down "$KIT_SERVER_DIR/bin/check-health" 2>&1) || rc=$?
    assert_eq 2 "$rc"
    assert_contains "$out" "OrbStack isn't running"
    assert_contains "$out" 'orb start'
}

# ---------------------------------------------------------------- the Server health widget

test_install_imports_the_server_health_widget_once() {
    secrets_src_basic
    local out
    out=$(kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Homarr: Server health widget (Management → Custom widgets'
    local imp; imp=$(cat "$FAKE_CURL_DIR/homarr-widget-imports")
    # shellcheck disable=SC2016  # a literal $schema
    assert_contains "$imp" '"$schema":"homarr-custom-widget-v2"'
    assert_contains "$imp" '"baseUrl":"http://health-web"'
    # The template goes in as one JSON string: its quotes escaped, its lines joined with \n
    assert_contains "$imp" '"template":"<Box>{status.status?.loading'
    assert_contains "$imp" 'title=\"Health stats unavailable\"'
    assert_eq 1 "$(grep -c . "$FAKE_CURL_DIR/homarr-widget-imports")"
    out=$(kit install 2>&1) || fail "second install failed: $out"
    assert_contains "$out" 'Homarr: Server health widget (already there)'
    assert_eq 1 "$(grep -c . "$FAKE_CURL_DIR/homarr-widget-imports")"
}

test_an_older_homarr_without_custom_widgets_only_warns() {
    secrets_src_basic
    local out
    out=$(FAKE_HOMARR_OLD=1 kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'custom widgets need a newer Homarr'
    assert_contains "$out" 'Homarr: Sonarr tile'                  # the rest still happened
}

test_json_text_escapes_a_template() {
    load_libs
    printf '%s\n' 'a "q" \ b' "	tab" >"$TEST_TMP/t.jsx"
    assert_eq '"a \"q\" \\ b\n\ttab"' "$(json_text "$TEST_TMP/t.jsx")"
}
