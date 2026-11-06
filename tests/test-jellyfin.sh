# shellcheck shell=bash
# The jellyfin module: installing it (Homebrew, or the .dmg from Homebrew's cask data), its job,
# its setup and wiring through its API, its Tailscale node and Funnel, and backup-jellyfin,
# restore-jellyfin and update-jellyfin. Brew, hdiutil, the downloads and Jellyfin's API are fakes
# (fake-brew, fake-host, fake-curl): nothing is installed or changed for real.

secrets_src() {     # a filled-in secrets file
    S=$TEST_TMP/secrets-src.conf
    printf '%s\n' "WIREGUARD_PRIVATE_KEY=\"$FAKE_WG\"" "TS_AUTHKEY=\"$FAKE_TSKEY\"" >"$S"
}
answers_src() {     # media-server -> an answers file choosing it
    AN=$TEST_TMP/answers-src.conf
    printf 'MEDIA_SERVER=%s\n' "$1" >"$AN"
}
stored() { cat "$FAKE_CURL_DIR/127.0.0.1_$1" 2>/dev/null; }
jf() { cat "$FAKE_CURL_DIR/jf-$1" 2>/dev/null; }     # done | pw | keys | libs | startup
gen() { sed -n "s/^$1=\"\\(.*\\)\"\$/\\1/p" "$KIT_SERVER_DIR/kit/generated-secrets.conf"; }


install_jellyfin() {    # [env...]: a first install with MEDIA_SERVER=jellyfin
    secrets_src; answers_src jellyfin
    OUT=$(env "$@" "$TEST_ROOT/kit" install --secrets "$S" --answers "$AN" 2>&1) || fail "install failed: $OUT"
}

# The runtime scripts' fakes: KIT_TEST_PATH comes first on their PATH
runtime_fakes() {
    local c
    R=$TEST_TMP/rtbin
    mkdir -p "$R"
    for c in defaults osascript pgrep open; do ln -sf "$TEST_ROOT/tests/fake-host" "$R/$c"; done
    ln -sf "$TEST_ROOT/tests/fake-curl" "$R/curl"
    export KIT_TEST_PATH=$R RESTORE_POLL=0
    B=$KIT_SERVER_DIR/bin
    JB=$KIT_SERVER_DIR/backups/jellyfin
}
# A Jellyfin that has been set up: its databases (real SQLite files) and folders
jellyfin_data() {
    JD="$HOME/Library/Application Support/jellyfin"
    mkdir -p "$JD/config" "$JD/data/transcodes" "$JD/plugins" "$JD/root" "$JD/metadata" "$JD/log"
    sqlite3 "$JD/data/jellyfin.db" "create table t(v); insert into t values ('$1');"
    echo '<IsStartupWizardCompleted>true</IsStartupWizardCompleted>' >"$JD/config/system.xml"
    echo art >"$JD/metadata/poster.jpg"
    echo t >"$JD/data/transcodes/x.ts"
}

# ---------------------------------------------------------------- installing it

test_jellyfin_comes_from_homebrew_once() {
    install_jellyfin
    assert_contains "$OUT" 'Jellyfin: installing with Homebrew'
    assert_contains "$(cat "$FAKE_BREW_LOG")" "brew install --cask --appdir=$KIT_SYSTEM_APPS jellyfin"
    [ -x "$KIT_SYSTEM_APPS/Jellyfin.app/Contents/MacOS/jellyfin" ] || fail "no Jellyfin app"
    assert_not_contains "$OUT" 'Plex:'
    local out
    out=$(kit install 2>&1) || fail "second install failed: $out"
    assert_contains "$out" 'Jellyfin: '
    assert_contains "$out" '(already installed)'
    assert_eq 1 "$(grep -c 'install --cask' "$FAKE_BREW_LOG")"
}

test_without_homebrew_jellyfin_comes_from_its_dmg() {
    install_jellyfin KIT_BREW=/nonexistent/brew
    assert_contains "$OUT" 'Jellyfin: downloading it from jellyfin.org'
    assert_contains "$(cat "$FAKE_CURL_LOG")" 'GET formulae.brew.sh/api/cask/jellyfin.json'
    assert_contains "$(cat "$FAKE_CURL_LOG")" "repo.jellyfin.org/files/server/macos/stable/v12.4/$(uname -m | sed 's/x86_64/amd64/')/"
    assert_contains "$(cat "$FAKE_HOST_LOG")" 'hdiutil attach -nobrowse -readonly'
    assert_contains "$(cat "$FAKE_HOST_LOG")" 'hdiutil detach'
    [ -x "$KIT_SYSTEM_APPS/Jellyfin.app/Contents/MacOS/jellyfin" ] || fail "Jellyfin wasn't copied from the .dmg"
    assert_contains "$OUT" "Jellyfin: $KIT_SYSTEM_APPS/Jellyfin.app"
}

test_a_dmg_with_the_wrong_checksum_is_refused() {
    install_jellyfin KIT_BREW=/nonexistent/brew FAKE_JELLYFIN_BAD_SUM=1
    assert_contains "$OUT" "doesn't match its published checksum"
    [ ! -d "$KIT_SYSTEM_APPS/Jellyfin.app" ] || fail "a bad download was installed"
    assert_not_contains "$(cat "$FAKE_HOST_LOG" 2>/dev/null)" 'hdiutil attach'
    assert_contains "$OUT" 'media-stack is running'      # the install goes on
}

test_the_jellyfin_job_runs_the_server_inside_the_app() {
    install_jellyfin
    assert_contains "$OUT" 'Job jellyfin: always running'
    local p=$HOME/Library/LaunchAgents/io.github.andy327.mac-server-kit.jellyfin.plist
    plutil -lint "$p" >/dev/null || fail "bad plist"
    assert_contains "$(cat "$p")" 'bin/run-jellyfin</string>'
    local r; r=$(cat "$KIT_SERVER_DIR/bin/run-jellyfin")
    # shellcheck disable=SC2016  # the script's own text
    assert_contains "$r" '--webdir "$APP/Contents/Resources/jellyfin-web" --ffmpeg "$APP/Contents/MacOS/ffmpeg" --datadir "$DATA"'
    local rc; rc=$(cat "$KIT_SERVER_DIR/kit/runtime.conf")
    assert_contains "$rc" "NATIVE_MODULES='jellyfin glances"
    assert_contains "$rc" "'Jellyfin|8096|/health|fail|job:jellyfin|$KIT_SERVER_DIR/logs/jellyfin.log'"
    # The jobs come before the wiring, so Jellyfin is running when the kit sets it up
    local jobs wire
    jobs=$(printf '%s\n' "$OUT" | grep -n 'Health and jobs' | cut -d: -f1)
    wire=$(printf '%s\n' "$OUT" | grep -n 'Connecting the apps' | cut -d: -f1)
    [ "$jobs" -lt "$wire" ] || fail "the jobs should load before the wiring"
}

# ---------------------------------------------------------------- setup and wiring

test_the_kit_sets_jellyfin_up_and_connects_it() {
    install_jellyfin
    local pw; pw=$(gen JELLYFIN_ADMIN_PASSWORD)
    [ -n "$pw" ] || fail "no JELLYFIN_ADMIN_PASSWORD"
    assert_contains "$OUT" 'Jellyfin: set up, with its admin account (admin, with JELLYFIN_ADMIN_PASSWORD)'
    assert_eq "$pw" "$(jf pw)"
    assert_contains "$(jf startup)" 'POST /Startup/Complete'
    assert_contains "$(jf startup)" 'GET /Startup/User'
    assert_contains "$OUT" 'Jellyfin: an API key for the kit'
    local key; key=$(gen JELLYFIN_API_KEY)
    assert_contains "$(jf keys)" "$key|mac-server-kit"
    assert_contains "$OUT" "Jellyfin: Movies library (~/Media/Movies)"
    assert_contains "$(jf libs)" "\"Locations\":[\"$HOME/Media/TV Shows\"],\"CollectionType\":\"tvshows\""
    local n; n=$(stored 8989_api_v3_notification)
    assert_contains "$n" '"implementation":"MediaBrowser"'
    assert_contains "$n" '{"name":"host","value":"jellyfin-proxy"}'
    assert_contains "$n" "{\"name\":\"apiKey\",\"value\":\"$key\"}"
    assert_contains "$n" "{\"name\":\"mapFrom\",\"value\":\"/tv\"},{\"name\":\"mapTo\",\"value\":\"$HOME/Media/TV Shows\"}"
    assert_contains "$(stored 7878_api_v3_notification)" '{"name":"mapFrom","value":"/movies"}'
    assert_contains "$OUT" 'Homarr: Jellyfin tile'
    assert_contains "$OUT" 'Homarr: Jellyfin widget connection'
    # Again: nothing new
    local out
    out=$(kit install 2>&1) || fail "second install failed: $out"
    assert_not_contains "$out" 'Jellyfin: set up'
    assert_contains "$out" 'Jellyfin: TV Shows library (already there)'
    assert_contains "$out" 'Sonarr: Jellyfin library updates (already set)'
    assert_eq 1 "$(jf keys | wc -l | tr -d ' ')"
}

test_a_jellyfin_set_up_by_hand_needs_the_owners_key() {
    install_jellyfin FAKE_JELLYFIN_SET_UP=1
    assert_contains "$OUT" 'Jellyfin was set up by hand, so the kit needs a key from you'
    stored 8989_api_v3_notification | grep -q MediaBrowser && fail "connected without a key"
    printf 'JELLYFIN_API_KEY="mine0123456789"\n' >>"$KIT_SERVER_DIR/secrets.conf"
    local out
    out=$(FAKE_JELLYFIN_SET_UP=1 FAKE_JELLYFIN_KEY=mine0123456789 kit install 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Sonarr: Jellyfin library updates'
    assert_contains "$(stored 8989_api_v3_notification)" '"value":"mine0123456789"'
    out=$(FAKE_JELLYFIN_SET_UP=1 kit install 2>&1) || fail "install should still succeed: $out"
    assert_contains "$out" "JELLYFIN_API_KEY in"
    assert_contains "$out" "isn't accepted"
}

test_a_jellyfin_that_doesnt_answer_only_warns() {
    install_jellyfin FAKE_CURL_DOWN=8096
    assert_contains "$OUT" 'Jellyfin: not answering on port 8096'
    assert_contains "$OUT" 'media-stack is running'
}

test_jellyfin_goes_public_in_the_run_that_sets_it_up() {
    install_jellyfin
    local f=$KIT_SERVER_DIR/media-stack/tailscale/jellyfin/serve.json
    assert_contains "$(cat "$f")" '"Proxy": "http://jellyfin-proxy:8096"'
    assert_contains "$(cat "$f")" 'AllowFunnel'
    assert_contains "$OUT" 'Jellyfin: public now (Funnel)'
    assert_not_contains "$OUT" "Jellyfin stays tailnet-only"
    assert_contains "$(cat "$KIT_SERVER_DIR/media-stack/.env")" 'TS_HOSTNAME_JELLYFIN='
    assert_contains "$OUT" 'sign in as admin with JELLYFIN_ADMIN_PASSWORD'
}

test_a_jellyfin_set_up_elsewhere_stays_tailnet_only_until_its_config_says_so() {
    install_jellyfin FAKE_JELLYFIN_SET_UP=1
    local f=$KIT_SERVER_DIR/media-stack/tailscale/jellyfin/serve.json
    assert_not_contains "$(cat "$f")" 'AllowFunnel'
    assert_contains "$OUT" "Jellyfin stays tailnet-only until it's set up"
    mkdir -p "$HOME/.local/share/jellyfin/config"      # the other data folder counts too
    echo '<IsStartupWizardCompleted>true</IsStartupWizardCompleted>' >"$HOME/.local/share/jellyfin/config/system.xml"
    local out
    out=$(FAKE_JELLYFIN_SET_UP=1 kit install 2>&1) || fail "install failed: $out"
    assert_contains "$(cat "$f")" 'AllowFunnel'
}

# ---------------------------------------------------------------- backup, restore, update

test_backup_jellyfin_copies_the_databases_and_skips_what_it_rebuilds() {
    install_jellyfin
    runtime_fakes
    jellyfin_data v1
    local out
    out=$("$B/backup-jellyfin" 2>&1) || fail "backup failed: $out"
    local bk; bk=$(find "$JB" -maxdepth 1 -name 'jellyfin-*' | head -n 1)
    assert_eq 700 "$(stat -f %Lp "$bk")"
    local t; t=$(tar -tzf "$bk/jellyfin.tgz")
    assert_contains "$t" 'data/jellyfin.db'
    assert_contains "$t" 'config/system.xml'
    assert_not_contains "$t" 'transcodes'
    assert_not_contains "$t" 'metadata'
    assert_contains "$(cat "$bk/versions.txt")" 'jellyfin version: 1.43.0'
    mkdir "$TEST_TMP/x" && tar -xzf "$bk/jellyfin.tgz" -C "$TEST_TMP/x"
    assert_eq v1 "$(sqlite3 "$TEST_TMP/x/data/jellyfin.db" 'select v from t')"
}

test_backup_all_includes_jellyfin_and_skips_one_not_set_up() {
    install_jellyfin
    runtime_fakes
    local out
    out=$("$B/backup-jellyfin" 2>&1) || fail "backup-jellyfin should pass before the setup: $out"
    assert_contains "$out" "Jellyfin hasn't been set up yet"
    jellyfin_data v1
    out=$("$B/backup-all" 2>&1) || fail "backup-all failed: $out"
    assert_contains "$out" '==== jellyfin'
    ls -d "$JB"/jellyfin-* >/dev/null 2>&1 || fail "no Jellyfin backup"
}

test_restore_jellyfin_puts_the_data_back_and_keeps_the_old() {
    install_jellyfin
    runtime_fakes
    jellyfin_data v1
    "$B/backup-jellyfin" >/dev/null 2>&1 || fail "backup failed"
    sqlite3 "$JD/data/jellyfin.db" "update t set v = 'v2'"
    local out
    out=$(printf 'no\n' | "$B/restore-jellyfin" 2>&1) && fail "restored without 'restore': $out"
    assert_eq v2 "$(sqlite3 "$JD/data/jellyfin.db" 'select v from t')"
    out=$(RESTORE_YES=1 "$B/restore-jellyfin" 2>&1) || fail "restore failed: $out"
    assert_eq v1 "$(sqlite3 "$JD/data/jellyfin.db" 'select v from t')"
    assert_eq v2 "$(sqlite3 "$(ls -d "$JB"/pre-restore-*)/data/jellyfin.db" 'select v from t')"
    [ -f "$JD/data/transcodes/x.ts" ] || fail "transcodes weren't carried over"
    assert_contains "$out" 'Done: Jellyfin is up'
    assert_contains "$(cat "$FAKE_LAUNCHD_LOG")" 'io.github.andy327.mac-server-kit.jellyfin'
}

test_update_jellyfin_from_the_dmg() {
    install_jellyfin KIT_BREW=/nonexistent/brew
    runtime_fakes
    local out
    out=$(KIT_BREW=/nonexistent/brew "$B/update-jellyfin" 2>&1) || fail "update failed: $out"
    assert_contains "$out" 'Jellyfin is up to date (12.4)'
    out=$(KIT_BREW=/nonexistent/brew FAKE_JELLYFIN_RELEASE=12.5 FAKE_DMG_VERSION=12.5 "$B/update-jellyfin" 2>&1) || fail "update failed: $out"
    assert_contains "$out" 'Updating Jellyfin: 12.4 → 12.5'
    assert_contains "$out" "Jellyfin: 12.4 → 12.5; it's up"
    assert_eq 12.5 "$(cat "$KIT_SYSTEM_APPS/Jellyfin.app/Contents/fake-version")"
    # A bad download leaves the installed one
    out=$(KIT_BREW=/nonexistent/brew FAKE_JELLYFIN_RELEASE=12.6 FAKE_JELLYFIN_BAD_SUM=1 "$B/update-jellyfin" 2>&1) && fail "a bad download should fail"
    assert_contains "$out" 'Jellyfin 12.5 is still installed'
    assert_eq 12.5 "$(cat "$KIT_SYSTEM_APPS/Jellyfin.app/Contents/fake-version")"
}

test_update_all_updates_a_homebrew_jellyfin() {
    install_jellyfin
    runtime_fakes
    local out
    out=$("$B/update-all" 2>&1) || fail "update-all failed: $out"
    assert_contains "$out" '==== jellyfin'
    assert_contains "$(cat "$FAKE_BREW_LOG")" 'brew upgrade --cask jellyfin'
}
