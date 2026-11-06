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

test_sonarr_radarr_and_prowlarr_get_the_kits_login() {
    secrets_src
    local out
    out=$(kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    local pw; pw=$(sed -n 's/^ARR_PASSWORD="\(.*\)"$/\1/p' "$KIT_SERVER_DIR/kit/generated-secrets.conf")
    [ -n "$pw" ] || fail "no ARR_PASSWORD generated"
    assert_contains "$out" 'Sonarr: login (admin, with ARR_PASSWORD)'
    assert_contains "$out" 'Prowlarr: login (admin, with ARR_PASSWORD)'
    local h; h=$(stored 7878_api_v3_config_host)
    assert_contains "$h" '"authenticationMethod":"forms"'
    assert_contains "$h" '"username":"admin"'
    assert_contains "$h" "\"password\":\"$pw\""
    assert_contains "$(stored 9696_api_v1_config_host)" '"username":"admin"'
    assert_contains "$(grep '^PUT ' "$FAKE_CURL_LOG")" '127.0.0.1:8989/api/v3/config/host/1'
    out=$(kit install 2>&1) || fail "second install failed: $out"
    assert_contains "$out" 'Sonarr: login (already set)'
    assert_not_contains "$out" 'create a login'
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
    assert_contains "$s" '"activeProfileName":"Any"'
    assert_contains "$(stored 5055_api_v1_settings_radarr)" '"minimumAvailability":"released"'
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

# ---- Homarr
homarr() { cat "$FAKE_CURL_DIR/homarr-$1" 2>/dev/null; }    # apps | integrations | keys | step

test_homarr_gets_an_admin_a_key_and_tiles() {
    secrets_src
    local out
    out=$(kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Homarr: admin account (admin) and an API key for the kit'
    assert_eq setup "$(homarr step)"                 # its setup page is left for the user
    local gen; gen=$(cat "$KIT_SERVER_DIR/kit/generated-secrets.conf")
    assert_contains "$gen" "HOMARR_API_KEY=\"$(homarr keys)\""
    assert_contains "$gen" 'HOMARR_ADMIN_PASSWORD="'
    local apps; apps=$(homarr apps)
    assert_contains "$apps" '"name":"Sonarr"'
    assert_contains "$apps" '"href":"https://media.tail0000.ts.net:8989"'   # check-private: allow
    assert_contains "$apps" '"href":"https://media.tail0000.ts.net"'        # check-private: allow
    assert_contains "$apps" '"iconUrl":"https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons@master/svg/qbittorrent.svg"'
    assert_not_contains "$apps" Gluetun               # a widget connection only, no tile
    local int; int=$(homarr integrations)
    local sk; sk=$(sed -n 's|.*<ApiKey>\(.*\)</ApiKey>.*|\1|p' "$KIT_SERVER_DIR/appdata/media-stack/sonarr/config.xml")
    assert_contains "$int" "\"kind\":\"sonarr\",\"secrets\":[{\"kind\":\"apiKey\",\"value\":\"$sk\"}]"
    assert_contains "$int" '"url":"http://gluetun:8080","kind":"qBittorrent","secrets":[{"kind":"username","value":"admin"},{"kind":"password"'
    assert_contains "$int" '"kind":"gluetun"'
    assert_contains "$int" '"app":{"id":"app2"}'      # linked to its tile
    assert_not_contains "$int" '"kind":"seerr"'       # waits for Seerr's sign-in
    local bk; bk=$(sed -n "s/^  apikey: '\(.*\)'$/\1/p" "$KIT_SERVER_DIR/appdata/media-stack/bazarr/config/config.yaml" | head -n 1)
    assert_contains "$int" "\"kind\":\"bazarr\",\"secrets\":[{\"kind\":\"apiKey\",\"value\":\"$bk\"}]"
}

test_homarr_second_install_creates_nothing() {
    secrets_src
    kit install --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    local apps int keys
    apps=$(homarr apps) int=$(homarr integrations) keys=$(homarr keys)
    local out
    out=$(kit install 2>&1) || fail "second install failed: $out"
    assert_eq "$apps" "$(homarr apps)"
    assert_eq "$int" "$(homarr integrations)"
    assert_eq "$keys" "$(homarr keys)"
    assert_contains "$out" 'Homarr: Sonarr tile (already there)'
}

test_homarr_integrations_off_makes_tiles_only() {
    secrets_src
    printf 'HOMARR_INTEGRATIONS=off\n' >"$TEST_TMP/a.conf"
    kit install --answers "$TEST_TMP/a.conf" --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    assert_contains "$(homarr apps)" '"name":"Radarr"'
    assert_eq '' "$(homarr integrations)"
}

test_homarr_set_up_by_hand_needs_the_users_key() {
    secrets_src
    local out
    out=$(FAKE_HOMARR_SET_UP=1 kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Homarr already has an account, so the kit needs a key from you'
    assert_eq '' "$(homarr apps)"
    printf 'HOMARR_API_KEY="mine.0123456789abcdef0123"\n' >>"$KIT_SERVER_DIR/secrets.conf"
    out=$(FAKE_HOMARR_SET_UP=1 FAKE_HOMARR_KEY=mine.0123456789abcdef0123 kit install 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Homarr: Sonarr tile'
    out=$(FAKE_HOMARR_SET_UP=1 kit install 2>&1) || fail "install should still succeed: $out"
    assert_contains "$out" "secrets.conf isn't accepted (HTTP 401: UNAUTHORIZED); no tiles made"
}

test_homarr_widget_failure_only_warns() {
    secrets_src
    local out
    out=$(FAKE_CURL_FAIL='"kind":"radarr"' kit install --secrets "$S" 2>&1) || fail "install should still succeed: $out"
    assert_contains "$out" 'Homarr: Radarr widget connection: HTTP 200: Unable to connect to the integration'
    assert_contains "$out" 'Homarr: Sonarr widget connection'
}

test_homarr_seerr_widget_after_sign_in() {
    secrets_src
    kit install --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    mkdir -p "$KIT_SERVER_DIR/appdata/media-stack/seerr"
    printf '{\n  "main": {\n    "apiKey": "seerr-key-1"\n  }\n}\n' >"$KIT_SERVER_DIR/appdata/media-stack/seerr/settings.json"
    local out
    out=$(FAKE_SEERR_INIT=1 kit install 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Homarr: Seerr widget connection'
    assert_contains "$(homarr integrations)" '"kind":"seerr","secrets":[{"kind":"apiKey","value":"seerr-key-1"}],"attemptSearchEngineCreation":false,"app":{"id":"app1"}'
}

# shellcheck disable=SC2034  # API_STATUS and API_BODY are read by api_error
test_homarr_errors_read_well() {
    load_libs
    API_STATUS=200
    API_BODY='{"result":{"data":{"json":{"error":{"type":"authorization","name":"s","message":"Unable to connect to the integration","data":{"statusCode":401,"reason":"unauthorized"},"cause":null}},"meta":{"v":1}}}}'
    assert_eq 'HTTP 200: Unable to connect to the integration (unauthorized)' "$(api_error)"
    API_STATUS=403
    API_BODY='{"error":{"json":{"message":"This onboarding session is not claimed.","code":-32003}}}'
    assert_eq 'HTTP 403: This onboarding session is not claimed.' "$(api_error)"
}
