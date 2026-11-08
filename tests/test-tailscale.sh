# shellcheck shell=bash
# Tailscale nodes (lib/tailscale.sh): serve.json, Funnel, the nodes' addresses, start hints

secrets_src() {     # a filled-in secrets file
    S=$TEST_TMP/secrets-src.conf
    printf '%s\n' "WIREGUARD_PRIVATE_KEY=\"$FAKE_WG\"" "TS_AUTHKEY=\"$FAKE_TSKEY\"" >"$S"
}
serve() { cat "$KIT_SERVER_DIR/media-stack/tailscale/$1/serve.json"; }
seerr_signed_in() {
    mkdir -p "$KIT_SERVER_DIR/appdata/media-stack/seerr"
    printf '{\n  "main": {\n    "apiKey": "seerr-key-1"\n  },\n  "public": {\n    "initialized": true\n  }\n}\n' \
        >"$KIT_SERVER_DIR/appdata/media-stack/seerr/settings.json"
}

test_install_writes_each_nodes_serve_config() {
    secrets_src
    kit install --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    local m; m=$(serve media)
    # shellcheck disable=SC2016  # ${TS_CERT_DOMAIN} is literal: Tailscale fills it in
    assert_contains "$m" '"${TS_CERT_DOMAIN}:443": { "Handlers": { "/": { "Proxy": "http://seerr:5055" } } }'
    assert_contains "$m" '"8080": { "HTTPS": true }'
    assert_contains "$m" '"Proxy": "http://gluetun:8080"'
    assert_contains "$(serve dashboard)" '"Proxy": "http://homarr:7575"'
    printf '%s' "$m" | /usr/bin/python3 -I -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null \
        || [ ! -x /usr/bin/python3 ] || fail "media serve.json isn't JSON: $m"
    local env; env=$(cat "$KIT_SERVER_DIR/media-stack/.env")
    assert_contains "$env" "TS_AUTHKEY='$FAKE_TSKEY'"
    assert_contains "$env" "TS_HOSTNAME_MEDIA='media'"
    assert_not_contains "$env" 'HOMARR_BASE_URL'
}

test_funnel_waits_until_seerr_is_set_up() {
    secrets_src
    local out
    out=$(kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_not_contains "$(serve media)" AllowFunnel
    assert_contains "$out" 'Seerr stays tailnet-only until'
    seerr_signed_in
    out=$(kit install 2>&1) || fail "install failed: $out"
    # shellcheck disable=SC2016
    assert_contains "$(serve media)" '"AllowFunnel": { "${TS_CERT_DOMAIN}:443": true }'
    assert_not_contains "$out" 'tailnet-only'
    assert_not_contains "$(serve dashboard)" AllowFunnel        # never public
}

test_tailnet_only_never_uses_funnel() {
    secrets_src
    printf 'EXPOSE_media=tailnet\n' >"$TEST_TMP/a.conf"
    seerr_signed_in
    kit install --answers "$TEST_TMP/a.conf" --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    assert_not_contains "$(serve media)" AllowFunnel
}

test_install_reads_the_nodes_addresses() {
    secrets_src
    local out
    out=$(kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Tailscale media: https://media.tail0000.ts.net'   # check-private: allow
    assert_contains "$(cat "$KIT_SERVER_DIR/kit/tailnet.conf")" 'TS_DNS_dashboard=dashboard.tail0000.ts.net'   # check-private: allow
    assert_contains "$out" 'Sonarr         https://media.tail0000.ts.net:8989'   # check-private: allow
    assert_contains "$out" 'this Mac: http://localhost:8989'
    assert_not_contains "$out" 'expires in 180 days'
}

test_untagged_or_renamed_nodes_warn() {
    secrets_src
    local out
    out=$(FAKE_TS_TAGS=0 FAKE_TS_TAKEN=media kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Tailscale media has no tag, so its login expires in 180 days'
    assert_contains "$out" 'The name media was taken in your tailnet, so this machine is media-1'
    assert_contains "$(cat "$KIT_SERVER_DIR/kit/tailnet.conf")" 'TS_DNS_media=media-1.'
}

test_bad_serve_lines_are_refused() {
    fake_modules
    mkmod svc KIND=base PROJECT=svc
    load_libs
    modules_discover
    printf 'web|443|/|sonarr:8989||\n' >"$KIT_MODULES_DIR/svc/serve"
    local out
    out=$(serve_lines svc svc 2>&1) && fail "should refuse: $out"
    assert_contains "$out" "bad target 'sonarr:8989' for web:443"
    printf 'web|https|/|http://web:80||\n' >"$KIT_MODULES_DIR/svc/serve"
    out=$(serve_lines svc svc 2>&1) && fail "should refuse: $out"
    assert_contains "$out" "bad port 'https'"
    printf 'web|443|/|http://web:80||\nweb|443|/api/|http://api:80||\n' >"$KIT_MODULES_DIR/svc/serve"
    assert_eq 'web|443|/|http://web:80|
web|443|/api/|http://api:80|' "$(serve_lines svc svc)"
    assert_contains "$(printf '443|/|http://web:80\n443|/api/|http://api:80\n' | serve_json no)" \
        '{ "/": { "Proxy": "http://web:80" }, "/api/": { "Proxy": "http://api:80" } }'
}

test_start_hints_only_for_services_that_are_down() {
    secrets_src
    local out
    out=$(FAKE_DOCKER_FAIL=up FAKE_DOCKER_PS='gluetun|running|healthy
media-tailscale|running|unhealthy
dashboard-tailscale|running|healthy' kit install --secrets "$S" 2>&1) && fail "install should stop"
    assert_contains "$out" "media-tailscale not healthy means it couldn't join your tailnet"
    assert_not_contains "$out" 'gluetun not healthy'
    assert_not_contains "$out" 'dashboard-tailscale not healthy'
    out=$(FAKE_DOCKER_FAIL=up kit install 2>&1) && fail "install should stop"
    assert_contains "$out" 'gluetun not healthy'                 # compose couldn't say: every hint
    # Still starting while another failed: Compose stopped waiting, so only the failure's hint
    out=$(FAKE_DOCKER_FAIL=up FAKE_DOCKER_PS='gluetun|running|unhealthy
media-tailscale|running|starting
dashboard-tailscale|running|healthy' kit install 2>&1) && fail "install should stop"
    assert_contains "$out" 'gluetun not healthy'
    assert_not_contains "$out" 'media-tailscale not healthy'
    # Only starting ones (the wait ran out): theirs
    out=$(FAKE_DOCKER_FAIL=up FAKE_DOCKER_PS='gluetun|running|healthy
media-tailscale|running|starting' kit install 2>&1) && fail "install should stop"
    assert_contains "$out" 'media-tailscale not healthy'
    assert_not_contains "$out" 'gluetun not healthy'
}
