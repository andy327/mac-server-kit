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
    assert_contains "$out" 'Healthchecks.io: pinged'
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
    assert_contains "$out" 'Healthchecks.io: pinged (HEALTHCHECK_URL still works)'
    assert_not_contains "$out" '✓ Healthchecks.io'
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
    for c in docker orb sysctl memory_pressure df mount route ping dscacheutil pmset launchctl log zip networksetup ifconfig; do
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

test_no_healthchecks_ping_inside_a_maintenance_window() {
    health_setup
    sample
    assert_eq 1 "$(grep -c "POST hc-ping.com/" "$FAKE_CURL_LOG")"
    "$KIT_SERVER_DIR/bin/start-maintenance" macOS update >/dev/null || fail "start-maintenance failed"
    age_samples 300
    sample                                         # healthy, but the window is open
    age_samples 300
    FAKE_HOST_DOCKER=down sample
    assert_eq 1 "$(grep -c "POST hc-ping.com/" "$FAKE_CURL_LOG")"   # a ping would resume the paused check
    age_samples 3600                               # the planned downtime: a gap
    sample                                         # back and healthy: the window closes
    [ ! -f "$KIT_SERVER_DIR/logs/health/.maintenance" ] || fail "window still open"
    assert_eq 2 "$(grep -c "POST hc-ping.com/" "$FAKE_CURL_LOG")"
    assert_not_contains "$(cat "$FAKE_CURL_LOG")" "/fail"
}

reboot_samples() {  # make the logged samples come from an earlier boot (kern.boottime jumps)
    local f; f=$(samples_file)
    awk -F'\t' -v OFS='\t' 'NR > 1 { $4 -= 86400 } { print }' "$f" >"$f.new" && mv "$f.new" "$f"
}

test_a_reboot_inside_a_maintenance_window_is_maintenance() {
    health_setup
    sample
    "$KIT_SERVER_DIR/bin/start-maintenance" macOS update >/dev/null || fail "start-maintenance failed"
    age_samples 300
    sample                                         # inside the window, before the restart
    assert_eq '' "$(tail -n 1 "$(samples_file)" | cut -f3 | grep -v ok)"
    age_samples 200
    reboot_samples
    # The fake Mac booted 3 days ago: open the window after the earlier boot and before that one
    local m=$KIT_SERVER_DIR/logs/health/.maintenance
    awk -F'\t' -v OFS='\t' '{ $1 -= 86400 * 3 + 43200 } { print }' "$m" >"$m.new" && mv "$m.new" "$m"
    FAKE_HOST_DOCKER=down sample                  # the boot-time sample, still coming up
    assert_eq maint "$(last_status)"
    assert_not_contains "$(cat "$FAKE_CURL_LOG")" 'ntfy'
    assert_not_contains "$(cat "$FAKE_CURL_LOG")" '/fail'
    ! ls -d "$KIT_SERVER_DIR"/logs/health/incidents/*/ >/dev/null 2>&1 || fail "saved a snapshot"
    [ -f "$KIT_SERVER_DIR/logs/health/.maintenance" ] || fail "window closed while still failing"
    local out
    out=$(NO_COLOR=1 "$KIT_SERVER_DIR/bin/show-health-history")
    assert_contains "$out" 'MAINT'
    assert_contains "$out" 'planned: macOS update; booted'
    assert_not_contains "$out" 'REBOOT'
    assert_not_contains "$out" 'DOWN'
    age_samples 300
    sample                                         # back up and healthy: the window closes
    assert_eq ok "$(last_status)"
    [ ! -f "$KIT_SERVER_DIR/logs/health/.maintenance" ] || fail "window still open"
    assert_not_contains "$(cat "$FAKE_CURL_LOG")" 'ntfy'
}

test_history_ends_an_outage_at_a_warning() {
    health_setup
    FAKE_HOST_DOCKER=down sample
    age_samples 300
    FAKE_HOST_BATTERY=1 sample                     # not failing any more, but a warning
    assert_eq warn "$(last_status)"
    local out
    out=$(NO_COLOR=1 "$KIT_SERVER_DIR/bin/show-health-history")
    assert_contains "$out" 'DOWN   5m'
    assert_contains "$out" 'WARN   0m       (still going)'
    assert_not_contains "$(printf '%s\n' "$out" | grep DOWN)" 'still going'
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

# The Mac's own Tailscale app, watched: FAKE_APP_ONLINE=false is offline to the coordination server
fake_ts_app() {
    TS_APP=$TEST_TMP/Tailscale
    # shellcheck disable=SC2016  # expanded when the fake app runs
    printf '#!/bin/bash\nprintf %s "${FAKE_APP_ONLINE:-true}"\n' \
        "'{\"BackendState\":\"Running\",\"Self\":{\"Online\":%s,\"DNSName\":\"kit-mac.example.ts.net.\"}}\\n'" >"$TS_APP"  # check-private: allow
    chmod +x "$TS_APP"
    export TS_APP
    printf "HOST_TAILSCALE='on'\n" >>"$KIT_SERVER_DIR/kit/runtime.conf"
}
funnel_serve() {
    local f=$TEST_TMP/serve.json
    printf '{"Web":{"kit-media.example.ts.net:443":{"Handlers":{}}},"AllowFunnel":{"kit-media.example.ts.net:443":true}}\n' >"$f"  # check-private: allow
    echo "$f"
}

test_every_node_losing_the_coordination_server_is_a_warning_while_funnel_loads() {
    health_setup
    fake_ts_app
    export FAKE_HOST_TS FAKE_HOST_TS_ONLINE=false FAKE_APP_ONLINE=false URL_RETRY_WAIT=0
    export FAKE_HOST_TS_SERVE
    FAKE_HOST_TS_SERVE=$(funnel_serve)
    FAKE_HOST_TS=$(ts_status '{}' '[]')       # no live links: on its own this node would be down
    local out
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" "Every Tailscale node lost Tailscale's coordination server at once (its one Tailscale container and"
    assert_contains "$out" '(Funnel) → 200'
    # The diagnosis is folded at 92 columns, and the Mac's name in it decides where the breaks
    # fall (a CI runner's name is 60 characters), so match it with the line breaks undone
    assert_contains "$(printf '%s' "$out" | tr '\n' ' ' | tr -s ' ')" "that's Tailscale's side"
    assert_not_contains "$out" 'docker restart'
    assert_not_contains "$out" 'Network Extensions'      # the app's own advice doesn't apply
    sample
    assert_eq warn "$(last_status)"
    assert_contains "$(tail -n 1 "$(samples_file)" | cut -f13)" 'ts:coord-all'
    # Still a warning on the next check, as long as Funnel loads
    age_samples 300
    sample
    assert_eq warn "$(last_status)"
}

test_every_node_losing_the_coordination_server_is_down_once_funnel_stops_loading() {
    health_setup
    fake_ts_app
    export FAKE_HOST_TS FAKE_HOST_TS_ONLINE=false FAKE_APP_ONLINE=false URL_RETRY_WAIT=0
    export FAKE_HOST_TS_SERVE FAKE_CURL_DOWN=ts.net
    FAKE_HOST_TS_SERVE=$(funnel_serve)
    FAKE_HOST_TS=$(ts_status '{}' '[]')
    local out
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" '(Funnel) → unreachable'
    assert_contains "$out" "Visitors can't get in"
    assert_contains "$out" 'docker restart media-tailscale'
    assert_not_contains "$out" 'reports connected'
    sample
    assert_eq fail "$(last_status)"
}

test_every_node_losing_the_coordination_server_without_funnel_is_down_the_second_time() {
    health_setup
    fake_ts_app
    export FAKE_HOST_TS FAKE_HOST_TS_ONLINE=false FAKE_APP_ONLINE=false
    FAKE_HOST_TS=$(ts_status '{}' '[]')
    sample
    assert_eq warn "$(last_status)"
    local out
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)     # the previous sample saw it too
    assert_contains "$out" 'the second check in a row'
    assert_contains "$out" 'docker restart media-tailscale'
    age_samples 300
    sample
    assert_eq fail "$(last_status)"
}

test_nodes_offline_while_the_app_is_connected_get_the_usual_advice() {
    health_setup
    fake_ts_app
    export FAKE_HOST_TS FAKE_HOST_TS_ONLINE=false      # the app is connected: Tailscale is reachable
    FAKE_HOST_TS=$(ts_status '{}' '[]')
    local out
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_not_contains "$out" 'Every Tailscale node'
    assert_contains "$out" 'kit-media (media-tailscale): Running, online=false'
    assert_contains "$out" 'docker restart media-tailscale'
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
    assert_eq 1 "$(grep -c '"name":"Server health"' "$FAKE_CURL_DIR/homarr-widget-imports")"
    # Glances' Mac Host Info comes in too (two widgets in all)
    assert_contains "$out" 'Homarr: Mac Host Info widget (Management → Custom widgets'
    assert_eq 2 "$(grep -c . "$FAKE_CURL_DIR/homarr-widget-imports")"
    out=$(kit install 2>&1) || fail "second install failed: $out"
    assert_contains "$out" 'Homarr: Server health widget (already there)'
    assert_contains "$out" 'Homarr: Mac Host Info widget (already there)'
    assert_eq 2 "$(grep -c . "$FAKE_CURL_DIR/homarr-widget-imports")"
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

# ---------------------------------------------------------------- external drives

# A drive the media is on: missing fails (host:media) with how to mount it; low space warns, then
# fails, in TB; this Mac's disk hints leave out folders that are on the drive
test_media_drive_mounted_and_its_space() {
    health_setup
    printf '%s\n' "MEDIA_VOLUMES=('/Volumes/Big Drive|/Volumes/Big Drive/Media')" "LOCAL_MEDIA=('$HOME/Games')" \
        "PROJECTS='media-stack romm'" "VOLUMES_media_stack='/Volumes/Big Drive'" "VOLUMES_romm=''" \
        "NATIVE_APPS=('Plex|32400|/identity|fail|job:plex|')" >>"$KIT_SERVER_DIR/kit/runtime.conf"
    local out
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" 'Big Drive not mounted (/Volumes/Big Drive/Media)'
    assert_contains "$out" 'diskutil mount "Big Drive"'
    assert_contains "$out" 'so Plex, qBittorrent and the *arr apps see'
    assert_not_contains "$out" 'RomM'                   # its games aren't on that drive
    sample
    assert_eq fail "$(last_status)"
    assert_contains "$(tail -n 1 "$(samples_file)" | cut -f13)" 'host:media'
    out=$(FAKE_HOST_MOUNTS='/Volumes/Big Drive' "$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" 'Big Drive 50% free (9.3 TB)'
    out=$(FAKE_HOST_MOUNTS='/Volumes/Big Drive' FAKE_HOST_MEDIA_DISK=93 "$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" 'Big Drive 7% free (1.3 TB)'
    assert_contains "$out" 'du -sh /Volumes/Big\ Drive/*'
    out=$(FAKE_HOST_MOUNTS='/Volumes/Big Drive' FAKE_HOST_MEDIA_DISK=97 FAKE_HOST_DISK=95 "$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" 'Big Drive 3% free'
    assert_contains "$out" 'du -sh ~/server/appdata/* ~/server/backups/* ~/Games/* 2>/dev/null'
    assert_not_contains "$out" 'Media/*'    # the drive's folder isn't on this Mac's disk
}

# A drive mounted at "/Volumes/<name> 1" (a folder was in its place): its own failure
# (host:media-stray) with how to clear the folder, not "mount it"; a second volume of the same
# name next to the right one only warns
test_media_drive_at_a_stray_mount_point() {
    health_setup
    printf '%s\n' "MEDIA_VOLUMES=('/Volumes/Big Drive|/Volumes/Big Drive/Media')" \
        "PROJECTS='media-stack'" "VOLUMES_media_stack='/Volumes/Big Drive'" >>"$KIT_SERVER_DIR/kit/runtime.conf"
    local out
    out=$(FAKE_HOST_MOUNTS='/Volumes/Big Drive 1' "$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" 'Big Drive mounted at /Volumes/Big Drive 1, not /Volumes/Big Drive'
    assert_contains "$out" 'diskutil unmount "/Volumes/Big Drive 1"'
    assert_contains "$out" 'sudo find "/Volumes/Big Drive" -depth -type d -empty -delete'
    assert_not_contains "$out" 'Big Drive not mounted'
    FAKE_HOST_MOUNTS='/Volumes/Big Drive 1' sample
    assert_eq fail "$(last_status)"
    assert_contains "$(tail -n 1 "$(samples_file)" | cut -f13)" 'host:media-stray'
    out=$(FAKE_HOST_MOUNTS='/Volumes/Big Drive|/Volumes/Big Drive 2' "$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" 'A second Big Drive is mounted at /Volumes/Big Drive 2'
    assert_contains "$out" 'Big Drive 50% free'
    out=$(FAKE_HOST_MOUNTS='/Volumes/Big Drive|/Volumes/Big Drive Backup' "$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_not_contains "$out" 'A second'               # another drive whose name starts the same
}

# Containers stopped because their drive isn't mounted: one diagnosis for them all, no "start it"
# advice for each, and their nodes' 502s aren't diagnosed again
test_containers_waiting_for_their_drive_get_one_diagnosis() {
    health_setup
    printf '%s\n' "MEDIA_VOLUMES=('/Volumes/Big Drive|/Volumes/Big Drive/Media')" >>"$KIT_SERVER_DIR/kit/runtime.conf"
    local out d=$KIT_SERVER_DIR/media-stack
    out=$(FAKE_HOST_CONTAINERS="/sonarr|sonarr:latest|exited||127|false|0|sonarr|$d|unless-stopped|$KIT_SERVER_DIR/appdata/media-stack/sonarr;/Volumes/Big Drive/Media;|
/radarr|radarr:latest|exited||127|false|0|radarr|$d|unless-stopped|/Volumes/Big Drive/Media;|
/homarr|homarr:latest|exited||1|false|0|homarr|$d|unless-stopped|$KIT_SERVER_DIR/appdata/media-stack/homarr;|" \
        "$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" "sonarr: stopped (its drive Big Drive isn't mounted)"
    assert_contains "$out" "radarr: stopped (its drive Big Drive isn't mounted)"
    assert_contains "$out" 'sonarr and radarr stay stopped until that drive is mounted'
    assert_contains "$out" "cd $d && docker compose up -d"$'\n'
    assert_not_contains "$out" 'docker compose up -d sonarr'
    assert_contains "$out" 'homarr: stopped (exit code 1)'          # not on the drive: as before
    assert_contains "$out" 'docker compose up -d homarr'
}

# Backup copies never made: a warning that names the backup drive and copy-backups' reason, not
# another drive's problem
test_backup_copies_never_made_names_their_drive() {
    health_setup
    mkdir -p "$KIT_SERVER_DIR/logs"
    printf '%s\n' "BACKUP_DRIVE='/Volumes/Other'" >>"$KIT_SERVER_DIR/kit/runtime.conf"
    printf '%s\t%s\t%s\t%s\n' "$(date +%s)" skipped "/Volumes/Other isn't plugged in" '' \
        >"$KIT_SERVER_DIR/logs/copy-backups.status"
    local out
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" 'Backup copies to /Volumes/Other: last one never'
    assert_contains "$out" "aren't being copied to /Volumes/Other (/Volumes/Other isn't plugged in)"
    assert_not_contains "$out" 'reason above'
}

# Plex down because its runner is waiting for the library's drive: no kickstart, just that
test_a_native_app_waiting_for_its_drive_says_so() {
    health_setup
    mkdir -p "$KIT_SERVER_DIR/logs"
    printf '%s\n' "NATIVE_APPS=('Plex|32400|/identity|fail|job:plex|$KIT_SERVER_DIR/logs/plex.log')" \
        >>"$KIT_SERVER_DIR/kit/runtime.conf"
    printf '%s\n' '22:39:12  Waiting for /Volumes/Big Drive to be mounted before starting (the library is there)' \
        >"$KIT_SERVER_DIR/logs/plex.log"
    local out
    out=$(FAKE_CURL_DOWN=32400 "$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" "Plex isn't answering on port 32400"
    assert_contains "$out" "waiting for its library's drive to be mounted"
    assert_not_contains "$out" 'kickstart -k'
    echo '22:41:02  Starting /Applications/Plex Media Server.app/Contents/MacOS/Plex Media Server' >>"$KIT_SERVER_DIR/logs/plex.log"
    out=$(FAKE_CURL_DOWN=32400 "$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" 'kickstart -k'
}

test_a_long_quiet_maintenance_window_says_to_close_it() {
    health_setup
    printf '%s\t%s\t%s\n' "$(( $(date +%s) - 3600 ))" "$(( $(date +%s) + 3600 ))" 'moving data' \
        >"$KIT_SERVER_DIR/logs/health/.maintenance" 2>/dev/null || {
        mkdir -p "$KIT_SERVER_DIR/logs/health"
        printf '%s\t%s\t%s\n' "$(( $(date +%s) - 3600 ))" "$(( $(date +%s) + 3600 ))" 'moving data' >"$KIT_SERVER_DIR/logs/health/.maintenance"
    }
    local out
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" "The maintenance window has been open 1h 0m and everything is healthy"
    assert_contains "$out" 'end-maintenance'
}

# ---------------------------------------------------------------- forwarded port

# Gluetun (healthy) and qBittorrent, started that many seconds ago, with port forwarding on;
# qBittorrent listens on 51413, Gluetun forwards 60123 (got an hour ago)
port_setup() {      # gluetun-age qbittorrent-age [gluetun health]
    health_setup
    mkdir -p "$KIT_SERVER_DIR/media-stack"
    printf '%s\n' "VPN_PORT_FORWARDING='on'" >"$KIT_SERVER_DIR/media-stack/.env"
    QBIT=$TEST_TMP/qbit-port
    echo 51413 >"$QBIT"
    local now; now=$(date +%s)
    export FAKE_HOST_QBIT=$QBIT FAKE_HOST_FWD='60123|3600'
    FAKE_HOST_CONTAINERS="/gluetun|qmcgaw/gluetun:latest|running|${3:-healthy}|0|false|0|gluetun||unless-stopped|||$(date -u -r $((now - $1)) '+%Y-%m-%dT%H:%M:%S').123456789Z|gid|default
/qbittorrent|lscr.io/linuxserver/qbittorrent:latest|running||0|false|0|qbittorrent||unless-stopped|||$(date -u -r $((now - $2)) '+%Y-%m-%dT%H:%M:%S').5Z|qid|container:gid"
    export FAKE_HOST_CONTAINERS
}
fixes_log() { cat "$KIT_SERVER_DIR/logs/health/fixes.log" 2>/dev/null; }

test_port_sync_ok_when_qbittorrent_has_the_forwarded_port() {
    port_setup 7200 7200
    echo 60123 >"$QBIT"
    local out
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" "qBittorrent listens on Gluetun's forwarded port (60123)"
    assert_not_contains "$out" 'Hardlinks: a file'
    assert_eq '' "$(fixes_log)"
}

test_port_sync_mismatch_is_fixed_and_still_a_failure() {
    port_setup 7200 7200
    local out
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" "qBittorrent listened on port 51413, not Gluetun's forwarded port 60123: set it to 60123"
    assert_contains "$out" 'check-health has set the port'
    assert_eq 60123 "$(cat "$QBIT")"
    assert_contains "$(fixes_log)" "set qBittorrent's listening port from 51413 to 60123"
    # In the log: a failure naming both ports, a snapshot, an alert; recovered at the next sample
    echo 51413 >"$QBIT"
    sample
    assert_eq fail "$(last_status)"
    assert_contains "$(tail -n 1 "$(samples_file)" | cut -f13)" 'media:port-sync(qBittorrent 51413, Gluetun 60123)'
    assert_contains "$(cat "$FAKE_CURL_LOG")" "POST hc-ping.com/${HC_URL##*/}/fail"
    assert_eq 1 "$(grep -c "POST ntfy.sh/$TOPIC" "$FAKE_CURL_LOG")"
    ls -d "$KIT_SERVER_DIR"/logs/health/incidents/*-down >/dev/null 2>&1 || fail "no down snapshot"
    assert_contains "$(cat "$KIT_SERVER_DIR/logs/health/web/status.json")" 'qBittorrent port out of sync'
    age_samples 300
    sample
    assert_eq ok "$(last_status)"
    assert_eq 2 "$(grep -c "POST ntfy.sh/$TOPIC" "$FAKE_CURL_LOG")"   # recovered
}

# A corrupted setting (seen in a real qBittorrent 5.3): a negative listen_port gets fixed too
test_port_sync_fixes_an_impossible_port() {
    port_setup 7200 7200
    echo -1260136216 >"$QBIT"
    local out
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" "qBittorrent listened on an impossible port (-1260136216), not Gluetun's forwarded port 60123: set it to 60123"
    assert_not_contains "$out" "its API doesn't answer"
    assert_eq 60123 "$(cat "$QBIT")"
    assert_contains "$(fixes_log)" "from -1260136216 to 60123"
}

# A port file that isn't one port is never pushed into qBittorrent
test_port_sync_leaves_qbittorrent_alone_when_the_port_file_is_wrong() {
    port_setup 7200 7200
    FAKE_HOST_FWD='402591794321640|3600'
    local out
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" "Gluetun's forwarded port file says 402591794321640, which isn't a port"
    assert_eq 51413 "$(cat "$QBIT")"
    assert_eq '' "$(fixes_log)"
}

test_port_sync_fix_inside_the_startup_window_is_only_noted() {
    port_setup 7200 120         # qBittorrent just started
    local out
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" "qBittorrent listened on port 51413: set it to Gluetun's forwarded port 60123"
    assert_eq 60123 "$(cat "$QBIT")"
    assert_contains "$(fixes_log)" 'from 51413 to 60123'
    port_setup 7200 7200        # an old pair, but the port changed two minutes ago
    FAKE_HOST_FWD='60123|120'
    echo 51413 >"$QBIT"
    sample
    assert_eq ok "$(last_status)"
    assert_eq 60123 "$(cat "$QBIT")"
}

test_port_sync_that_cant_be_fixed_says_so() {
    port_setup 7200 120
    local out
    out=$(FAKE_HOST_QBIT_STUCK=1 "$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" "qBittorrent listens on port 51413, but Gluetun forwards 60123, and setting it didn't work"
    assert_contains "$out" 'Settings → Connection → Listening port'
    assert_eq '' "$(fixes_log)"
}

test_port_sync_skipped_without_forwarding_or_qbittorrent() {
    port_setup 7200 7200
    printf '%s\n' "VPN_PORT_FORWARDING='off'" >"$KIT_SERVER_DIR/media-stack/.env"     # NordVPN
    local out
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_not_contains "$out" 'forwarded port'
    assert_eq 51413 "$(cat "$QBIT")"
    port_setup 7200 7200
    FAKE_HOST_CONTAINERS=${FAKE_HOST_CONTAINERS%%$'\n'*}                            # no qBittorrent
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_not_contains "$out" 'forwarded port'
}

test_port_sync_waits_for_gluetun_and_qbittorrent_to_start() {
    port_setup 60 60 starting
    local out
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" 'Forwarded port not checked yet (Gluetun is still connecting)'
    port_setup 7200 30
    rm -f "$QBIT"                                       # qBittorrent's API isn't up yet
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" "qBittorrent's listening port not checked (its API doesn't answer yet)"
    port_setup 120 120
    FAKE_HOST_FWD=''                                    # no port from the VPN yet
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" 'Gluetun has no forwarded port yet (it started 2m ago)'
    assert_not_contains "$out" 'media:'
}

# Gluetun restarted by itself and qBittorrent didn't: it's on Gluetun's old network, so
# check-health restarts it, logs it and fails (an outage happened); its port waits for it
test_qbittorrent_left_on_gluetuns_old_network_is_restarted() {
    port_setup 300 7200
    rm -f "$QBIT"                                       # unreachable through Gluetun
    export FAKE_HOST_LOG=$TEST_TMP/host.log
    local out
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" "qbittorrent was cut off: gluetun restarted 5m ago and qbittorrent stayed on its old network. Restarted qbittorrent"
    assert_contains "$out" 'docker restart gluetun qbittorrent'
    assert_contains "$out" "qBittorrent's listening port not checked (its API doesn't answer yet)"
    assert_contains "$(cat "$FAKE_HOST_LOG")" 'docker restart qbittorrent'
    assert_contains "$(fixes_log)" "restarted qbittorrent, which was left on gluetun's network from before gluetun restarted"
    sample
    assert_eq fail "$(last_status)"
    assert_contains "$(tail -n 1 "$(samples_file)" | cut -f13)" 'net:stale(qbittorrent)'
    # A restart that fails says so
    : >"$FAKE_HOST_LOG"
    out=$(FAKE_HOST_RESTART_FAILS=1 "$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" 'and restarting qbittorrent didn'"'"'t work'
    # Started after Gluetun (the normal order): left alone
    port_setup 7200 300
    : >"$FAKE_HOST_LOG"
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_not_contains "$out" 'cut off'
    assert_eq '' "$(cat "$FAKE_HOST_LOG")"
}

test_no_forwarded_port_long_after_gluetun_started_warns() {
    port_setup 3600 3600
    FAKE_HOST_FWD=''
    local out
    out=$("$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" 'Gluetun has no forwarded port (port forwarding is on)'
    assert_contains "$out" 'docker restart gluetun qbittorrent && check-media-stack'
    sample
    assert_eq warn "$(last_status)"
    assert_contains "$(tail -n 1 "$(samples_file)" | cut -f13)" 'media:no-forwarded-port'
}
