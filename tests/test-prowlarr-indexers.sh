# shellcheck shell=bash
# Prowlarr's indexers (modules/media-stack/hooks/prowlarr-indexers.sh): the kit's suggested public
# indexers, added by the wire hook to a Prowlarr with none, and left alone after. Against
# tests/fake-curl, whose Prowlarr has a template for each of the defaults and its Standard profile.

secrets_src() {     # a filled-in secrets file
    S=$TEST_TMP/secrets-src.conf
    printf '%s\n' "WIREGUARD_PRIVATE_KEY=\"$FAKE_WG\"" "TS_AUTHKEY=\"$FAKE_TSKEY\"" >"$S"
}
stored() { cat "$FAKE_CURL_DIR/127.0.0.1_9696_api_v1_$1" 2>/dev/null; }
indexer() { stored indexer | grep "\"definitionName\":\"$1\""; }
mark() { cat "$KIT_SERVER_DIR/appdata/media-stack/prowlarr/kit-indexers" 2>/dev/null; }

test_defaults_name_no_machine_and_parse() {
    load_libs
    # shellcheck source=../modules/media-stack/hooks/prowlarr-indexers.sh
    . "$TEST_ROOT/modules/media-stack/hooks/prowlarr-indexers.sh"
    local n
    n=$(pix_data | grep -v '^#' | grep -c '^[^|]*|[0-9][0-9]*|[^|]*|[^|][^|]*$')
    assert_eq 11 "$n"
    assert_eq 11 "$(pix_data | grep -vc '^#')"
    assert_not_contains "$(pix_data)" 'torrentdownloads|'
}

test_first_install_adds_the_defaults() {
    secrets_src
    local out
    out=$(kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Prowlarr: sync profile Interactive only'
    assert_contains "$out" 'Prowlarr: indexer Nyaa.si'
    assert_contains "$out" 'Prowlarr: indexer Uindex'
    assert_eq 11 "$(stored indexer | grep -c .)"
    assert_eq '' "$(indexer torrentdownloads)"
    local ip; ip=$(stored appprofile | grep '"name":"Interactive only"')
    assert_contains "$ip" '"enableRss":false,"enableAutomaticSearch":false,"enableInteractiveSearch":true,"minimumSeeders":1'
    local pid; pid=$(printf '%s' "$ip" | sed -n 's/^{"id":\([0-9]*\),.*/\1/p')
    assert_eq 2 "$pid"
    # Standard's minimum seeders raised from Prowlarr's 1
    assert_contains "$out" 'Prowlarr: sync profile Standard, minimum seeders 3'
    assert_contains "$(stored appprofile | grep '"name":"Standard"')" '"minimumSeeders":3'
    # The flaresolverr tag (id 1) on 1337x, EZTV and Uindex only; Uindex on Interactive only
    local i
    for i in 1337x eztv uindex; do assert_contains "$(indexer "$i")" '"tags":[1]'; done
    assert_contains "$(indexer nyaasi)" '"tags":[]'
    assert_contains "$(indexer uindex)" "\"appProfileId\":$pid"
    assert_contains "$(indexer nyaasi)" '"appProfileId":1'
    assert_contains "$(indexer nyaasi)" '"priority":10'
    assert_contains "$(indexer uindex)" '"priority":40'
    assert_contains "$(indexer yts)" '"enable":true'
    assert_contains "$(indexer yts)" '{"name":"baseUrl","value":"https://yts.example/"}'
    assert_contains "$(mark)" 'seeded '
    assert_not_contains "$out" 'Prowlarr: add your indexers'       # its to-do is done
    : >"$FAKE_CURL_LOG"
    out=$(kit install 2>&1) || fail "second install failed: $out"
    assert_contains "$out" 'Prowlarr: indexers (seeded '
    assert_eq 11 "$(stored indexer | grep -c .)"
    assert_eq 0 "$(grep -c 'indexer/schema' "$FAKE_CURL_LOG")"
}

test_a_prowlarr_with_its_own_indexers_keeps_them() {
    secrets_src
    mkdir -p "$FAKE_CURL_DIR"
    echo '{"id":1,"name":"Mine","definitionName":"mine"}' >"$FAKE_CURL_DIR/127.0.0.1_9696_api_v1_indexer"
    local out
    out=$(kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Prowlarr: keeping its own indexers (it has indexers of its own)'
    assert_eq 1 "$(stored indexer | grep -c .)"
    assert_eq '' "$(stored appprofile | grep 'Interactive only')"
    assert_not_contains "$(stored appprofile)" '"minimumSeeders":3'
    assert_contains "$(mark)" 'kept (it has indexers of its own)'
}

test_a_missing_definition_or_a_refused_indexer_warns() {
    secrets_src
    local out
    out=$(FAKE_PROWLARR_MISSING=tokyotosho FAKE_PROWLARR_REFUSE=1337x kit install --secrets "$S" 2>&1) \
        || fail "install should still succeed: $out"
    assert_contains "$out" 'Prowlarr: this version has no tokyotosho indexer; skipped'
    # Refused: added anyway, turned off and then on with forceSave (no test)
    assert_contains "$out" "Prowlarr: indexer 1337x added, though Prowlarr's test failed (HTTP 400: Unable to connect to indexer"
    assert_contains "$out" "Prowlarr: some of the kit's suggested indexers didn't go in or failed Prowlarr's test"
    assert_eq 10 "$(stored indexer | grep -c .)"
    assert_contains "$(indexer 1337x)" '"enable":true'
    assert_contains "$(indexer 1337x)" '"tags":[1]'
    assert_contains "$(grep 'PUT .*9696/api/v1/indexer/' "$FAKE_CURL_LOG")" '?forceSave=true'
    assert_contains "$(mark)" 'seeded '
}

test_a_cloudflare_refusal_is_tried_again_through_flaresolverr() {
    secrets_src
    local out
    out=$(FAKE_PROWLARR_CLOUDFLARE='limetorrents eztv' kit install --secrets "$S" 2>&1) \
        || fail "install should still succeed: $out"
    assert_contains "$out" 'Prowlarr: indexer LimeTorrents (tagged flaresolverr: Cloudflare blocked it)'
    assert_contains "$out" 'Prowlarr: indexer EZTV'      # tagged already, so it went in first time
    assert_contains "$(indexer limetorrents)" '"tags":[1]'
    assert_contains "$(indexer limetorrents)" '"enable":true'
    assert_contains "$(indexer yts)" '"tags":[]'
    assert_eq 11 "$(stored indexer | grep -c .)"
    assert_not_contains "$out" "suggested indexers didn't go in"
}

test_a_cloudflare_refusal_that_flaresolverr_cant_pass_is_added_anyway() {
    secrets_src
    local out
    out=$(FAKE_PROWLARR_CLOUDFLARE=tokyotosho FAKE_PROWLARR_REFUSE=tokyotosho kit install --secrets "$S" 2>&1) \
        || fail "install should still succeed: $out"
    assert_contains "$out" "Prowlarr: indexer Tokyo Toshokan added, though Prowlarr's test failed (HTTP 400: Unable to connect to indexer"
    assert_contains "$(indexer tokyotosho)" '"tags":[1]'       # kept, for when FlareSolverr gets through
    assert_contains "$(indexer tokyotosho)" '"enable":true'
    assert_eq 11 "$(stored indexer | grep -c .)"
}

test_an_indexer_left_off_when_turning_it_on_fails() {
    secrets_src
    local out
    out=$(FAKE_PROWLARR_REFUSE=yts FAKE_CURL_FAIL='forceSave' kit install --secrets "$S" 2>&1) \
        || fail "install should still succeed: $out"
    assert_contains "$out" 'Prowlarr: indexer YTS added turned off (HTTP 400: Unable to connect to indexer'
    assert_contains "$(indexer yts)" '"enable":false'
}

test_a_failed_check_warns_and_tries_again() {
    secrets_src
    local out
    out=$(FAKE_CURL_FAIL=9696/api/v1/indexer kit install --secrets "$S" 2>&1) || fail "install should still succeed: $out"
    assert_contains "$out" "Prowlarr: couldn't check its indexers (its indexers: HTTP 500); the next ./kit install tries again"
    assert_eq '' "$(mark)"
    out=$(FAKE_CURL_FAIL=indexer/schema kit install 2>&1) || fail "second install should still succeed: $out"
    assert_contains "$out" "Prowlarr: couldn't add the kit's suggested indexers (its indexer templates: HTTP 500); the next ./kit install tries again"
    assert_eq '' "$(mark)"
    out=$(kit install 2>&1) || fail "third install failed: $out"
    assert_contains "$out" 'Prowlarr: indexer Uindex'
    assert_contains "$(mark)" 'seeded '
}

test_plan_adds_nothing() {
    secrets_src
    kit install --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    rm -f "$KIT_SERVER_DIR/appdata/media-stack/prowlarr/kit-indexers" "$FAKE_CURL_DIR"/127.0.0.1_9696_api_v1_indexer \
        "$KIT_SERVER_DIR/appdata/media-stack/sonarr/kit-fail-downloads" \
        "$FAKE_CURL_DIR"/127.0.0.1_9696_api_v1_appprofile
    : >"$FAKE_CURL_LOG"
    local out
    out=$(kit install --plan 2>&1) || fail "plan failed: $out"
    assert_contains "$out" "Prowlarr: the kit's suggested public indexers (it has none yet)"
    assert_eq '' "$(grep -v '^GET ' "$FAKE_CURL_LOG" | grep 9696)"
    assert_eq '' "$(grep -v '^GET ' "$FAKE_CURL_LOG" | grep 'api/v3/indexer')"
    assert_eq '' "$(mark)"
    assert_eq '' "$(fd_mark sonarr)"
}

# Sonarr's and Radarr's indexers: Fail Downloads on Executables and Potentially Dangerous, once per
# indexer (the wire hook, after Prowlarr's sync)
app_indexers() { cat "$FAKE_CURL_DIR/127.0.0.1_$1_api_v3_indexer" 2>/dev/null; }
fd_mark() { cat "$KIT_SERVER_DIR/appdata/media-stack/$1/kit-fail-downloads" 2>/dev/null; }

test_synced_indexers_fail_dangerous_downloads() {
    secrets_src
    local out
    out=$(kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$(grep 'POST .*9696/api/v1/command' "$FAKE_CURL_LOG")" 'command'
    assert_eq 11 "$(app_indexers 8989 | grep -c .)"
    assert_eq 11 "$(app_indexers 8989 | grep -c '"name":"failDownloads","value":\[0,1\]')"
    assert_eq 11 "$(app_indexers 7878 | grep -c '"name":"failDownloads","value":\[0,1\]')"
    assert_contains "$out" 'Sonarr: indexer EZTV (Prowlarr) fails downloads with executables or potentially dangerous files'
    assert_contains "$out" 'Radarr: indexer YTS (Prowlarr) fails downloads'
    assert_contains "$(grep 'PUT .*8989/api/v3/indexer/' "$FAKE_CURL_LOG")" '?forceSave=true'
    assert_eq 11 "$(fd_mark sonarr | grep -c .)"
    # The second run leaves them alone, even one changed by hand since
    sed -i '' 's/"value":\[0,1\]/"value":[]/' "$FAKE_CURL_DIR/127.0.0.1_8989_api_v3_indexer"
    : >"$FAKE_CURL_LOG"
    out=$(kit install 2>&1) || fail "second install failed: $out"
    assert_eq '' "$(grep 'PUT .*/api/v3/indexer/' "$FAKE_CURL_LOG")"
    assert_eq 0 "$(grep -c 'POST .*9696/api/v1/command' "$FAKE_CURL_LOG")"
}

test_a_new_indexer_gets_it_and_one_set_already_is_kept() {
    secrets_src
    mkdir -p "$FAKE_CURL_DIR"
    echo '{"id":1,"name":"Mine","definitionName":"mine"}' >"$FAKE_CURL_DIR/127.0.0.1_9696_api_v1_indexer"
    printf '%s\n' '{"id":1,"name":"Set","implementation":"Torznab","fields":[{"name":"failDownloads","value":[0]}]}' \
        '{"id":2,"name":"Old","implementation":"Torznab","fields":[{"name":"baseUrl","value":"x"}]}' \
        >"$FAKE_CURL_DIR/127.0.0.1_8989_api_v3_indexer"
    local out
    out=$(kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Sonarr: Fail Downloads already set on its indexers'
    assert_contains "$(app_indexers 8989)" '"name":"Set","implementation":"Torznab","fields":[{"name":"failDownloads","value":[0]}]'
    assert_eq 1 "$(fd_mark sonarr)"       # Old has no such field (an older Sonarr): not looked at
    printf '%s\n' '{"id":3,"name":"New","implementation":"Torznab","fields":[{"name":"failDownloads","value":[]}]}' \
        >>"$FAKE_CURL_DIR/127.0.0.1_8989_api_v3_indexer"
    out=$(kit install 2>&1) || fail "second install failed: $out"
    assert_contains "$out" 'Sonarr: indexer New fails downloads'
    assert_contains "$(app_indexers 8989 | grep '"id":3')" '"value":[0,1]'
    assert_eq '1 3' "$(fd_mark sonarr | tr '\n' ' ' | sed 's/ $//')"
}

test_a_failed_fail_downloads_update_warns_and_tries_again() {
    secrets_src
    local out
    out=$(FAKE_CURL_FAIL=8989/api/v3/indexer/ kit install --secrets "$S" 2>&1) || fail "install should still succeed: $out"
    assert_contains "$out" "Sonarr: indexer EZTV (Prowlarr): couldn't set Fail Downloads"
    assert_eq '' "$(fd_mark sonarr)"
    assert_eq 11 "$(fd_mark radarr | grep -c .)"
    out=$(kit install 2>&1) || fail "second install failed: $out"
    assert_eq 11 "$(app_indexers 8989 | grep -c '"value":\[0,1\]')"
    assert_eq 11 "$(fd_mark sonarr | grep -c .)"
}
