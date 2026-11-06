# shellcheck shell=bash
# Native apps (lib/native.sh, the plex and glances modules), Mac settings (lib/mac.sh) and the
# "always" jobs. Brew, downloads, power settings, Plex's preferences and its processes are all
# fakes (tests/lib.sh, fake-brew, fake-curl, fake-host): nothing is installed or changed for real.

secrets_src() {     # a filled-in secrets file
    S=$TEST_TMP/secrets-src.conf
    printf '%s\n' "WIREGUARD_PRIVATE_KEY=\"$FAKE_WG\"" "TS_AUTHKEY=\"$FAKE_TSKEY\"" >"$S"
}
stored() { cat "$FAKE_CURL_DIR/127.0.0.1_$1" 2>/dev/null; }
PLEX_APP_NAME="Plex Media Server.app"

# The runtime scripts' fakes: KIT_TEST_PATH comes first on their PATH
runtime_fakes() {
    local c
    R=$TEST_TMP/rtbin
    mkdir -p "$R"
    for c in defaults osascript pgrep open; do ln -sf "$TEST_ROOT/tests/fake-host" "$R/$c"; done
    ln -sf "$TEST_ROOT/tests/fake-curl" "$R/curl"
    export KIT_TEST_PATH=$R RESTORE_POLL=0
}

# A Plex that has been set up: its databases (real SQLite files) and plug-in data
plex_data() {
    PMS="$HOME/Library/Application Support/Plex Media Server"
    mkdir -p "$PMS/Plug-in Support/Databases" "$PMS/Plug-in Support/Preferences" "$PMS/Plug-in Support/Caches" "$PMS/Metadata"
    sqlite3 "$PMS/Plug-in Support/Databases/com.plexapp.plugins.library.db" "create table t(v); insert into t values ('$1');"
    sqlite3 "$PMS/Plug-in Support/Databases/com.plexapp.plugins.library.blobs.db" "create table b(v);"
    echo old >"$PMS/Plug-in Support/Databases/com.plexapp.plugins.library.db-2026-01-01"
    echo prefs >"$PMS/Plug-in Support/Preferences/x.xml"
    echo cache >"$PMS/Plug-in Support/Caches/c"
    echo art >"$PMS/Metadata/poster.jpg"
}

# ---------------------------------------------------------------- installing the apps

test_install_puts_plex_and_glances_in_with_homebrew_once() {
    secrets_src
    local out
    out=$(kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Plex: installing with Homebrew'
    assert_contains "$(cat "$FAKE_BREW_LOG")" "brew install --cask --appdir=$KIT_SYSTEM_APPS plex-media-server"
    assert_contains "$(cat "$FAKE_BREW_LOG")" 'brew install glances'
    [ -d "$KIT_SYSTEM_APPS/$PLEX_APP_NAME" ] || fail "no Plex app"
    out=$(kit install 2>&1) || fail "second install failed: $out"
    assert_contains "$out" 'Plex: '
    assert_contains "$out" '(already installed)'
    assert_eq 2 "$(grep -c 'install' "$FAKE_BREW_LOG")"
}

test_without_homebrew_plex_comes_from_plex_tv_and_glances_from_uv() {
    secrets_src
    local out
    out=$(KIT_BREW=/nonexistent/brew kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Plex: downloading it from plex.tv'
    [ -e "$KIT_SYSTEM_APPS/$PLEX_APP_NAME/Contents/MacOS/Plex Media Server" ] || fail "Plex wasn't unpacked"
    assert_contains "$out" 'Glances: installing uv first'
    [ -x "$HOME/.local/bin/glances" ] || fail "no glances from uv"
    [ ! -f "$HOME/.zshrc" ] && [ ! -f "$HOME/.bashrc" ] || fail "uv's installer changed a shell profile"
}

test_when_homebrew_fails_plex_is_downloaded_and_glances_comes_from_uv() {
    secrets_src
    local out
    out=$(FAKE_BREW_FAIL=1 kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$out" "Plex: Homebrew couldn't install it"
    [ -d "$KIT_SYSTEM_APPS/$PLEX_APP_NAME" ] || fail "no Plex"
    assert_contains "$out" "Glances: Homebrew couldn't install it"
    [ -x "$HOME/.local/bin/glances" ] || fail "no glances from uv"
}

test_a_download_with_the_wrong_checksum_is_refused_and_the_install_goes_on() {
    secrets_src
    local out
    out=$(KIT_BREW=/nonexistent/brew FAKE_PLEX_BAD_SUM=1 kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$out" "doesn't match its published checksum"
    [ ! -e "$KIT_SYSTEM_APPS/$PLEX_APP_NAME" ] || fail "installed a bad download"
    assert_contains "$out" 'media-stack is running'
}

test_apps_dir_is_used_and_an_app_elsewhere_counts() {
    secrets_src
    printf 'APPS_DIR=%s\n' "$HOME/Applications" >"$TEST_TMP/answers-src.conf"
    local out
    out=$(kit install --answers "$TEST_TMP/answers-src.conf" --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$(cat "$FAKE_BREW_LOG")" "--appdir=$HOME/Applications plex-media-server"
    assert_contains "$(cat "$KIT_SERVER_DIR/kit/runtime.conf")" "APPS_DIR='$HOME/Applications'"
}

# ---------------------------------------------------------------- jobs and runtime.conf

test_native_apps_get_always_running_jobs() {
    secrets_src
    local out p=$HOME/Library/LaunchAgents/io.github.andy327.mac-server-kit
    out=$(kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Job plex: always running (starts at login, again after a crash)'
    assert_contains "$out" 'Job glances: always running'
    assert_contains "$(cat "$p.plex.plist")" "<string>$KIT_SERVER_DIR/bin/run-plex</string>"
    assert_contains "$(tr -d ' \n' <"$p.plex.plist")" '<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>'
    plutil -lint "$p.plex.plist" >/dev/null || fail "the plex plist isn't valid"
    local rc
    rc=$(cat "$KIT_SERVER_DIR/kit/runtime.conf")
    assert_contains "$rc" "NATIVE_MODULES='plex glances"
    assert_contains "$rc" "'Plex|32400|/identity|fail|job:plex|$KIT_SERVER_DIR/logs/plex.log'"
    assert_contains "$rc" "'Glances|61208|/api/4/status|warn|job:glances|$KIT_SERVER_DIR/logs/glances.log'"
}

test_switching_the_media_server_away_from_plex_removes_its_job() {
    secrets_src
    kit install --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    printf 'MEDIA_SERVER=jellyfin\n' >>"$KIT_SERVER_DIR/answers.conf"
    local out
    out=$(kit install 2>&1) || fail "second install failed: $out"
    assert_contains "$out" 'Job plex: removed'
    [ ! -f "$HOME/Library/LaunchAgents/io.github.andy327.mac-server-kit.plex.plist" ] || fail "plist left behind"
    [ -d "$KIT_SYSTEM_APPS/$PLEX_APP_NAME" ] || fail "the app should stay"
}

test_check_health_says_how_to_start_a_native_app() {
    runtime_fakes
    mkdir -p "$KIT_SERVER_DIR/kit" "$KIT_SERVER_DIR/bin"
    cp "$TEST_ROOT"/modules/health/bin/* "$KIT_SERVER_DIR/bin/"
    printf '%s\n' "PROJECTS=''" "HOST_TAILSCALE='off'" "NATIVE_APPS=('Plex|32400|/identity|fail|job:plex|')" \
        >"$KIT_SERVER_DIR/kit/runtime.conf"
    local out
    out=$(FAKE_CURL_DOWN=32400 "$KIT_SERVER_DIR/bin/check-health" 2>&1)
    assert_contains "$out" "Plex isn't answering on port 32400"
    assert_contains "$out" "launchctl kickstart -k gui/$(id -u)/io.github.andy327.mac-server-kit.plex"
}

# ---------------------------------------------------------------- Plex: wiring

test_plex_is_wired_once_someone_has_signed_in() {
    secrets_src
    local out
    out=$(kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Plex: not signed in yet'
    [ -z "$(stored 8989_api_v3_notification)" ] || fail "connected before sign-in"
    out=$(FAKE_PLEX_TOKEN=plex-token-1 kit install 2>&1) || fail "second install failed: $out"
    assert_contains "$out" 'Sonarr: Plex library updates'
    local n; n=$(stored 8989_api_v3_notification)
    assert_contains "$n" '"implementation":"PlexServer"'
    assert_contains "$n" '{"name":"host","value":"plex-proxy"}'
    assert_contains "$n" '{"name":"authToken","value":"plex-token-1"}'
    assert_contains "$n" "{\"name\":\"mapFrom\",\"value\":\"/tv\"},{\"name\":\"mapTo\",\"value\":\"$HOME/Media/TV Shows\"}"
    assert_contains "$(stored 7878_api_v3_notification)" '{"name":"mapFrom","value":"/movies"}'
    assert_contains "$out" 'Homarr: Plex tile'
    assert_contains "$out" 'Homarr: Plex widget connection'
    out=$(FAKE_PLEX_TOKEN=plex-token-1 kit install 2>&1) || fail "third install failed: $out"
    assert_contains "$out" 'Sonarr: Plex library updates (already set)'
    assert_contains "$out" 'Homarr: Plex tile (already there)'
}

# ---------------------------------------------------------------- Plex: backup and restore

plex_installed() {
    secrets_src
    kit install --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    runtime_fakes
    B=$KIT_SERVER_DIR/bin
    PB=$KIT_SERVER_DIR/backups/plex
}

test_backup_plex_copies_the_databases_and_settings_while_plex_runs() {
    plex_installed
    plex_data v1
    local out bk
    out=$(FAKE_PLEX_TOKEN=tok "$B/backup-plex" 2>&1) || fail "backup failed: $out"
    bk=$(find "$PB" -maxdepth 1 -name 'plex-*' | sort | tail -n 1)
    assert_eq 700 "$(stat -f %Lp "$bk")"
    assert_contains "$(cat "$bk/preferences.plist")" 'PlexOnlineToken'
    assert_contains "$(cat "$bk/versions.txt")" 'plex version: 1.43.0'
    local list; list=$(tar -tzf "$bk/plugin-support.tgz")
    assert_contains "$list" 'Plug-in Support/Databases/com.plexapp.plugins.library.db'
    assert_contains "$list" 'Plug-in Support/Preferences/x.xml'
    assert_not_contains "$list" 'library.db-2026-01-01'          # Plex's own dated copies
    assert_not_contains "$list" 'Caches'
    mkdir -p "$TEST_TMP/x" && tar -xzf "$bk/plugin-support.tgz" -C "$TEST_TMP/x"
    assert_eq v1 "$(sqlite3 "$TEST_TMP/x/Plug-in Support/Databases/com.plexapp.plugins.library.db" 'select v from t')"
    grep -q 'osascript\|quit' "$FAKE_HOST_LOG" && fail "backup stopped Plex"
    return 0
}

test_backup_plex_before_plex_is_set_up_is_not_a_failure() {
    plex_installed
    local out
    out=$("$B/backup-plex" 2>&1) || fail "should succeed: $out"
    assert_contains "$out" "Plex hasn't been set up yet"
    out=$("$B/backup-all" 2>&1) || fail "backup-all failed: $out"
    assert_contains "$out" '==== plex'
    assert_contains "$out" 'Everything backed up'
}

test_restore_plex_quits_plex_puts_it_back_and_keeps_the_old() {
    plex_installed
    plex_data v1
    "$B/backup-plex" >/dev/null 2>&1 || fail "backup failed"
    sqlite3 "$PMS/Plug-in Support/Databases/com.plexapp.plugins.library.db" "update t set v = 'v2'"
    local out
    out=$("$B/restore-plex" </dev/null 2>&1) && fail "restored without asking"
    assert_contains "$out" 'nothing restored'
    # Plex is running until the restore quits it
    touch "$TEST_TMP/plex-running"
    out=$(FAKE_HOST_RUNNING=$TEST_TMP/plex-running RESTORE_YES=1 FAKE_HOST_IMPORTED=$TEST_TMP/imported.plist \
        "$B/restore-plex" 2>&1) || fail "restore failed: $out"
    assert_contains "$out" 'Quitting Plex'
    assert_contains "$(cat "$FAKE_HOST_LOG")" 'to quit'
    assert_eq v1 "$(sqlite3 "$PMS/Plug-in Support/Databases/com.plexapp.plugins.library.db" 'select v from t')"
    [ -f "$TEST_TMP/imported.plist" ] || fail "settings not imported"
    assert_eq v2 "$(sqlite3 "$(ls -d "$PB"/pre-restore-*)/Plug-in Support/Databases/com.plexapp.plugins.library.db" 'select v from t')"
    assert_contains "$out" 'Done: Plex is up'
    assert_contains "$(cat "$FAKE_LAUNCHD_LOG")" 'io.github.andy327.mac-server-kit.plex'
}

# ---------------------------------------------------------------- Glances

test_update_all_updates_glances_too() {
    plex_installed
    local out
    out=$("$B/update-all" 2>&1) || fail "update-all failed: $out"
    assert_contains "$out" '==== glances'
    assert_contains "$out" 'Glances is up to date'
}

test_the_mac_host_info_widget_follows_the_busiest_interface() {
    local t; t=$(cat "$TEST_ROOT/modules/glances/homarr-widget.jsx")
    assert_not_contains "$t" 'en0_bytes'                         # not tied to Wi-Fi any more
    assert_contains "$t" 'bytes_all_gauge'
    # Homarr's template language: one-expression callbacks, no const or Object.keys
    assert_not_contains "$t" 'const '
    assert_not_contains "$t" 'Object.'
    assert_not_contains "$t" '=> {'
    [ -f "$TEST_ROOT/modules/glances/homarr-widget.json" ] || fail "the widget is still a draft"
}

# ---------------------------------------------------------------- Mac settings

test_power_settings_are_shown_and_applied_only_when_agreed() {
    secrets_src
    local out
    out=$(kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Power settings: never sleeps, restarts after a power cut (already set)'
    out=$(FAKE_HOST_SLEEP=10 kit install 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Power settings to change: sleep 0'
    assert_contains "$out" 'To apply them (as an admin): sudo pmset -a sleep 0'
    grep -q '^sudo' "$FAKE_HOST_LOG" && fail "used sudo without asking"
    # Asked in Terminal: yes applies them
    load_libs
    export FAKE_HOST_SLEEP=10 KIT_INTERACTIVE=1
    out=$(mac_settings <<<'y' 2>&1)
    assert_contains "$(cat "$FAKE_HOST_LOG")" "sudo $KIT_PMSET -a sleep 0"
    assert_contains "$out" 'Power settings: never sleeps'
}

test_a_laptops_power_settings_are_left_alone() {
    secrets_src
    printf 'MACHINE_ROLE=laptop\n' >"$TEST_TMP/answers-src.conf"
    local out
    out=$(FAKE_HOST_SLEEP=10 kit install --answers "$TEST_TMP/answers-src.conf" --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Power settings: left alone (MACHINE_ROLE=laptop)'
}
