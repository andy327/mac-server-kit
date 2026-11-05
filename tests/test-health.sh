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
    assert_contains "$(cat "$rc")" "MACHINE_ROLE='server'"
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
    for c in docker orb sysctl memory_pressure df route ping dscacheutil pmset launchctl log zip networksetup ifconfig; do
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

test_battery_warns_on_a_server_but_not_on_a_laptop() {
    health_setup
    FAKE_HOST_BATTERY=1 sample
    assert_eq warn "$(last_status)"
    assert_contains "$(tail -n 1 "$(samples_file)" | cut -f13)" 'host:on-battery'
    printf "MACHINE_ROLE='laptop'\n" >>"$KIT_SERVER_DIR/kit/runtime.conf"
    age_samples 300
    FAKE_HOST_BATTERY=1 sample
    assert_eq ok "$(last_status)"
    local out
    out=$(FAKE_HOST_BATTERY=1 "$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" 'On battery (62%)'
    assert_not_contains "$out" 'Plug it back in'
}

# ---------------------------------------------------------------- Tailscale and the network

ts_status() {       # peers-json health-json -> a file with a node's full status
    local f=$TEST_TMP/ts-status.json
    printf '{"BackendState":"Running","Self":{"Online":false,"Relay":"nyc"},"Health":%s,"Peer":%s}\n' "$2" "$1" >"$f"
    echo "$f"
}

test_tailscale_coordination_loss_warns_once_then_counts_as_down() {
    health_setup
    export FAKE_HOST_TS FAKE_HOST_TS_ONLINE=false
    FAKE_HOST_TS=$(ts_status '{"p1":{"CurAddr":"192.168.1.30:41641"}}' '[]')
    sample
    assert_eq warn "$(last_status)"
    assert_contains "$(tail -n 1 "$(samples_file)" | cut -f13)" 'ts:kit-media:coord'
    local out
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)     # the previous sample saw it too
    assert_contains "$out" 'online=false, the second check in a row'
    age_samples 300
    sample
    assert_eq fail "$(last_status)"
    # Back to normal; a later blip starts with a warning again
    age_samples 300
    FAKE_HOST_TS_ONLINE=true sample
    assert_eq ok "$(last_status)"
    age_samples 300
    sample
    assert_eq warn "$(last_status)"
}

test_tailscale_offline_without_links_is_down_right_away() {
    health_setup
    export FAKE_HOST_TS FAKE_HOST_TS_ONLINE=false
    # No live peer link
    FAKE_HOST_TS=$(ts_status '{"p1":{"CurAddr":"","LastHandshake":"0001-01-01T00:00:00Z"}}' '[]')
    local out
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" 'kit-media (media-tailscale): Running, online=false'
    assert_contains "$out" 'docker restart media-tailscale'
    # Peers, but no relay
    FAKE_HOST_TS=$(ts_status '{"p1":{"Active":true}}' '["Tailscale could not connect to the nyc relay server."]')
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" 'docker restart media-tailscale'
    # Relay and a peer: a warning, with no restart advice
    FAKE_HOST_TS=$(ts_status '{"p1":{"Active":true}}' '[]')
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" "lost Tailscale's coordination server; its relay (nyc) and 1 peer link(s) are still up"
    assert_not_contains "$out" 'docker restart media-tailscale'
}

test_a_tailnet_url_that_fails_once_gets_a_second_try() {
    health_setup
    local serve=$TEST_TMP/serve.json
    printf '{"Web":{"kit-media.example.ts.net:443":{"Handlers":{}}},"AllowFunnel":{"kit-media.example.ts.net:443":true}}\n' >"$serve"  # check-private: allow
    export FAKE_HOST_TS FAKE_HOST_TS_SERVE=$serve URL_RETRY_WAIT=0
    FAKE_HOST_TS=$(ts_status '{}' '[]')
    local out
    out=$(FAKE_CURL_FLAKY=ts.net "$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" '(Funnel) → 200'
    assert_eq 2 "$(grep -c 'ts.net' "$FAKE_CURL_LOG")"
}

test_network_setup_warnings() {
    health_setup
    local out
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_not_contains "$out" 'Wi-Fi'
    out=$(FAKE_HOST_UP='en0 en5' "$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" 'Wi-Fi (en0) and Ethernet (en5) are both connected'
    out=$(FAKE_HOST_UP='en0 en5' FAKE_HOST_IF=en0 "$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" 'Traffic goes over Wi-Fi (en0) though Ethernet (en5) is connected'
    out=$(FAKE_HOST_UP=en0 FAKE_HOST_IF=en0 "$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_not_contains "$out" 'Wi-Fi ('                    # Wi-Fi only is fine
    printf "HOME_ROUTER='192.168.1.1'\n" >>"$KIT_SERVER_DIR/kit/runtime.conf"
    assert_not_contains "$("$KIT_SERVER_DIR/bin/check-health" 2>&1)" 'usual'
    FAKE_HOST_GW=10.0.0.1 sample
    assert_eq warn "$(last_status)"
    assert_contains "$(tail -n 1 "$(samples_file)" | cut -f13)" 'net:router'
    printf "MACHINE_ROLE='laptop'\n" >>"$KIT_SERVER_DIR/kit/runtime.conf"
    out=$(FAKE_HOST_GW=10.0.0.1 FAKE_HOST_UP='en0 en5' FAKE_HOST_IF=en0 "$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_not_contains "$out" 'usual'
    assert_not_contains "$out" 'Wi-Fi ('
}

test_a_snapshot_keeps_the_network_events() {
    health_setup
    sample
    age_samples 300
    FAKE_HOST_DOCKER=down sample
    local f
    f=$(ls -d "$KIT_SERVER_DIR"/logs/health/incidents/*-down)/network-events.txt
    assert_contains "$(cat "$f")" 'router ARP failure'
    assert_not_contains "$(cat "$f")" 'unrelated'
    assert_contains "$(cat "${f%/*}/network.txt")" 'Hardware Port: Wi-Fi'
}

test_only_this_servers_scripts_count_as_maintenance() {
    health_setup
    local other=$TEST_TMP/other/server/bin pid
    mkdir -p "$other"
    printf '#!/bin/bash\nsleep 30\n' >"$other/backup-project"
    cp "$other/backup-project" "$KIT_SERVER_DIR/bin/backup-project"
    chmod +x "$other/backup-project" "$KIT_SERVER_DIR/bin/backup-project"
    "$other/backup-project" & pid=$!
    FAKE_HOST_DOCKER=down sample
    kill $pid 2>/dev/null
    assert_eq fail "$(last_status)"                     # another server's backup doesn't count
    age_samples 300
    "$KIT_SERVER_DIR/bin/backup-project" & pid=$!
    FAKE_HOST_DOCKER=down sample
    kill $pid 2>/dev/null
    assert_eq maint "$(last_status)"
    assert_contains "$(tail -n 1 "$(samples_file)" | cut -f13)" 'during backup-project'
}

test_install_records_the_router() {
    load_libs
    assert_contains "$(validate ipv4 192.168.1.1 && echo yes)" yes
    validate ipv4 192.168.1.256 && fail "accepted 192.168.1.256"
    validate ipv4 10.0.0 && fail "accepted 10.0.0"
    KIT_TEST_PATH=$TEST_TMP/fakebin
    mkdir -p "$KIT_TEST_PATH"; ln -sf "$TEST_ROOT/tests/fake-host" "$KIT_TEST_PATH/route"
    assert_eq 192.168.1.1 "$(PATH=$KIT_TEST_PATH:$PATH default_router)"
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

# The widget-update offer, on a copy of the health module's widget
widget_setup() {
    load_libs
    mkdir -p "$KIT_STATE" "$TEST_TMP/w"
    cp "$TEST_ROOT/modules/health/homarr-widget.json" "$TEST_ROOT/modules/health/homarr-widget.jsx" "$TEST_TMP/w/"
    export FAKE_HOMARR_KEY=test-key
    # shellcheck disable=SC2034  # homarr_call reads it
    HOMARR_KEY=test-key
    homarr_widget_list
    homarr_widget "$TEST_TMP/w" >/dev/null 2>&1
}
widget_run() { export KIT_INTERACTIVE=${1:-0}; homarr_widget_list; homarr_widget "$TEST_TMP/w" 2>&1; }  # [1: interactive]

test_widget_import_records_its_fingerprint_and_homarr_time() {
    widget_setup
    assert_contains "$(cat "$KIT_STATE/homarr-widgets.lock")" 'Server health|'
    assert_contains "$(cat "$KIT_STATE/homarr-widgets.lock")" '|2026-01-01T00:00:01.000Z'
    assert_contains "$(widget_run)" 'Server health widget (already there)'
}

test_a_changed_widget_is_offered_and_updated() {
    widget_setup
    printf '%s\n' '<Text>new</Text>' >"$TEST_TMP/w/homarr-widget.jsx"
    local out
    out=$(widget_run)                                   # not interactive: only a note
    assert_contains "$out" 'run ./kit install in Terminal to update it'
    assert_eq 0 "$(cat "$FAKE_CURL_DIR/homarr-widget-updates" 2>/dev/null | grep -c .)"
    out=$(widget_run 1 <<<'')         # the default is yes
    assert_contains "$out" 'Update it in Homarr?'
    assert_contains "$out" 'Server health widget updated'
    local up; up=$(cat "$FAKE_CURL_DIR/homarr-widget-updates")
    # shellcheck disable=SC2016  # a literal $schema
    assert_contains "$up" '{"json":{"id":"w1","$schema":"homarr-custom-widget-v2"'
    assert_contains "$up" '"template":"<Text>new</Text>"}}'
    assert_eq '}}' "$(printf '%s' "$up" | sed 's/.*<Text>new<\/Text>"//')"   # no brace too many
    assert_contains "$(cat "$KIT_STATE/homarr-widgets.lock")" '|2026-01-01T00:00:02.000Z'
    assert_contains "$(widget_run 1 </dev/null)" '(already there)'
}

test_a_widget_changed_in_homarr_is_kept_unless_you_agree() {
    widget_setup
    printf '%s\n' '<Text>new</Text>' >"$TEST_TMP/w/homarr-widget.jsx"
    export FAKE_HOMARR_EDITED='Server health'
    local out
    out=$(widget_run 1 <<<'')         # the default is no
    assert_contains "$out" 'was changed there since'
    assert_contains "$out" 'kept as you have it'
    [ -f "$FAKE_CURL_DIR/homarr-widget-updates" ] && fail "updated without agreement"
    # Not asked again for the same definition; asked again (as changed) for the next one
    assert_contains "$(widget_run 1 </dev/null)" '(already there)'
    printf '%s\n' '<Text>newer</Text>' >"$TEST_TMP/w/homarr-widget.jsx"
    out=$(widget_run 1 <<<'y')
    assert_contains "$out" 'was changed there since'
    assert_contains "$out" 'Server health widget updated'
}

test_a_widget_imported_before_the_record_is_adopted_when_it_matches() {
    widget_setup
    rm "$KIT_STATE/homarr-widgets.lock"
    assert_contains "$(widget_run)" '(already there)'
    assert_contains "$(cat "$KIT_STATE/homarr-widgets.lock")" 'Server health|'
    rm "$KIT_STATE/homarr-widgets.lock"
    printf '%s\n' '<Text>new</Text>' >"$TEST_TMP/w/homarr-widget.jsx"
    assert_contains "$(widget_run 1 <<<'')" 'was changed there since'
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
