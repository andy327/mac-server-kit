# shellcheck shell=bash
# The romm module: its own project, the platform folders, the admin the kit makes before anything
# serves it, the optional metadata keys, its Homarr tile and widget, and backups. Docker and
# RomM's API are fakes (fake-docker, fake-curl).

secrets_src() {     # a filled-in secrets file
    S=$TEST_TMP/secrets-src.conf
    printf '%s\n' "WIREGUARD_PRIVATE_KEY=\"$FAKE_WG\"" "TS_AUTHKEY=\"$FAKE_TSKEY\"" >"$S"
}
gen() { sed -n "s/^$1=\"\\(.*\\)\"\$/\\1/p" "$KIT_SERVER_DIR/kit/generated-secrets.conf"; }

install_with() {    # [answers-line...] [-- env...]: a first install with romm
    local envs=()
    secrets_src
    printf 'MEDIA_SERVER=plex\nMODULES=romm\n' >"$TEST_TMP/answers-src.conf"
    while [ $# -gt 0 ]; do
        [ "$1" = -- ] && { shift; envs=("$@"); break; }
        printf '%s\n' "$1" >>"$TEST_TMP/answers-src.conf"
        shift
    done
    OUT=$(env ${envs[@]+"${envs[@]}"} "$TEST_ROOT/kit" install --secrets "$S" --answers "$TEST_TMP/answers-src.conf" 2>&1) \
        || fail "install failed: $OUT"
    P=$KIT_SERVER_DIR/romm
    A=$KIT_SERVER_DIR/appdata/romm
}

test_romm_is_its_own_project_with_platform_folders() {
    install_with
    assert_contains "$OUT" 'Modules: core media-stack plex romm'
    local env; env=$(cat "$P/.env")
    assert_contains "$env" "GAMES_ROOT='$HOME/Games'"
    assert_contains "$env" "ROMM_DB_PASSWORD='$(gen ROMM_DB_PASSWORD)'"
    assert_contains "$env" "ROMM_AUTH_SECRET_KEY='$(gen ROMM_AUTH_SECRET_KEY)'"
    assert_contains "$env" "TS_HOSTNAME_ROMM='romm'"
    local lock; lock=$(cat "$P/images.lock")
    assert_contains "$lock" 'romm rommapp/romm:5@sha256:'
    assert_contains "$lock" 'romm-db mariadb:11.8@sha256:'
    printf '%s\n' "$lock" | grep -q '^romm-tailscale ' || fail "romm-tailscale isn't pinned"
    local p
    for p in gb gbc gba nes snes n64 genesis psx; do
        [ -d "$HOME/Games/roms/$p" ] && [ -d "$HOME/Games/bios/$p" ] || fail "no folders for $p"
    done
    assert_contains "$OUT" 'Games: ~/Games (new platform folders: gb gbc gba nes snes n64 genesis psx)'
    ls "$KIT_SERVER_DIR"/media-stack/compose.d/*-romm.yml >/dev/null 2>&1 || fail "no romm-proxy in the media stack"
    # A platform added later gets its folders; one taken off the list keeps them
    echo keep >"$HOME/Games/roms/psx/game.chd"
    # Typed by hand with capitals and a space: read as ps2,gba
    printf 'ROMM_PLATFORMS=PS2, gba\n' >>"$KIT_SERVER_DIR/answers.conf"
    local out
    out=$(kit install 2>&1) || fail "second install failed: $out"
    [ -d "$HOME/Games/roms/ps2" ] && [ -d "$HOME/Games/bios/ps2" ] || fail "no folders for ps2"
    assert_eq keep "$(cat "$HOME/Games/roms/psx/game.chd")"
    assert_contains "$out" 'Games: ~/Games (new platform folders: ps2)'
}

test_the_kit_makes_romms_admin_and_then_serves_it() {
    install_with
    assert_eq "$(gen ROMM_ADMIN_PASSWORD)" "$(cat "$FAKE_CURL_DIR/romm-admin")"
    assert_contains "$OUT" 'RomM: made its admin account (admin)'
    assert_contains "$OUT" "RomM: its admin is the kit's"
    [ -f "$A/kit-checked" ] || fail "no kit-checked"
    local sj; sj=$(cat "$P/tailscale/romm/serve.json")
    assert_contains "$sj" '"Proxy": "http://romm:8080"'
    assert_not_contains "$sj" 'AllowFunnel'
    # Homarr: its tile, and the widget connection (RomM's needs no key)
    assert_contains "$(cat "$FAKE_CURL_DIR/homarr-apps")" '"pingUrl":"http://romm-proxy:3050/api/heartbeat"'
    local integ; integ=$(cat "$FAKE_CURL_DIR/homarr-integrations")
    assert_contains "$integ" '"kind":"romm"'
    assert_contains "$integ" '"url":"http://romm-proxy:3050"'
    assert_contains "$("$KIT_SERVER_DIR/bin/show-logins" romm)" "user: admin   password: $(gen ROMM_ADMIN_PASSWORD)"
    # The next install makes nothing again
    local out
    out=$(kit install 2>&1) || fail "second install failed: $out"
    assert_eq 1 "$(grep -c 'POST 127.0.0.1:3050/api/users' "$FAKE_CURL_LOG")"
    assert_not_contains "$out" 'RomM: made'
}

test_someone_elses_admin_keeps_romm_off_the_tailnet() {
    install_with 'EXPOSE_romm=funnel' -- FAKE_ROMM_OTHER_ADMIN=1
    assert_contains "$OUT" "RomM: admin doesn't sign in with ROMM_ADMIN_PASSWORD"
    assert_contains "$OUT" 'delete ~/server/appdata/romm/mariadb'
    [ ! -f "$A/kit-checked" ] || fail "kit-checked written for someone else's RomM"
    local sj; sj=$(cat "$P/tailscale/romm/serve.json")
    assert_not_contains "$sj" 'romm:8080'
    assert_not_contains "$sj" 'AllowFunnel'
    assert_eq 0 "$(grep -c 'POST 127.0.0.1:3050/api/users' "$FAKE_CURL_LOG")"
}

test_romm_funnel_comes_with_its_admin() {
    install_with 'EXPOSE_romm=funnel'
    assert_contains "$(cat "$P/tailscale/romm/serve.json")" 'AllowFunnel'
    assert_contains "$OUT" 'RomM: public now (Funnel)'
}

test_metadata_keys_are_optional() {
    install_with
    local env; env=$(cat "$P/.env")
    assert_contains "$env" "IGDB_CLIENT_ID=''"
    assert_contains "$env" "STEAMGRIDDB_API_KEY=''"
    assert_not_contains "$env" 'ROMM_PLAYMATCH'
    # With IGDB's pair (and SteamGridDB's key) in secrets.conf: on, with Playmatch
    printf '%s\n' 'IGDB_CLIENT_ID="fakeigdbid"' 'IGDB_CLIENT_SECRET="fakeigdbsecret"' 'STEAMGRIDDB_API_KEY="fakesgdbkey"' \
        >>"$KIT_SERVER_DIR/secrets.conf"
    kit install >/dev/null 2>&1 || fail "install with keys failed"
    env=$(cat "$P/.env")
    assert_contains "$env" "IGDB_CLIENT_ID='fakeigdbid'"
    assert_contains "$env" "IGDB_CLIENT_SECRET='fakeigdbsecret'"
    assert_contains "$env" "STEAMGRIDDB_API_KEY='fakesgdbkey'"
    assert_contains "$env" "ROMM_PLAYMATCH='true'"
}

# Each key's question, and the second half of a pair only after the first
test_metadata_questions_come_in_pairs() {
    load_libs
    config_init
    modules_discover
    export KIT_INTERACTIVE=1
    printf 'GAMES_ROOT=%s\nROMM_PLATFORMS=gba\nTS_NODE_romm=romm\nEXPOSE_romm=tailnet\n' "$HOME/Games" >>"$ANSWERS"
    local err
    err=$(run_prompts romm 2>&1 >/dev/null <<EOF
fakeid
fakesecret




EOF
)
    assert_eq fakeid "$(kv_get "$SECRETS" IGDB_CLIENT_ID)"
    assert_eq fakesecret "$(kv_get "$SECRETS" IGDB_CLIENT_SECRET)"
    assert_eq '' "$(kv_get "$SECRETS" SCREENSCRAPER_USER)"
    assert_contains "$err" 'IGDB client secret'
    assert_not_contains "$err" 'ScreenScraper password'
}

test_backup_all_and_restore_cover_romm() {
    install_with
    local B=$KIT_SERVER_DIR/bin out
    mkdir -p "$A/mariadb" "$A/tailscale-romm" "$A/resources/roms" "$A/assets"
    echo games >"$A/mariadb/ibdata1"
    echo state >"$A/tailscale-romm/tailscaled.state"
    echo cover >"$A/resources/roms/cover.png"
    echo save >"$A/assets/save.srm"
    sed -i '' "s/^AFTER_START_media_stack=.*/AFTER_START_media_stack=''/" "$KIT_SERVER_DIR/kit/runtime.conf"
    out=$("$B/backup-romm" 2>&1) || fail "backup-romm failed: $out"
    assert_not_contains "$out" 'nothing at'
    local n; n=$(find "$KIT_SERVER_DIR/backups/romm" -maxdepth 1 -name "romm-[0-9]*" | sort | tail -n 1)
    local c; c=$(tar -tzf "$n/appdata.tgz")
    assert_contains "$c" './mariadb/ibdata1'
    assert_contains "$c" './assets/save.srm'
    assert_not_contains "$c" 'cover.png'
    echo changed >"$A/mariadb/ibdata1"
    out=$(RESTORE_YES=1 "$B/restore-romm" 2>&1) || fail "restore-romm failed: $out"
    assert_eq games "$(cat "$A/mariadb/ibdata1")"
    [ -x "$B/update-romm" ] || fail "no update-romm"
    assert_contains "$(cat "$KIT_SERVER_DIR/kit/runtime.conf")" "BACKUP_PROJECTS='romm media-stack'"
}

test_the_platform_check() {
    load_libs
    validate slugs 'gba,snes,psx' || fail "a plain list"
    validate slugs 'neo-geo-pocket' || fail "a name with dashes"
    validate slugs 'GBA' && fail "capitals"
    validate slugs 'gba,,snes' && fail "an empty name"
    validate slugs 'gba snes' && fail "spaces"
    assert_eq 'ps2,gba' "$(normalize_value slugs 'PS2, gba')"
}
