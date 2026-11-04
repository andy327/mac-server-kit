# shellcheck shell=bash
# Install steps after configuration (lib/project.sh), with the repo's modules

secrets_src() {     # a filled-in secrets file
    S=$TEST_TMP/secrets-src.conf
    printf '%s\n' "WIREGUARD_PRIVATE_KEY=\"$FAKE_WG\"" "TS_AUTHKEY=\"$FAKE_TSKEY\"" >"$S"
}

test_install_creates_folders() {
    secrets_src
    local out
    out=$(kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    local d
    for d in bin appdata backups logs kit; do
        [ -d "$KIT_SERVER_DIR/$d" ] || fail "no $d folder"
    done
    for d in Downloads Movies 'TV Shows'; do
        [ -d "$HOME/Media/$d" ] || fail "no Media/$d folder"
    done
}

test_zprofile_line_added_once_and_existing_content_kept() {
    secrets_src
    printf 'export EDITOR=vim' >"$HOME/.zprofile"     # no final newline
    kit install --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    kit install >/dev/null 2>&1 || fail "second install failed"
    local z; z=$(cat "$HOME/.zprofile")
    assert_eq "export EDITOR=vim
export PATH=\"$KIT_SERVER_DIR/bin:\$PATH\"  # added by mac-server-kit" "$z"
}

# shellcheck disable=SC2016  # the $HOME and $PATH must stay literal
test_zprofile_line_uses_home_variable() {
    load_libs
    SERVER_DIR=$HOME/server  # read by zprofile_line
    export SERVER_DIR
    assert_eq 'export PATH="$HOME/server/bin:$PATH"  # added by mac-server-kit' "$(zprofile_line)"
}

test_media_root_on_unmounted_drive_is_refused() {
    secrets_src
    printf 'MEDIA_ROOT=/Volumes/NoSuchDrive-kit-test/Media\n' >"$TEST_TMP/answers.conf"
    local out
    out=$(kit install --answers "$TEST_TMP/answers.conf" --secrets "$S" 2>&1) && fail "install should fail"
    assert_contains "$out" "/Volumes/NoSuchDrive-kit-test isn't mounted"
    [ ! -e /Volumes/NoSuchDrive-kit-test ] || fail "created the drive's folder"
}

test_env_file_for_the_media_stack() {
    secrets_src
    kit install --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    local E=$KIT_SERVER_DIR/media-stack/.env
    assert_eq 600 "$(stat -f %Lp "$E")"
    local t; t=$(cat "$E")
    assert_contains "$t" 'COMPOSE_PROJECT_NAME=media-stack'
    assert_contains "$t" "MEDIA_ROOT='$HOME/Media'"
    assert_contains "$t" "APPDATA='$KIT_SERVER_DIR/appdata/media-stack'"
    assert_contains "$t" "PUID='$(id -u)'"
    assert_contains "$t" "WIREGUARD_PRIVATE_KEY='$FAKE_WG'"
    assert_contains "$t" "VPN_PORT_FORWARDING='on'"
    assert_contains "$t" "SERVER_COUNTRIES='United States'"
    assert_contains "$t" "MEDIA_SUBNET='172.31.97.0/24'"
    [ -d "$KIT_SERVER_DIR/appdata/media-stack" ] || fail "no app data folder"
    [ ! -e "$KIT_SERVER_DIR/health-web" ] || fail "made a folder for a project with no files yet"
}

test_env_follows_answers_and_is_regenerated() {
    secrets_src
    kit install --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    printf 'VPN_PROVIDER=nordvpn\nVPN_COUNTRIES=Canada\n' >>"$KIT_SERVER_DIR/answers.conf"
    kit install >/dev/null 2>&1 || fail "second install failed"
    local t; t=$(cat "$KIT_SERVER_DIR/media-stack/.env")
    assert_contains "$t" "VPN_SERVICE_PROVIDER='nordvpn'"
    assert_contains "$t" "VPN_PORT_FORWARDING='off'"
    assert_contains "$t" "SERVER_COUNTRIES='Canada'"
    assert_not_contains "$t" "VPN_PORT_FORWARDING='on'"
}

# shellcheck disable=SC2016  # the ${...} are for render_value
test_render_value() {
    load_libs
    fake_modules
    mkmod m PROJECT=p
    printf 'answers|A|alpha|||\nsecrets|OPT||?any|Optional|\n' >"$KIT_MODULES_DIR/m/prompts"
    modules_discover
    config_init
    printf 'B="${A} stays"\n' >>"$SECRETS"
    RENDER_PROJECT=p  # read by render_value
    export RENDER_PROJECT
    assert_eq 'x-alpha-y' "$(render_value 'x-${A}-y')"
    assert_eq '${A} stays/alpha' "$(render_value '${B}/${A}')"
    assert_eq '[]' "$(render_value '[${OPT}]')"
    assert_eq "$KIT_SERVER_DIR/appdata/p" "$(render_value '${KIT_APPDATA}')"
    assert_fails render_value '${NOT_DECLARED}'
}

# shellcheck disable=SC2016  # the ${A} is for env_lines
test_env_refuses_quotes_and_duplicate_keys() {
    load_libs
    fake_modules
    mkmod m PROJECT=p
    printf 'answers|A|it'"'"'s|||\n' >"$KIT_MODULES_DIR/m/prompts"
    printf 'X|${A}|\n' >"$KIT_MODULES_DIR/m/env"
    modules_discover
    config_init
    assert_fails env_lines p m
    printf 'X|1|\nX|2|\n' >"$KIT_MODULES_DIR/m/env"
    assert_fails env_lines p m
    printf 'X|1|A=no\nX|2|\n' >"$KIT_MODULES_DIR/m/env"
    assert_eq 'X=2' "$(env_lines p m)"
}
