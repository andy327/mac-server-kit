# shellcheck shell=bash
# Connecting the apps (lib/api.sh and modules/media-stack/hooks/wire), against tests/fake-curl

secrets_src() {     # a filled-in secrets file
    S=$TEST_TMP/secrets-src.conf
    printf '%s\n' "WIREGUARD_PRIVATE_KEY=\"$FAKE_WG\"" "TS_AUTHKEY=\"$FAKE_TSKEY\"" >"$S"
}
stored() { cat "$FAKE_CURL_DIR/127.0.0.1_$1" 2>/dev/null; }    # port_api_... -> what the fake app holds
posts() { grep -c '^POST ' "$FAKE_CURL_LOG"; }

test_first_install_connects_the_apps() {
    secrets_src
    local out
    out=$(kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Sonarr: library folder /tv'
    assert_contains "$(stored 8989_api_v3_rootfolder)" '"path":"/tv"'
    assert_contains "$(stored 7878_api_v3_rootfolder)" '"path":"/movies"'
    local dc; dc=$(stored 8989_api_v3_downloadclient)
    assert_contains "$dc" '{"name":"host","value":"gluetun"}'
    assert_contains "$dc" '{"name":"tvCategory","value":"tv-sonarr"}'
    local pw; pw=$(sed -n 's/^QBITTORRENT_PASSWORD="\(.*\)"$/\1/p' "$KIT_SERVER_DIR/kit/generated-secrets.conf")
    assert_contains "$dc" "{\"name\":\"password\",\"value\":\"$pw\"}"
    assert_contains "$(stored 7878_api_v3_downloadclient)" '{"name":"movieCategory","value":"radarr"}'
    assert_contains "$(stored 9696_api_v1_tag)" '"label":"flaresolverr"'
    assert_contains "$(stored 9696_api_v1_indexerProxy)" '"tags":[1]'
    local apps; apps=$(stored 9696_api_v1_applications)
    assert_contains "$apps" '"baseUrl","value":"http://sonarr:8989"'
    assert_contains "$apps" '5070'                       # anime, as in the reference stack
    local sk; sk=$(sed -n 's|.*<ApiKey>\(.*\)</ApiKey>.*|\1|p' "$KIT_SERVER_DIR/appdata/media-stack/sonarr/config.xml")
    assert_contains "$apps" "{\"name\":\"apiKey\",\"value\":\"$sk\"}"
    assert_contains "$out" 'After you sign in to it, ./kit install connects it'
}

test_second_install_creates_nothing() {
    secrets_src
    kit install --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    local before; before=$(posts)
    local out
    out=$(kit install 2>&1) || fail "second install failed: $out"
    assert_eq "$before" "$(posts)" "the second install posted again"
    assert_contains "$out" 'Sonarr: library folder /tv (already set)'
}

test_a_failing_app_only_warns() {
    secrets_src
    local out
    out=$(FAKE_CURL_FAIL=7878 kit install --secrets "$S" 2>&1) || fail "install should still succeed: $out"
    assert_contains "$out" 'Radarr: library folder /movies: couldn'"'"'t read the current settings (HTTP 500: Failed on purpose)'
    assert_contains "$out" 'Sonarr: library folder /tv'
    assert_contains "$out" "couldn't be made (above)"
    out=$(FAKE_CURL_DOWN=9696 kit install 2>&1) || fail "install should still succeed: $out"
    assert_contains "$out" 'Prowlarr: flaresolverr tag: couldn'"'"'t read the current settings (no answer)'
    assert_contains "$out" 'add the proxy by hand'
}

# shellcheck disable=SC2034  # API_STATUS and API_BODY are read by api_error
test_a_refused_post_warns_with_the_apps_message() {
    load_libs
    API_BODY='[{"propertyName":"Host","errorMessage":"Unable to connect to qBittorrent","severity":"error"}]'
    API_STATUS=400
    assert_eq 'HTTP 400: Unable to connect to qBittorrent' "$(api_error)"
    API_BODY='{"status":403,"error":"You do not have permission"}'
    API_STATUS=403
    assert_eq 'HTTP 403: You do not have permission' "$(api_error)"
}

test_seerr_is_connected_once_someone_has_signed_in() {
    secrets_src
    kit install --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    mkdir -p "$KIT_SERVER_DIR/appdata/media-stack/seerr"
    printf '{\n  "clientId": "x",\n  "main": {\n    "apiKey": "seerr-key-1"\n  }\n}\n' \
        >"$KIT_SERVER_DIR/appdata/media-stack/seerr/settings.json"
    local out
    out=$(FAKE_SEERR_INIT=1 kit install 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Seerr: sonarr for requests'
    local s; s=$(stored 5055_api_v1_settings_sonarr)
    assert_contains "$s" '"hostname":"sonarr"'
    assert_contains "$s" '"activeProfileId":4'          # the first profile Seerr's test call lists
    assert_contains "$s" '"activeDirectory":"/tv"'
    assert_contains "$(stored 5055_api_v1_settings_radarr)" '"activeDirectory":"/movies"'
    out=$(FAKE_SEERR_INIT=1 kit install 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Seerr: sonarr for requests (already set)'
}

# shellcheck disable=SC2034  # API_BODY is read by api_id_of
test_json_helpers() {
    load_libs
    assert_eq '{"a":[1,2],"b":"x y"}' "$(printf '{\n  "a": [ 1,2 ],\n  "b":   "x y"\n}' | json_flat)"
    API_BODY='[{"label":"other","id":3},{"label":"flaresolverr","id":7}]'
    assert_eq 7 "$(api_id_of label flaresolverr)"
    assert_eq 'a\"b\\c' "$(json_str 'a"b\c')"
}
