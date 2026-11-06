# shellcheck shell=bash
# ./kit end to end with the repo's modules (no host checks, nothing installed)

WG=$FAKE_WG

secrets_src() {     # a filled-in secrets file
    S=$TEST_TMP/secrets-src.conf
    printf '%s\n' "WIREGUARD_PRIVATE_KEY=\"$WG\"" "TS_AUTHKEY=\"$FAKE_TSKEY\"" >"$S"
}

test_install_noninteractive_needs_required_secrets() {
    local out
    out=$(kit install 2>&1) && fail "install should fail without secrets"
    assert_contains "$out" 'WIREGUARD_PRIVATE_KEY (secrets.conf)'
    assert_contains "$out" 'TS_AUTHKEY (secrets.conf)'
}

test_install_with_secrets_file() {
    secrets_src
    local out
    out=$(kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Modules: core media-stack plex glances health'
    assert_eq 'core media-stack plex glances health' \
        "$(grep -v '^#' "$KIT_SERVER_DIR/kit/enabled" | tr '\n' ' ' | sed 's/ $//')"
    grep -q '^SONARR_API_KEY="[0-9a-f]\{32\}"$' "$KIT_SERVER_DIR/kit/generated-secrets.conf" \
        || fail "no generated Sonarr API key"
}

test_install_is_idempotent() {
    secrets_src
    kit install --secrets "$S" >/dev/null 2>&1 || fail "first install failed"
    local a s g
    a=$(cat "$KIT_SERVER_DIR/answers.conf")
    s=$(cat "$KIT_SERVER_DIR/secrets.conf")
    g=$(cat "$KIT_SERVER_DIR/kit/generated-secrets.conf")
    kit install >/dev/null 2>&1 || fail "second install failed"
    assert_eq "$a" "$(cat "$KIT_SERVER_DIR/answers.conf")" "answers.conf changed"
    assert_eq "$s" "$(cat "$KIT_SERVER_DIR/secrets.conf")" "secrets.conf changed"
    assert_eq "$g" "$(cat "$KIT_SERVER_DIR/kit/generated-secrets.conf")" "generated secrets changed"
}

test_install_interactive_asks_everything_once() {
    export KIT_INTERACTIVE=1
    # core: role, tz, media root, media server, backup drive; health: healthchecks url, ntfy;
    # media-stack: vpn, media node, exposure, dashboard node, wg key, ts key; jellyfin: node,
    # exposure; homarr key
    # (base modules are asked in discovery order; no WireGuard address for nordvpn)
    local out
    out=$(kit install 2>&1 <<EOF
laptop

~/Stuff/Media/
both



nordvpn
srv-media
tailnet
srv-dash
$WG
$FAKE_TSKEY
srv-jellyfin
tailnet

EOF
) || fail "interactive install failed: $out"
    local A=$KIT_SERVER_DIR/answers.conf
    assert_contains "$(cat "$A")" 'MACHINE_ROLE=laptop'
    assert_contains "$(cat "$A")" "MEDIA_ROOT=$HOME/Stuff/Media"
    assert_contains "$(cat "$A")" 'MEDIA_SERVER=both'
    assert_contains "$(cat "$A")" 'VPN_PROVIDER=nordvpn'
    assert_contains "$(cat "$A")" 'TS_NODE_media=srv-media'
    assert_not_contains "$(cat "$KIT_SERVER_DIR/secrets.conf")" 'WIREGUARD_ADDRESSES'   # proton only
    assert_contains "$out" 'Modules: core media-stack plex jellyfin glances health'
}

test_add_and_disable() {
    secrets_src
    kit install --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    local out
    out=$(kit add open-webui 2>&1) && fail "add open-webui alone should fail"
    assert_contains "$out" 'open-webui requires ollama'
    assert_fails grep -q '^MODULES=' "$KIT_SERVER_DIR/answers.conf"

    kit add ollama open-webui >/dev/null 2>&1 || fail "add failed"
    assert_contains "$(cat "$KIT_SERVER_DIR/answers.conf")" 'MODULES=ollama open-webui'

    out=$(kit disable ollama 2>&1) && fail "disabling a needed module should fail"
    assert_contains "$out" 'open-webui requires ollama'

    kit disable open-webui ollama >/dev/null 2>&1 || fail "disable failed"
    assert_eq 'MODULES=' "$(grep '^MODULES=' "$KIT_SERVER_DIR/answers.conf")"
}

test_add_and_disable_refusals() {
    secrets_src
    kit install --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    assert_fails kit add media-stack
    assert_fails kit add nonsense
    assert_fails kit disable health
    assert_fails kit disable plex           # the media-server choice
    assert_fails kit disable romm           # not enabled
}

test_check_and_status() {
    local out
    out=$(kit check 2>&1) || fail "check should pass with nothing configured"
    assert_contains "$out" 'kit install asks for everything'
    secrets_src
    kit install --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    printf 'HOLD_sonarr=4.0 # testing a pin, 2026-11\n' >>"$KIT_SERVER_DIR/answers.conf"
    out=$(kit check 2>&1) || fail "check failed: $out"
    assert_contains "$out" 'Ready'
    out=$(kit status 2>&1) || fail "status failed: $out"
    assert_contains "$out" 'media-stack'
    assert_contains "$out" 'Available to add:'
    assert_contains "$out" 'sonarr'
    assert_contains "$out" 'testing a pin'
    printf 'MODULES=romm\n' >>"$KIT_SERVER_DIR/answers.conf"
    out=$(kit status 2>&1)
    assert_contains "$out" 'run ./kit install to apply it'
}

test_check_flags_bad_values() {
    secrets_src
    kit install --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    printf 'MEDIA_SERVER=emby\n' >>"$KIT_SERVER_DIR/answers.conf"
    local out
    out=$(kit check 2>&1) && fail "check should fail"
    assert_contains "$out" 'MEDIA_SERVER in'
}

test_help() {
    assert_contains "$(kit --help)" './kit install'
    assert_fails kit bogus
}

# --answers and --secrets files reach ~/server only once every value has passed, so a run that's
# quit or stopped by a bad value can be repeated with the corrected file.
test_quit_install_with_files_leaves_nothing_and_can_be_rerun() {
    local s=$TEST_TMP/s.conf
    printf '%s\n' 'WIREGUARD_PRIVATE_KEY=""' "TS_AUTHKEY=\"$FAKE_TSKEY\"" >"$s"   # forgot the key
    export KIT_INTERACTIVE=1
    kit install --secrets "$s" </dev/null >/dev/null 2>&1 && fail "should stop: input ended at the key"
    [ ! -e "$KIT_SERVER_DIR/secrets.conf" ] || fail "secrets.conf copied by a run that didn't finish"
    printf '%s\n' "WIREGUARD_PRIVATE_KEY=\"$WG\"" "TS_AUTHKEY=\"$FAKE_TSKEY\"" >"$s"  # fixed
    local out
    out=$(KIT_INTERACTIVE=0 kit install --secrets "$s" 2>&1) || fail "rerun with the fixed file failed: $out"
    assert_contains "$out" "Copied $s to $KIT_SERVER_DIR/secrets.conf"
    assert_contains "$(cat "$KIT_SERVER_DIR/secrets.conf")" "$WG"
}

test_bad_value_in_a_secrets_file_names_that_file() {
    local s=$TEST_TMP/s.conf out
    printf '%s\n' 'WIREGUARD_PRIVATE_KEY="not-a-key"' "TS_AUTHKEY=\"$FAKE_TSKEY\"" >"$s"
    out=$(kit install --secrets "$s" 2>&1) && fail "should stop at the bad key"
    assert_contains "$out" "WIREGUARD_PRIVATE_KEY in $s must be a WireGuard private key"
    [ ! -e "$KIT_SERVER_DIR/secrets.conf" ] || fail "copied a file with a bad value"
    printf '%s\n' "WIREGUARD_PRIVATE_KEY=\"$WG\"" "TS_AUTHKEY=\"$FAKE_TSKEY\"" >"$s"
    kit install --secrets "$s" >/dev/null 2>&1 || fail "rerun with the fixed file failed"
}

test_answers_typed_at_prompts_are_kept_when_quit() {
    export KIT_INTERACTIVE=1
    # role, time zone, then input ends
    printf 'laptop\nEurope/London\n' | kit install >/dev/null 2>&1 && fail "should stop when input ends"
    assert_contains "$(cat "$KIT_SERVER_DIR/answers.conf")" 'MACHINE_ROLE=laptop'
    assert_contains "$(cat "$KIT_SERVER_DIR/answers.conf")" 'TIMEZONE=Europe/London'
}
