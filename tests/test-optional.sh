# shellcheck shell=bash
# The tracearr and wud modules: joining the media stack's compose project, their Tailscale
# addresses, generated secrets, backups, Homarr tiles and widget connections, and the labels that
# keep WUD to what update-all pulls. Docker and the apps are fakes (fake-docker, fake-curl).

secrets_src() {     # a filled-in secrets file
    S=$TEST_TMP/secrets-src.conf
    printf '%s\n' "WIREGUARD_PRIVATE_KEY=\"$FAKE_WG\"" "TS_AUTHKEY=\"$FAKE_TSKEY\"" >"$S"
}
homarr() { cat "$FAKE_CURL_DIR/homarr-$1" 2>/dev/null; }    # apps | integrations
gen() { sed -n "s/^$1=\"\\(.*\\)\"\$/\\1/p" "$KIT_SERVER_DIR/kit/generated-secrets.conf"; }

install_with() {    # modules: a first install with these optional modules
    secrets_src
    printf 'MEDIA_SERVER=plex\nMODULES=%s\n' "$1" >"$TEST_TMP/answers-src.conf"
    OUT=$(kit install --secrets "$S" --answers "$TEST_TMP/answers-src.conf" 2>&1) || fail "install failed: $OUT"
    MS=$KIT_SERVER_DIR/media-stack
}

test_tracearr_and_wud_join_the_media_stack() {
    install_with 'tracearr wud'
    assert_contains "$OUT" 'Modules: core media-stack plex tracearr wud'
    ls "$MS"/compose.d/*-tracearr.yml >/dev/null 2>&1 || fail "no tracearr compose file"
    ls "$MS"/compose.d/*-wud.yml >/dev/null 2>&1 || fail "no wud compose file"
    local env; env=$(cat "$MS/.env")
    local k
    for k in TRACEARR_DB_PASSWORD TRACEARR_JWT_SECRET TRACEARR_COOKIE_SECRET TRACEARR_AUTH_SECRET TRACEARR_CLAIM_CODE \
        WUD_ADMIN_PASSWORD WUD_SESSION_SECRET; do
        [ -n "$(gen "$k")" ] || fail "no generated $k"
        assert_contains "$env" "$k="
    done
    assert_contains "$env" "TS_HOSTNAME_TRACEARR='tracearr'"
    local lock; lock=$(cat "$MS/images.lock")
    for k in tracearr tracearr-db tracearr-redis tracearr-tailscale wud; do
        printf '%s\n' "$lock" | grep -q "^$k " || fail "$k isn't pinned"
    done
    assert_contains "$lock" 'tracearr-db timescale/timescaledb-ha:pg18@sha256:'
    # Tracearr on its own node, WUD on the media node's port 3030, both tailnet-only
    assert_contains "$(cat "$MS/tailscale/tracearr/serve.json")" '"Proxy": "http://tracearr:3000"'
    assert_not_contains "$(cat "$MS/tailscale/tracearr/serve.json")" 'AllowFunnel'
    assert_contains "$(cat "$MS/tailscale/media/serve.json")" '"Proxy": "http://wud:3000"'
    assert_contains "$OUT" 'Tracearr       https://tracearr.tail0000.ts.net'   # check-private: allow
    assert_contains "$OUT" 'WUD            https://media.tail0000.ts.net:3030'  # check-private: allow
    assert_contains "$OUT" 'TRACEARR_CLAIM_CODE'
    assert_contains "$OUT" 'Tracearr: add Plex by signing in with your Plex account'
    assert_not_contains "$OUT" 'jellyfin-proxy:8096 and an API key'
    # Backups check for their data, and leave out Tracearr's own backups
    local rc; rc=$(cat "$KIT_SERVER_DIR/kit/runtime.conf")
    assert_contains "$rc" 'tracearr/postgres/PG_VERSION tailscale-tracearr/tailscaled.state wud/wud.sqlite'
    assert_contains "$rc" './tracearr/backup'
}

test_wud_labels_keep_it_to_what_update_all_pulls() {
    install_with wud
    local zz; zz=$(cat "$MS/compose.d/zz-images.yml")
    # A release series hold: its newer releases
    assert_contains "$zz" "  homarr:
    image: ghcr.io/homarr-labs/homarr:v"
    assert_contains "$zz" "- 'wud.tag.include=^v2\\.\\d+(\\.\\d+)*\$\$'"
    # Any other tag: newer images of that tag only
    assert_contains "$zz" "- 'wud.tag.include=^stable-alpine\$\$'"
    assert_contains "$zz" "- 'wud.tag.include=^latest\$\$'"
    assert_contains "$zz" '- wud.watch.digest=true'
    # update-all rewrites the pins and keeps the labels
    (
        . "$TEST_ROOT/modules/core/bin/kit-runtime.sh"
        sed -i '' 's/^homarr \([^@]*\)@sha256:[0-9a-f]*/homarr \1@sha256:feedface/' "$MS/images.lock"
        zz_refresh "$MS"
    ) || fail "zz_refresh failed"
    zz=$(cat "$MS/compose.d/zz-images.yml")
    assert_contains "$zz" '@sha256:feedface'
    assert_contains "$zz" "- 'wud.tag.include=^v2\\.\\d+(\\.\\d+)*\$\$'"
}

test_without_wud_there_are_no_labels() {
    install_with tracearr
    assert_not_contains "$(cat "$MS/compose.d/zz-images.yml")" 'labels:'
}

test_homarr_gets_wud_and_tracearr_once_it_has_its_key() {
    install_with 'tracearr wud'
    local apps int
    apps=$(homarr apps) int=$(homarr integrations)
    assert_contains "$apps" '"name":"WUD"'
    assert_contains "$apps" '"href":"https://media.tail0000.ts.net:3030"'   # check-private: allow
    assert_contains "$apps" '"iconUrl":"https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons@master/svg/whats-up-docker.svg"'
    assert_contains "$int" "\"url\":\"http://wud:3000\",\"kind\":\"wud\",\"secrets\":[{\"kind\":\"username\",\"value\":\"admin\"},{\"kind\":\"password\",\"value\":\"$(gen WUD_ADMIN_PASSWORD)\"}]"
    # Tracearr: a tile now, the widget connection once its owner gives the kit its API key
    assert_contains "$apps" '"name":"Tracearr"'
    assert_contains "$apps" '"href":"https://tracearr.tail0000.ts.net"'     # check-private: allow
    assert_not_contains "$int" '"kind":"tracearr"'
    assert_contains "$OUT" 'Tracearr widget connection waits for TRACEARR_API_KEY'
    printf 'TRACEARR_API_KEY="trr_pub_testkey"\n' >>"$KIT_SERVER_DIR/secrets.conf"
    local out; out=$(kit install 2>&1) || fail "second install failed: $out"
    assert_contains "$out" 'Homarr: Tracearr tile (already there)'
    assert_contains "$out" 'Homarr: Tracearr widget connection'
    assert_contains "$(homarr integrations)" '"url":"http://tracearr:3000","kind":"tracearr","secrets":[{"kind":"apiKey","value":"trr_pub_testkey"}]'
    assert_eq 1 "$(homarr apps | grep -c '"name":"Tracearr"')"
}

test_tracearr_with_jellyfin_gets_its_steps() {
    secrets_src
    printf 'MEDIA_SERVER=jellyfin\nMODULES=tracearr\n' >"$TEST_TMP/answers-src.conf"
    OUT=$(kit install --secrets "$S" --answers "$TEST_TMP/answers-src.conf" 2>&1) || fail "install failed: $OUT"
    assert_contains "$OUT" 'Tracearr: add Jellyfin under Settings → Servers → Connections → Add Server'
    assert_not_contains "$OUT" 'Tracearr: add Plex'
}

# ---------------------------------------------------------------- show-logins

test_show_logins_lists_each_apps_sign_in() {
    install_with 'tracearr wud'
    printf 'ARR_PASSWORD="mine-from-secrets"\n' >>"$KIT_SERVER_DIR/secrets.conf"
    local out
    out=$("$KIT_SERVER_DIR/bin/show-logins" 2>&1) || fail "show-logins failed: $out"
    assert_contains "$out" 'Homarr       https://dashboard.tail0000.ts.net'        # check-private: allow
    assert_contains "$out" 'this Mac: http://localhost:7575'
    assert_contains "$out" "user: admin   password: $(gen HOMARR_ADMIN_PASSWORD)"
    assert_contains "$out" 'user: admin   password: mine-from-secrets'          # secrets.conf wins
    assert_contains "$out" "user: admin   password: $(gen WUD_ADMIN_PASSWORD)"
    assert_contains "$out" "the owner account you made; claim code (asked once, by its first page): $(gen TRACEARR_CLAIM_CODE)"
    assert_contains "$out" 'your Plex account'
    assert_not_contains "$out" 'Jellyfin'
    # runtime.conf holds the keys' names, not their values
    local rc; rc=$(cat "$KIT_SERVER_DIR/kit/runtime.conf")
    assert_contains "$rc" "|admin|HOMARR_ADMIN_PASSWORD|password'"
    assert_not_contains "$rc" "$(gen HOMARR_ADMIN_PASSWORD)"
    # One app, by any part of its name
    out=$("$KIT_SERVER_DIR/bin/show-logins" wu 2>&1) || fail "show-logins wu failed: $out"
    assert_contains "$out" 'WUD'
    assert_not_contains "$out" 'Homarr'
    assert_fails "$KIT_SERVER_DIR/bin/show-logins" nosuchapp
}

# Every key a logins file names is one the kit generates or asks for, so show-logins can find it
test_logins_files_name_known_keys() {
    local f m key bad=''
    for f in "$TEST_ROOT"/modules/*/logins; do
        m=$(basename "$(dirname "$f")")
        while IFS='|' read -r _ _ key _ _; do
            case "$key" in ''|'#'*) continue ;; esac
            grep -q "|$key|" "$TEST_ROOT"/modules/*/prompts || bad="$bad $m:$key"
        done <"$f"
        while IFS='|' read -r name _; do
            case "$name" in ''|'#'*) continue ;; esac
            grep -q "^$name|" "$TEST_ROOT/modules/$m/urls" || bad="$bad $m:$name(no urls line)"
        done <"$f"
    done
    [ -z "$bad" ] || fail "logins files name unknown keys or apps:$bad"
}
