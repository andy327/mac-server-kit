# shellcheck shell=bash
# The ollama and open-webui modules: installing Ollama (Homebrew, or its release .tgz), its job,
# the model download, update-ollama, and Open WebUI's project, admin account, Tailscale node,
# Homarr tile and backups. Brew, the downloads and Ollama's API are fakes (fake-brew, fake-curl).

secrets_src() {     # a filled-in secrets file
    S=$TEST_TMP/secrets-src.conf
    printf '%s\n' "WIREGUARD_PRIVATE_KEY=\"$FAKE_WG\"" "TS_AUTHKEY=\"$FAKE_TSKEY\"" >"$S"
}
gen() { sed -n "s/^$1=\"\\(.*\\)\"\$/\\1/p" "$KIT_SERVER_DIR/kit/generated-secrets.conf"; }
models() { cat "$FAKE_CURL_DIR/ollama-models" 2>/dev/null; }

install_with() {    # modules [answers-line...] [-- env...]: a first install
    local mods=$1 envs=()
    shift
    secrets_src
    printf 'MODULES=%s\n' "$mods" >"$TEST_TMP/answers-src.conf"
    while [ $# -gt 0 ]; do
        [ "$1" = -- ] && { shift; envs=("$@"); break; }
        printf '%s\n' "$1" >>"$TEST_TMP/answers-src.conf"
        shift
    done
    OUT=$(env ${envs[@]+"${envs[@]}"} "$TEST_ROOT/kit" install --secrets "$S" --answers "$TEST_TMP/answers-src.conf" 2>&1) \
        || fail "install failed: $OUT"
    OL=$KIT_SERVER_DIR/apps/ollama
}

# ---------------------------------------------------------------- Ollama

test_ollama_comes_from_homebrew_once() {
    install_with ollama
    assert_contains "$OUT" 'Ollama: installing with Homebrew'
    assert_contains "$(cat "$FAKE_BREW_LOG")" 'brew install ollama'
    [ -x "$TEST_TMP/brew/bin/ollama" ] || fail "no Homebrew ollama"
    local out
    out=$(kit install 2>&1) || fail "second install failed: $out"
    assert_contains "$out" 'Ollama: '
    assert_contains "$out" '(already installed)'
    assert_eq 1 "$(grep -c 'install ollama' "$FAKE_BREW_LOG")"
}

test_without_homebrew_ollama_comes_from_its_release() {
    install_with ollama -- KIT_BREW=/nonexistent/brew
    assert_contains "$OUT" 'Ollama: downloading it from its GitHub release'
    assert_contains "$(cat "$FAKE_CURL_LOG")" 'HEAD github.com/ollama/ollama/releases/latest'
    assert_contains "$(cat "$FAKE_CURL_LOG")" 'GET github.com/ollama/ollama/releases/download/v0.40.15/ollama-darwin.tgz'
    [ -x "$OL/ollama" ] || fail "ollama wasn't unpacked"
    [ -f "$OL/libggml.dylib" ] || fail "its libraries weren't unpacked with it"
    assert_eq "$OL/ollama" "$(readlink "$KIT_SERVER_DIR/bin/ollama")"
    assert_contains "$OUT" "Ollama: $OL/ollama"
    # The next install keeps the link (it isn't one of the kit's runtime scripts)
    kit install >/dev/null 2>&1 || fail "second install failed"
    [ -L "$KIT_SERVER_DIR/bin/ollama" ] || fail "the second install removed the ollama link"
}

test_a_release_with_the_wrong_checksum_is_refused() {
    install_with ollama -- KIT_BREW=/nonexistent/brew FAKE_OLLAMA_BAD_SUM=1
    assert_contains "$OUT" "doesn't match its published checksum"
    [ ! -e "$OL" ] || fail "a bad download was unpacked"
    assert_contains "$OUT" 'media-stack is running'      # the install goes on
    assert_not_contains "$OUT" 'Ollama: downloading qwen'
}

test_an_old_macos_gets_no_ollama() {
    install_with ollama -- KIT_MACOS_MAJOR=13
    assert_contains "$OUT" 'Ollama needs macOS 14 or newer'
    assert_not_contains "$(cat "$FAKE_BREW_LOG" 2>/dev/null)" 'install ollama'
    assert_not_contains "$OUT" 'not answering on port 11434'
}

test_the_ollama_job_runs_its_server() {
    install_with ollama
    local plist=$HOME/Library/LaunchAgents/io.github.andy327.mac-server-kit.ollama.plist
    [ -f "$plist" ] || fail "no ollama job"
    assert_contains "$(cat "$plist")" 'bin/run-ollama</string>'
    assert_contains "$(cat "$plist")" '<key>KeepAlive</key>'
    assert_contains "$(cat "$KIT_SERVER_DIR/kit/runtime.conf")" "'Ollama|11434|/api/version|warn|job:ollama|"
    assert_contains "$(cat "$KIT_SERVER_DIR/bin/run-ollama")" 'OLLAMA_HOST=127.0.0.1:11434'
    assert_contains "$(cat "$KIT_SERVER_DIR/kit/runtime.conf")" "NATIVE_MODULES='ollama"
}

test_the_install_downloads_a_model_that_fits_this_mac() {
    install_with ollama
    assert_contains "$(cat "$KIT_SERVER_DIR/answers.conf")" 'OLLAMA_MODEL=qwen3.5:9b'    # 32 GB
    assert_contains "$OUT" 'Ollama: downloading qwen3.5:9b'
    assert_contains "$OUT" '✓ Ollama: qwen3.5:9b'
    assert_eq 'qwen3.5:9b' "$(models)"
    local out
    out=$(kit install 2>&1) || fail "second install failed: $out"
    assert_contains "$out" 'Ollama: qwen3.5:9b (already downloaded)'
    assert_eq 1 "$(grep -c 'POST 127.0.0.1:11434/api/pull' "$FAKE_CURL_LOG")"
}

test_the_model_suggestion_follows_memory_and_none_downloads_nothing() {
    load_libs
    assert_eq qwen3.5:2b "$(KIT_MEM_GB=8 default_ollama_model)"
    assert_eq qwen3.5:4b "$(KIT_MEM_GB=16 default_ollama_model)"
    assert_eq qwen3.5:9b "$(KIT_MEM_GB=24 default_ollama_model)"
    assert_eq qwen3.5:27b "$(KIT_MEM_GB=64 default_ollama_model)"
    validate model gemma4:12b || fail "gemma4:12b refused"
    validate model none || fail "none refused"
    validate model 'Big Model' && fail "a name with a space was accepted"
    install_with ollama 'OLLAMA_MODEL=none'
    assert_eq '' "$(models)"
    assert_not_contains "$(cat "$FAKE_CURL_LOG")" '/api/pull'
}

test_a_failed_model_download_only_warns() {
    install_with ollama 'OLLAMA_MODEL=nosuch:1b' -- FAKE_OLLAMA_PULL_FAIL=1
    assert_contains "$OUT" "Ollama: couldn't download nosuch:1b (pull model manifest: file does not exist)"
    assert_contains "$OUT" 'Open'
}

test_an_ollama_that_doesnt_answer_only_warns() {
    install_with ollama -- FAKE_CURL_DOWN=11434
    assert_contains "$OUT" 'Ollama: not answering on port 11434'
    assert_contains "$OUT" 'Still to do'
}

# ---------------------------------------------------------------- update-ollama

test_update_ollama_from_its_release() {
    install_with ollama -- KIT_BREW=/nonexistent/brew
    local B=$KIT_SERVER_DIR/bin out
    export KIT_TEST_PATH=$TEST_TMP/rtbin
    mkdir -p "$KIT_TEST_PATH" && ln -sf "$TEST_ROOT/tests/fake-curl" "$KIT_TEST_PATH/curl"
    out=$("$B/update-ollama" 2>&1) || fail "update-ollama failed: $out"
    assert_contains "$out" 'Ollama is up to date (0.40.15); nothing restarted'
    out=$(FAKE_OLLAMA_RELEASE=0.41.0 "$B/update-ollama" 2>&1) || fail "update-ollama failed: $out"
    assert_contains "$out" 'Ollama: 0.40.15 → 0.41.0'
    assert_contains "$("$KIT_SERVER_DIR/apps/ollama/ollama" -v)" '0.41.0'
    assert_contains "$(cat "$FAKE_LAUNCHD_LOG")" 'bootout'
    # A bad download keeps the copy that's there, and starts it again
    out=$(FAKE_OLLAMA_RELEASE=0.42.0 FAKE_OLLAMA_BAD_SUM=1 "$B/update-ollama" 2>&1) && fail "a bad download passed"
    assert_contains "$out" 'Ollama 0.41.0 is still installed and running'
    assert_contains "$("$KIT_SERVER_DIR/apps/ollama/ollama" -v)" '0.41.0'
}

test_update_ollama_with_homebrew_and_another_accounts_homebrew() {
    install_with ollama
    local B=$KIT_SERVER_DIR/bin out
    out=$(FAKE_BREW_OLLAMA_NEW=0.41.0 "$B/update-ollama" 2>&1) || fail "update-ollama failed: $out"
    assert_contains "$(cat "$FAKE_BREW_LOG")" 'brew upgrade ollama'
    assert_contains "$out" 'Ollama: 0.40.14 → 0.41.0'
    chmod a-w "$TEST_TMP/brew/bin"
    out=$("$B/update-ollama" 2>&1); local rc=$?
    chmod u+w "$TEST_TMP/brew/bin"
    assert_eq 0 "$rc"
    assert_contains "$out" "Homebrew, which this account can't update"
}

# ---------------------------------------------------------------- Open WebUI

test_open_webui_is_its_own_project_with_its_admin_from_the_start() {
    install_with 'ollama open-webui'
    assert_contains "$OUT" 'Modules: core media-stack plex ollama open-webui'
    local P=$KIT_SERVER_DIR/open-webui env
    env=$(cat "$P/.env")
    assert_contains "$env" "OPENWEBUI_ADMIN_PASSWORD='$(gen OPENWEBUI_ADMIN_PASSWORD)'"
    assert_contains "$env" "OPENWEBUI_SECRET_KEY='$(gen OPENWEBUI_SECRET_KEY)'"
    assert_contains "$env" "OPENWEBUI_SESSION_DAYS='90'"
    assert_contains "$env" "TS_HOSTNAME_CHAT='chat'"
    # Pinned to a release, not main
    assert_contains "$(cat "$P/images.lock")" 'open-webui ghcr.io/open-webui/open-webui:v0.13.0@sha256:'
    assert_contains "$(cat "$P/images.lock")" ' v0.*'
    # Public through Funnel at once: its admin exists from its first start
    local sj; sj=$(cat "$P/tailscale/chat/serve.json")
    assert_contains "$sj" '"Proxy": "http://open-webui:8080"'
    assert_contains "$sj" 'AllowFunnel'
    # The relay for Homarr joins the media stack
    ls "$KIT_SERVER_DIR"/media-stack/compose.d/*-open-webui.yml >/dev/null 2>&1 || fail "no open-webui-proxy in the media stack"
    assert_contains "$OUT" 'Open WebUI     https://chat.tail0000.ts.net'          # check-private: allow
    assert_contains "$OUT" 'sign in as admin@localhost with'
    assert_contains "$OUT" 'turn on two-factor sign-in'
    local apps; apps=$(cat "$FAKE_CURL_DIR/homarr-apps")
    assert_contains "$apps" '"name":"Open WebUI"'
    assert_contains "$apps" '"pingUrl":"http://open-webui-proxy:3020/health"'
    # Backups: its database and node, without its document models
    local rc; rc=$(cat "$KIT_SERVER_DIR/kit/runtime.conf")
    assert_contains "$rc" "BACKUP_EXPECT_open_webui='data/webui.db tailscale-chat/tailscaled.state'"
    assert_contains "$rc" "BACKUP_EXCLUDE_open_webui='./data/cache'"
    assert_contains "$rc" "BACKUP_PROJECTS='media-stack open-webui'"
    assert_contains "$("$KIT_SERVER_DIR/bin/show-logins" webui)" "user: admin@localhost   password: $(gen OPENWEBUI_ADMIN_PASSWORD)"
}

test_open_webui_needs_ollama() {
    secrets_src
    printf 'MODULES=open-webui\n' >"$TEST_TMP/a.conf"
    local out
    out=$(kit install --secrets "$S" --answers "$TEST_TMP/a.conf" 2>&1) && fail "installed without ollama"
    assert_contains "$out" 'open-webui requires ollama (./kit add ollama)'
}

test_a_tailnet_only_open_webui_has_no_funnel() {
    install_with 'ollama open-webui' 'EXPOSE_chat=tailnet'
    assert_not_contains "$(cat "$KIT_SERVER_DIR/open-webui/tailscale/chat/serve.json")" 'AllowFunnel'
    assert_not_contains "$OUT" 'Funnel allowed for the kit'"'"'s machines (for Open WebUI)'
}

test_backup_all_and_restore_cover_open_webui() {
    install_with 'ollama open-webui'
    local A=$KIT_SERVER_DIR/appdata/open-webui B=$KIT_SERVER_DIR/bin out
    mkdir -p "$A/data/cache" "$A/tailscale-chat"
    echo chats >"$A/data/webui.db"
    echo model >"$A/data/cache/embedding.bin"
    echo state >"$A/tailscale-chat/tailscaled.state"
    sed -i '' "s/^AFTER_START_media_stack=.*/AFTER_START_media_stack=''/" "$KIT_SERVER_DIR/kit/runtime.conf"
    out=$("$B/backup-open-webui" 2>&1) || fail "backup-open-webui failed: $out"
    assert_not_contains "$out" 'nothing at'
    local n; n=$(find "$KIT_SERVER_DIR/backups/open-webui" -maxdepth 1 -name "open-webui-[0-9]*" | sort | tail -n 1)
    local c; c=$(tar -tzf "$n/appdata.tgz")
    assert_contains "$c" './data/webui.db'
    assert_not_contains "$c" 'cache'
    echo changed >"$A/data/webui.db"
    out=$(RESTORE_YES=1 "$B/restore-open-webui" 2>&1) || fail "restore-open-webui failed: $out"
    assert_eq chats "$(cat "$A/data/webui.db")"
    [ -x "$B/update-open-webui" ] || fail "no update-open-webui"
}
