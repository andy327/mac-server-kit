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
    assert_contains "$(mark)" 'kept (it has indexers of its own)'
}

test_a_missing_definition_or_a_refused_indexer_warns() {
    secrets_src
    local out
    out=$(FAKE_PROWLARR_MISSING=tokyotosho FAKE_PROWLARR_REFUSE=1337x kit install --secrets "$S" 2>&1) \
        || fail "install should still succeed: $out"
    assert_contains "$out" 'Prowlarr: this version has no tokyotosho indexer; skipped'
    assert_contains "$out" 'Prowlarr: indexer 1337x: HTTP 400: Unable to connect to indexer'
    assert_contains "$out" "Prowlarr: some of the kit's suggested indexers didn't go in"
    assert_eq 9 "$(stored indexer | grep -c .)"
    assert_contains "$(mark)" 'seeded '
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
        "$FAKE_CURL_DIR"/127.0.0.1_9696_api_v1_appprofile
    : >"$FAKE_CURL_LOG"
    local out
    out=$(kit install --plan 2>&1) || fail "plan failed: $out"
    assert_contains "$out" "Prowlarr: the kit's suggested public indexers (it has none yet)"
    assert_eq '' "$(grep -v '^GET ' "$FAKE_CURL_LOG" | grep 9696)"
    assert_eq '' "$(mark)"
}
