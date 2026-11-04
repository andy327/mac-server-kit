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
