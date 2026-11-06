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
    for d in Downloads/complete Downloads/incomplete Movies 'TV Shows'; do
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

# The kit reads images from its compose files without a YAML parser (compose_images), so every
# module's compose files must follow the layout rules in modules/media-stack/compose.yml.
test_module_compose_files_follow_the_layout_rules() {
    load_libs
    local f svcs imgs bad='' line svc img
    for f in "$TEST_ROOT"/modules/*/compose*.yml; do
        [ -f "$f" ] || continue
        svcs=$(awk '/^[^ #]/ { top = $0 } top == "services:" && /^  [^ #]/ { print }' "$f")
        printf '%s\n' "$svcs" | grep -qv '^  [a-z0-9][a-z0-9_-]*:$' && bad="$bad
$f: service lines must be '  name:' (lowercase, digits, - and _)"
        imgs=$(compose_images "$f")
        [ "$(printf '%s\n' "$svcs" | grep -c .)" = "$(printf '%s\n' "$imgs" | grep -c .)" ] || bad="$bad
$f: every service needs exactly one '    image:' line"
        while read -r svc img; do
            [ -n "$svc" ] || continue
            [[ $img =~ ^[a-z0-9][a-z0-9./_-]*:[A-Za-z0-9._-]+$ ]] || bad="$bad
$f: $svc: image must be repo:tag with no digest or variables ($img)"
        done <<<"$imgs"
        line=$(grep -n '^    image:' "$f" | grep -v '^[0-9]*:    image: [^ ]*\( *#.*\)\{0,1\}$' | head -1)
        [ -z "$line" ] || bad="$bad
$f: odd image line: $line"
    done
    [ -z "$bad" ] || fail "$bad"
}

test_compose_images_reads_services_and_images() {
    load_libs
    local f=$TEST_TMP/c.yml
    printf '%s\n' 'services:' '  a:' '    image: x/a:1  # note' '    environment:' '      image: not-this' \
        '  b-2:' '    container_name: b' '    image: ghcr.io/y/b:latest' 'networks:' '  default:' >"$f"
    assert_eq 'a x/a:1
b-2 ghcr.io/y/b:latest' "$(compose_images "$f")"
}

test_compose_files_assembled_in_module_order() {
    load_libs
    fake_modules
    mkmod one PROJECT=p
    mkmod two PROJECT=p
    mkmod three PROJECT=other
    printf 'services:\n  a:\n    image: x/a:1\n' >"$KIT_MODULES_DIR/one/compose.yml"
    printf 'services:\n  b:\n    image: x/b:1\n' >"$KIT_MODULES_DIR/two/compose.yml"
    printf 'services:\n  a:\n    environment:\n      - X=1\n' >"$KIT_MODULES_DIR/three/compose.p.yml"
    modules_discover
    config_init
    local D=$KIT_SERVER_DIR/p
    mkdir -p "$D"
    assert_eq 'compose.d/10-one.yml:compose.d/11-two.yml:compose.d/12-three.yml' "$(compose_assemble p one two three)"
    assert_eq 'compose.d/10-one.yml' "$(compose_assemble p one)"
    assert_eq '10-one.yml' "$(ls "$D/compose.d")"     # files of modules no longer listed are gone
}

test_install_writes_compose_file_list() {
    secrets_src
    kit install --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    local D=$KIT_SERVER_DIR/media-stack
    assert_contains "$(cat "$D/.env")" 'COMPOSE_FILE=project.yml:compose.d/10-media-stack.yml:compose.d/11-plex.yml:compose.d/12-health.yml:compose.d/zz-images.yml'
    assert_contains "$(cat "$D/project.yml")" 'name: media-stack'
    cmp -s "$TEST_ROOT/modules/media-stack/compose.yml" "$D/compose.d/10-media-stack.yml" || fail "compose file not copied"
}

test_install_pins_every_service_once() {
    secrets_src
    kit install --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    local D=$KIT_SERVER_DIR/media-stack lock
    lock=$(grep -v '^#' "$D/images.lock")
    assert_eq 14 "$(printf '%s\n' "$lock" | grep -c .)"      # with Plex's plex-proxy
    printf '%s\n' "$lock" | grep -q '^sonarr lscr.io/linuxserver/sonarr:latest@sha256:[0-9a-f]\{64\}$' \
        || fail "no sonarr pin: $lock"
    assert_contains "$(cat "$D/compose.d/zz-images.yml")" "  sonarr:
    image: $(printf '%s\n' "$lock" | awk '$1 == "sonarr" { print $2 }')"
    assert_eq 14 "$(grep -c '^pull ' "$FAKE_DOCKER_LOG")"

    # A second install pulls nothing and moves no pin, even when newer images exist
    : >"$FAKE_DOCKER_LOG"
    FAKE_DOCKER_SALT=newer kit install >/dev/null 2>&1 || fail "second install failed"
    assert_eq "$lock" "$(grep -v '^#' "$D/images.lock")"
    assert_fails grep -q '^pull ' "$FAKE_DOCKER_LOG"
}

test_hold_chooses_the_tag_and_a_deleted_pin_is_redone() {
    secrets_src
    printf 'HOLD_sonarr=4.0.15 # testing, 2026-11\n' >"$TEST_TMP/a.conf"
    kit install --answers "$TEST_TMP/a.conf" --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    local L=$KIT_SERVER_DIR/media-stack/images.lock
    grep -q '^sonarr lscr.io/linuxserver/sonarr:4.0.15@sha256:' "$L" || fail "hold not used: $(cat "$L")"
    sed -i '' '/^radarr /d' "$L"
    : >"$FAKE_DOCKER_LOG"
    kit install >/dev/null 2>&1 || fail "second install failed"
    assert_eq 'pull -q lscr.io/linuxserver/radarr:latest' "$(grep '^pull ' "$FAKE_DOCKER_LOG")"
    grep -q '^radarr lscr.io/linuxserver/radarr:latest@sha256:' "$L" || fail "radarr not pinned again"
}

test_failed_pull_stops_the_install() {
    secrets_src
    local out
    out=$(FAKE_DOCKER_FAIL=pull kit install --secrets "$S" 2>&1) && fail "install should fail"
    assert_contains "$out" 'could not pull qmcgaw/gluetun:latest'
}

test_zz_images_only_lists_enabled_services() {
    load_libs
    fake_modules
    mkmod one PROJECT=p
    printf 'services:\n  a:\n    image: x/a:1\n' >"$KIT_MODULES_DIR/one/compose.yml"
    modules_discover
    config_init
    local D=$KIT_SERVER_DIR/p
    mkdir -p "$D"
    printf 'gone x/gone:1@sha256:%064d\n' 0 >"$D/images.lock"    # from a disabled module
    compose_assemble p one >/dev/null
    images_pin p one >/dev/null
    assert_contains "$(cat "$D/compose.d/zz-images.yml")" '  a:'
    assert_not_contains "$(cat "$D/compose.d/zz-images.yml")" 'gone'
    grep -q '^gone ' "$D/images.lock" || fail "the disabled module's pin should stay in the lock"
}

test_pbkdf2_matches_published_vectors() {
    load_libs
    # PBKDF2-HMAC-SHA512, password "password", salt "salt", 1 and 2 iterations
    assert_eq 867f70cf1ade02cff3752599a3a53dc4af34c7a669815ae5d513554e1c8cf252c02d470a285a0501bad999bfe943c08f050235d7d68b1da55e63f73b60a57fce \
        "$(pbkdf2_sha512 password 73616c74 1)"
    assert_eq e1d9c16aa681708a45f5c7c4e215ceb66e011a2e9f0040713f18aefdb866d53cf76cab2868a39b9f7840edce4fef5a82be67335c77a6068e04112754f27ccf4e \
        "$(pbkdf2_sha512 password 73616c74 2)"
    assert_eq c2FsdA== "$(hex_to_base64 73616c74)"
}

gen() { sed -n "s/^$1=\"\\(.*\\)\"\$/\\1/p" "$KIT_SERVER_DIR/kit/generated-secrets.conf"; }

test_install_seeds_app_settings() {
    secrets_src
    printf 'MEDIA_SUBNET=10.9.8.0/24\n' >"$TEST_TMP/a.conf"
    kit install --answers "$TEST_TMP/a.conf" --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    local A=$KIT_SERVER_DIR/appdata/media-stack app
    for app in sonarr radarr prowlarr; do
        assert_eq "$(gen "$(printf '%s' "$app" | tr '[:lower:]' '[:upper:]')_API_KEY")" "$(xml_value_of "$A/$app/config.xml")"
        assert_eq 600 "$(stat -f %Lp "$A/$app/config.xml")"
    done
    local q=$A/qbittorrent/qBittorrent/qBittorrent.conf
    assert_contains "$(cat "$q")" 'AuthSubnetWhitelist=10.9.8.1/32'
    assert_contains "$(cat "$q")" 'Session\Interface=tun0'
    # The stored hash is the generated password's
    load_libs
    local b64 salt hash
    b64=$(sed -n 's/^Password_PBKDF2="@ByteArray(\(.*\))"$/\1/p' "$q")
    salt=$(printf '%s' "${b64%%:*}" | base64 -D | od -An -tx1 | tr -d ' \n')
    hash=$(printf '%s' "${b64#*:}" | base64 -D | od -An -tx1 | tr -d ' \n')
    assert_eq "$hash" "$(pbkdf2_sha512 "$(gen QBITTORRENT_PASSWORD)" "$salt" 100000)"
    assert_contains "$(cat "$A/qbittorrent/qBittorrent/categories.json")" '"tv-sonarr"'
    local y; y=$(cat "$A/bazarr/config/config.yaml")
    assert_contains "$y" "apikey: '$(gen BAZARR_API_KEY)'"
    assert_contains "$y" "apikey: '$(gen SONARR_API_KEY)'"
    assert_contains "$y" "apikey: '$(gen RADARR_API_KEY)'"
}
xml_value_of() { sed -n 's|.*<ApiKey>\(.*\)</ApiKey>.*|\1|p' "$1"; }

test_seeded_files_are_never_overwritten_and_existing_keys_are_used() {
    secrets_src
    local A=$KIT_SERVER_DIR/appdata/media-stack
    mkdir -p "$A/sonarr"
    printf '<Config>\n  <ApiKey>dddddddddddddddddddddddddddddddd</ApiKey>\n</Config>\n' >"$A/sonarr/config.xml"
    kit install --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    assert_contains "$(cat "$A/sonarr/config.xml")" 'dddddddddddddddddddddddddddddddd'
    assert_contains "$(cat "$A/bazarr/config/config.yaml")" "apikey: 'dddddddddddddddddddddddddddddddd'"
    printf '# changed by the app\n' >>"$A/qbittorrent/qBittorrent/qBittorrent.conf"
    local before; before=$(cat "$A/qbittorrent/qBittorrent/qBittorrent.conf" "$A/bazarr/config/config.yaml")
    kit install >/dev/null 2>&1 || fail "second install failed"
    assert_eq "$before" "$(cat "$A/qbittorrent/qBittorrent/qBittorrent.conf" "$A/bazarr/config/config.yaml")"
}

test_install_starts_the_stack_and_reports() {
    secrets_src
    local out
    out=$(kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_eq "compose up -d --wait --wait-timeout 300 --remove-orphans (in $KIT_SERVER_DIR/media-stack)" \
        "$(grep '^compose up' "$FAKE_DOCKER_LOG")"
    assert_contains "$out" 'media-stack is running'
    assert_contains "$out" 'http://localhost:7575'
    assert_contains "$out" 'sign in as admin with ARR_PASSWORD'
    assert_not_contains "$out" 'each asks you to create a login'
    assert_not_contains "$out" "$(gen QBITTORRENT_PASSWORD)"     # never printed
}

test_failed_start_stops_with_hints() {
    secrets_src
    local out
    out=$(FAKE_DOCKER_FAIL=up kit install --secrets "$S" 2>&1) && fail "install should fail"
    assert_contains "$out" "media-stack didn't start"
    assert_contains "$out" 'gluetun not healthy means the VPN did not connect'
    grep -q '^compose ps -a' "$FAKE_DOCKER_LOG" || fail "no compose ps after the failure"
    assert_not_contains "$out" 'http://localhost:7575'
}

test_checklist_waits_for_modules_and_keys() {
    secrets_src
    local out
    out=$(kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Plex: open'                     # the kit installs Plex
    assert_not_contains "$out" 'Jellyfin: the kit made'     # not enabled
    assert_not_contains "$out" 'add ntfy too'               # no Healthchecks URL
    printf 'HEALTHCHECK_URL="%s"\n' "$FAKE_HC_URL" >>"$KIT_SERVER_DIR/secrets.conf"
    out=$(kit install 2>&1) || fail "second install failed: $out"
    assert_contains "$out" 'add ntfy too'
}
