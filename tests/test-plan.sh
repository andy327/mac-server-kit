# shellcheck shell=bash
# ./kit install --plan (and add|disable --plan): what it lists, and that it changes nothing. Every
# test snapshots the home folder and ~/server before and after, and reads the fakes' logs: only
# read-only docker and launchctl calls, only GETs (and registry HEADs) to the apps, no brew, no
# sudo.

secrets_src() {     # a filled-in secrets file
    S=$TEST_TMP/secrets-src.conf
    printf '%s\n' "WIREGUARD_PRIVATE_KEY=\"$FAKE_WG\"" "TS_AUTHKEY=\"$FAKE_TSKEY\"" >"$S"
}

# Every file and folder under the home folder and ~/server: path, size, mode, mtime, checksum
snap() {
    find "$HOME" "$KIT_SERVER_DIR" 2>/dev/null | sort | while IFS= read -r f; do
        if [ -f "$f" ]; then
            printf '%s %s\n' "$(stat -f '%N %z %p %m' "$f")" "$(shasum -a 256 <"$f" | cut -c1-16)"
        else
            stat -f '%N %p %m' "$f"
        fi
    done
}

logs_reset() { : >"$FAKE_DOCKER_LOG"; : >"$FAKE_CURL_LOG"; : >"$FAKE_LAUNCHD_LOG"; : >"$FAKE_BREW_LOG"; : >"$FAKE_HOST_LOG"; }

# What the fakes saw: nothing that changes anything
assert_read_only() {
    local bad
    bad=$(grep -vE '^(info|ps -a --format|inspect |image inspect |context inspect |compose .* config( --hash [^ ]+)? \(in |compose version)' "$FAKE_DOCKER_LOG" 2>/dev/null)
    [ -z "$bad" ] || fail "docker calls that change something: $bad"
    bad=$(grep -vE '^(GET|HEAD) ' "$FAKE_CURL_LOG" 2>/dev/null)
    [ -z "$bad" ] || fail "API calls other than GET: $bad"
    bad=$(grep -vE '^(print|list) ' "$FAKE_LAUNCHD_LOG" 2>/dev/null)
    [ -z "$bad" ] || fail "launchctl calls that change something: $bad"
    bad=$(grep -v '^brew --prefix$' "$FAKE_BREW_LOG" 2>/dev/null)
    [ -z "$bad" ] || fail "brew calls: $bad"
    bad=$(grep -E '^(sudo|open|defaults (write|import|export)|osascript)' "$FAKE_HOST_LOG" 2>/dev/null)
    [ -z "$bad" ] || fail "host commands that change something: $bad"
}

plan() {            # args... -> OUT, after checking it changed nothing
    local before
    before=$(snap)
    logs_reset
    OUT=$(kit install --plan "$@" 2>&1) || fail "plan failed: $OUT"
    assert_eq "$before" "$(snap)" "the plan changed files"
    assert_read_only
}

installed() {       # a first install with the fakes
    secrets_src
    kit install --secrets "$S" >/dev/null 2>&1 || fail "install failed"
}

test_plan_on_a_fresh_mac_lists_everything_and_writes_nothing() {
    secrets_src
    plan --secrets "$S"
    [ ! -e "$KIT_SERVER_DIR" ] || fail "the plan made ~/server"
    assert_contains "$OUT" 'Ask for MEDIA_ROOT (answers.conf), default ~/Media'
    assert_contains "$OUT" 'secrets.conf: TS_AUTHKEY (value not shown)'
    assert_contains "$OUT" 'generated-secrets.conf: SONARR_API_KEY (made at random)'
    assert_not_contains "$OUT" "$FAKE_TSKEY"
    assert_contains "$OUT" 'Make folder'
    assert_contains "$OUT" 'TV Shows'
    assert_contains "$OUT" 'Add a line to ~/.zprofile'
    assert_contains "$OUT" 'Plex: install Plex Media Server'
    assert_contains "$OUT" 'Glances: install it'
    assert_contains "$OUT" '+ New .env'
    assert_contains "$OUT" 'Pull lscr.io/linuxserver/sonarr:latest for sonarr and pin it'
    assert_contains "$OUT" 'Pull ghcr.io/homarr-labs/homarr:v2.11.1 for homarr and pin it in images.lock (newest release of v2.*)'
    assert_contains "$OUT" 'Seed '
    assert_contains "$OUT" 'Create sonarr (lscr.io/linuxserver/sonarr:latest)'
    assert_contains "$OUT" 'media: a new machine in your tailnet'
    assert_contains "$OUT" 'Load job backup-all: weekly, Sunday 05:30'
    assert_contains "$OUT" "can't tell: media-stack's settings: media-stack isn't running yet"
    assert_contains "$OUT" 'nothing to check first'
    assert_contains "$OUT" 'Plan only: nothing was changed.'
}

test_plan_holds_without_the_sandbox() {
    secrets_src
    KIT_PLAN_SANDBOX=off plan --secrets "$S"
    assert_contains "$OUT" 'Plan only: nothing was changed.'
    assert_not_contains "$OUT" "sandbox kept it"
}

test_plan_after_an_install_has_nothing_to_do() {
    installed
    plan
    assert_contains "$OUT" 'Unchanged: .env, project.yml'
    assert_contains "$OUT" 'Unchanged: gluetun qbittorrent prowlarr sonarr radarr'
    assert_contains "$OUT" 'Job backup-all: weekly, Sunday 05:30 (already loaded)'
    assert_contains "$OUT" 'Sonarr: library folder /data/TV Shows (already set)'
    assert_contains "$OUT" 'Homarr: Sonarr tile (already there)'
    assert_not_contains "$OUT" 'Recreate'
    assert_not_contains "$OUT" 'Pull '
    assert_not_contains "$OUT" '+ Seed'
    assert_contains "$OUT" 'nothing to check first'
}

# qBittorrent runs on Gluetun's network: Compose labels it with that network resolved to
# Gluetun's container, so the plan hashes it the same way. A new Gluetun takes qBittorrent with it.
test_plan_follows_a_shared_network() {
    installed
    printf 'VPN_COUNTRIES=Canada\n' >>"$KIT_SERVER_DIR/answers.conf"
    plan
    assert_contains "$OUT" 'Recreate gluetun (its settings changed; its data stays)'
    assert_contains "$OUT" "Recreate qbittorrent (it shares gluetun's network, which is made again; its data stays)"
    assert_not_contains "$OUT" 'Recreate sonarr'
}

# A named volume is compared by its Docker name (<project>_<key>), not by its path
test_plan_compares_named_volumes_by_name() {
    local c=$TEST_TMP/containers m=$TEST_TMP/mounts
    installed
    printf 'MODULES=plex tracearr\n' >>"$KIT_SERVER_DIR/answers.conf"
    printf '%s\n' 'tracearr|media-stack|tracearr|abc|ghcr.io/connorgallopo/tracearr:latest|running||' >"$c"
    printf '%s\n' 'tracearr|/var/lib/docker/volumes/media-stack_tracearr_images/_data|/data/tracearr/image-cache|volume|media-stack_tracearr_images' >"$m"
    FAKE_DOCKER_CONTAINERS=$c FAKE_DOCKER_MOUNTS=$m plan
    assert_contains "$OUT" 'Recreate tracearr'
    assert_not_contains "$OUT" 'image-cache would come from'
    printf '%s\n' 'tracearr|/var/lib/docker/volumes/oldstack_tracearr_images/_data|/data/tracearr/image-cache|volume|oldstack_tracearr_images' >"$m"
    FAKE_DOCKER_CONTAINERS=$c FAKE_DOCKER_MOUNTS=$m plan
    assert_contains "$OUT" 'tracearr: /data/tracearr/image-cache would come from the Docker volume media-stack_tracearr_images instead of the volume oldstack_tracearr_images'
}

test_plan_shows_changed_settings_pins_and_jobs() {
    installed
    local lock=$KIT_SERVER_DIR/media-stack/images.lock plist
    printf 'TIMEZONE=Europe/London\n' >>"$KIT_SERVER_DIR/answers.conf"
    grep -v '^sonarr ' "$lock" >"$lock.new" && mv "$lock.new" "$lock"
    printf 'WIREGUARD_PRIVATE_KEY="%s"\n' 'bGyBWqcVhzpzkFpWbUAYcIY+xGqoUZpDe1rqAqKDdHc=' >>"$KIT_SERVER_DIR/secrets.conf"  # check-private: allow
    plist=$HOME/Library/LaunchAgents/io.github.andy327.mac-server-kit.backup-all.plist
    sed 's/<integer>30<\/integer>/<integer>45<\/integer>/' "$plist" >"$plist.new" && mv "$plist.new" "$plist"
    plan
    assert_contains "$OUT" '+ Change .env:'
    assert_contains "$OUT" "+TIMEZONE='Europe/London'"
    assert_contains "$OUT" "-TIMEZONE="
    assert_contains "$OUT" '+WIREGUARD_PRIVATE_KEY=•••'
    assert_not_contains "$OUT" 'bGyBWqcVhzpzkFpWbUAYcIY'
    assert_not_contains "$OUT" "$FAKE_WG"
    assert_contains "$OUT" 'Pull lscr.io/linuxserver/sonarr:latest for sonarr and pin it'
    assert_contains "$OUT" 'Recreate sonarr (pinned to lscr.io/linuxserver/sonarr:latest; its data stays)'
    assert_contains "$OUT" 'Recreate gluetun (its settings changed; its data stays)'
    assert_contains "$OUT" 'which is then reloaded'
}

test_plan_reads_the_old_layout_move() {
    installed
    local d=$FAKE_CURL_DIR
    printf '{"id":1,"path":"/tv"}\n{"id":2,"path":"/data/TV Shows"}\n{"id":3,"path":"/anime"}\n' >"$d/127.0.0.1_8989_api_v3_rootfolder"
    printf '{"id":1,"title":"Show A","path":"/tv/Show A"}\n{"id":2,"title":"Show B","path":"/tv/Show B"}\n' >"$d/127.0.0.1_8989_api_v3_series"
    rm -f "$d"/qb-*
    FAKE_QB_OLD=1 plan
    assert_contains "$OUT" 'Sonarr: 2 in its library would move from /tv to /data/TV Shows'
    assert_contains "$OUT" 'Sonarr: remove the old library folder /tv'
    assert_contains "$OUT" 'Sonarr: its library folder /anime isn'"'"'t under /data'
    assert_contains "$OUT" 'torrents would move to /data/Downloads and be rechecked'
    assert_contains "$OUT" 'to check first'
}

test_add_plan_leaves_modules_alone() {
    installed
    local before
    before=$(grep '^MODULES=' "$KIT_SERVER_DIR/answers.conf" || true)
    local snap0
    snap0=$(snap)
    logs_reset
    OUT=$(kit add romm --plan 2>&1) || fail "add --plan failed: $OUT"
    assert_eq "$snap0" "$(snap)" "add --plan changed files"
    assert_read_only
    assert_eq "$before" "$(grep '^MODULES=' "$KIT_SERVER_DIR/answers.conf" || true)"
    assert_contains "$OUT" 'MODULES=romm for this plan only'
    assert_contains "$OUT" 'Enable romm'
    assert_contains "$OUT" 'answers.conf: MODULES=romm'
    assert_contains "$OUT" 'generated-secrets.conf: ROMM_DB_PASSWORD'
    assert_contains "$OUT" 'Create romm (rommapp/romm:5)'
    assert_contains "$OUT" "can't tell: romm's settings: romm isn't running yet"
}

# An older stack already running: its containers have the kit's names, its own data folders and
# /tv from a folder of another name; Plex runs in a container; an old backup job
test_plan_flags_an_existing_stack() {
    local c=$TEST_TMP/containers m=$TEST_TMP/mounts
    mkdir -p "$HOME/Media/TV" "$HOME/old/sonarr" "$HOME/Library/LaunchAgents"
    touch "$HOME/Media/TV/show.mkv" "$HOME/old/sonarr/sonarr.db"
    printf '<plist><string>/Users/x/bin/backup-media.sh</string></plist>\n' >"$HOME/Library/LaunchAgents/com.example.backup.plist"
    printf '%s\n' 'sonarr|oldstack|sonarr|abc|lscr.io/linuxserver/sonarr:latest|running|127.0.0.1:8989->8989/tcp|' \
        'oldradarr|oldstack|radarr|abc|lscr.io/linuxserver/radarr:latest|running|127.0.0.1:7878->7878/tcp|' \
        'plex|oldstack|plex|abc|plexinc/pms-docker:latest|running||' >"$c"
    printf '%s\n' "sonarr|$HOME/old/sonarr|/config" "sonarr|$HOME/Media/TV|/tv" >"$m"
    secrets_src
    FAKE_DOCKER_CONTAINERS=$c FAKE_DOCKER_MOUNTS=$m plan --secrets "$S"
    assert_contains "$OUT" 'sonarr: a container named sonarr already exists (compose project oldstack'
    assert_contains "$OUT" "/config would come from"
    assert_contains "$OUT" "which is empty, instead of ~/old/sonarr: sonarr starts fresh"
    assert_contains "$OUT" '/tv comes from ~/Media/TV now, but the install moves'
    assert_contains "$OUT" 'radarr: port 7878 is taken by the container oldradarr'
    assert_contains "$OUT" 'plex runs in a container here (plex, plexinc/pms-docker:latest)'
    assert_contains "$OUT" 'has files but no TV Shows folder'
    assert_contains "$OUT" 'com.example.backup.plist, mentions backup'
    assert_contains "$OUT" "can't tell: whether lscr.io/linuxserver/sonarr:latest is newer"
    assert_contains "$OUT" 'to check first (⚠)'
}

test_plan_compares_images_with_the_registry() {
    local c=$TEST_TMP/containers ref=lscr.io/linuxserver/sonarr:latest same
    printf '%s\n' "sonarr|oldstack|sonarr|abc|$ref|running||" >"$c"
    same=sha256:$(printf '%s' "$ref" | shasum -a 256 | cut -c1-64)
    secrets_src
    FAKE_DOCKER_CONTAINERS=$c FAKE_REGISTRY_DIGEST=$same plan --secrets "$S"
    assert_contains "$OUT" "sonarr: $ref is the image it runs now"
    rm -rf "$KIT_SERVER_DIR"
    FAKE_DOCKER_CONTAINERS=$c FAKE_REGISTRY_DIGEST=sha256:0123 plan --secrets "$S"
    assert_contains "$OUT" "sonarr: $ref is newer than the image it runs now"
}

test_plan_flags_romm_risks() {
    installed
    local c=$TEST_TMP/containers
    printf 'MODULES=romm\n' >>"$KIT_SERVER_DIR/answers.conf"
    mkdir -p "$HOME/Games/gba/roms" "$KIT_SERVER_DIR/appdata/romm/mariadb"
    touch "$HOME/Games/gba/roms/game.gba" "$KIT_SERVER_DIR/appdata/romm/mariadb/ibdata1"
    printf '%s\n' 'romm|romm|romm|abc|rommapp/romm:3.10.2|running||3.10.2' >"$c"
    FAKE_DOCKER_CONTAINERS=$c plan
    assert_contains "$OUT" "RomM's Structure B, so the kit makes no roms/ or bios/ folders"
    assert_contains "$OUT" 'ROMM_DB_PASSWORD is new, but'
    assert_contains "$OUT" "made with another value: the app couldn't open it"
    assert_contains "$OUT" 'ROMM_AUTH_SECRET_KEY is new, but'
    assert_contains "$OUT" 'everyone signed in is signed out'
    assert_contains "$OUT" 'romm: RomM 3.10.2 runs now, and the kit runs RomM 5'
    [ ! -d "$HOME/Games/roms" ] || fail "the plan made roms/"
}

test_romm_seed_leaves_a_structure_b_library_alone() {
    installed
    printf 'MODULES=romm\n' >>"$KIT_SERVER_DIR/answers.conf"
    mkdir -p "$HOME/Games/gba/roms"
    local out
    out=$(kit install 2>&1) || fail "install failed: $out"
    assert_contains "$out" "RomM's Structure B, so the kit makes no roms/ or bios/ folders"
    [ ! -d "$HOME/Games/roms" ] || fail "the seed made roms/ in a Structure B library"
    [ ! -d "$HOME/Games/bios" ] || fail "the seed made bios/ in a Structure B library"
}

test_plan_says_when_docker_is_down() {
    secrets_src
    FAKE_DOCKER_DOWN=1 plan --secrets "$S"
    assert_contains "$OUT" "can't tell: Docker isn't answering"
}

# The guards themselves: each refuses, and says it's a kit bug
# shellcheck disable=SC2034  # in_plan reads KIT_PLAN
test_plan_guards_refuse_changes() {
    load_libs
    KIT_PLAN=1 PLAN_DIR=$TEST_TMP/plan
    mkdir -p "$PLAN_DIR"
    plan_guards
    mkdir -p "$KIT_SERVER_DIR"
    assert_fails write_generated "$KIT_SERVER_DIR/x" </dev/null
    [ ! -e "$KIT_SERVER_DIR/x" ] || fail "write_generated wrote outside the plan's folder"
    assert_fails kv_append "$KIT_SERVER_DIR/answers.conf" K v
    mark_write "$KIT_SERVER_DIR/kit-checked" x >/dev/null
    [ ! -e "$KIT_SERVER_DIR/kit-checked" ] || fail "mark_write wrote in a plan"
    assert_fails dk pull nginx:latest
    assert_fails dk compose up -d
    assert_fails dk compose -p x --project-directory /tmp down
    assert_fails kcurl -X POST http://127.0.0.1:8989/api
    assert_fails kcurl --data x http://127.0.0.1:8989/api
    assert_fails kcurl -o "$KIT_SERVER_DIR/f" http://127.0.0.1/
    assert_fails klaunchctl bootstrap gui/501 x.plist
    assert_fails kbrew install glances
    assert_fails ksudo true
    assert_fails kpmset -a sleep 0
    assert_fails kdefaults write x y z
    assert_ok dk ps -a
    assert_ok dk compose -p x --project-directory /tmp --env-file /dev/null -f /dev/null config --hash '*'
    assert_ok kcurl -fsS -o /dev/null http://127.0.0.1:8989/api/v3/rootfolder
    assert_ok klaunchctl list
    [ -s "$PLAN_DIR/refused" ] || fail "refusals weren't recorded"
    # api_call answers a change without sending it
    : >"$FAKE_CURL_LOG"
    api_call POST http://127.0.0.1:8989/api/v3/rootfolder key '{}' || fail "api_call POST should answer as if it worked"
    assert_eq '' "$(cat "$FAKE_CURL_LOG")"
}
