# shellcheck shell=bash
# Backups, restores and updates: the runtime scripts in modules/core/bin, after a (fake) install,
# against tests/fake-docker and tests/fake-curl. The weekly jobs, release series (v2.*) and the
# lock's track column.
# shellcheck disable=SC2010,SC2012  # ls of the kit's own folder names

installed() {       # a fake install with some app data, and no after-start check
    S=$TEST_TMP/secrets-src.conf
    printf '%s\n' "WIREGUARD_PRIVATE_KEY=\"$FAKE_WG\"" "TS_AUTHKEY=\"$FAKE_TSKEY\"" \
        'HEALTHCHECK_URL=""' 'NTFY_TOPIC=""' >"$S"
    kit install --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    B=$KIT_SERVER_DIR/bin
    A=$KIT_SERVER_DIR/appdata/media-stack
    D=$KIT_SERVER_DIR/media-stack
    BK=$KIT_SERVER_DIR/backups/media-stack
    mkdir -p "$A/sonarr/MediaCover" "$A/sonarr/logs" "$A/radarr"
    echo db1 >"$A/sonarr/sonarr.db"
    echo poster >"$A/sonarr/MediaCover/1.jpg"
    echo log >"$A/sonarr/logs/sonarr.txt"
    echo db1 >"$A/radarr/radarr.db"
    # check-media-stack talks to the real apps; the tests leave it out
    sed -i '' "s/^AFTER_START_media_stack=.*/AFTER_START_media_stack=''/" "$KIT_SERVER_DIR/kit/runtime.conf"
}
newest() { ls -1d "$BK"/media-stack-[0-9]* | sort | tail -n 1; }

test_backup_project_copies_app_data_and_pins() {
    installed
    local out
    out=$("$B/backup-media-stack" 2>&1) || fail "backup failed: $out"
    local n; n=$(newest)
    assert_eq 700 "$(stat -f %Lp "$n")"
    local c; c=$(tar -tzf "$n/appdata.tgz")
    assert_contains "$c" './sonarr/sonarr.db'
    assert_not_contains "$c" 'MediaCover'
    assert_not_contains "$c" 'sonarr/logs'
    assert_contains "$(tar -tzf "$n/project.tgz")" 'images.lock'
    assert_contains "$(cat "$n/manifest.txt")" 'sonarr lscr.io/linuxserver/sonarr:latest@sha256:'
    assert_contains "$(cat "$FAKE_DOCKER_LOG")" 'compose stop sonarr radarr'
    assert_contains "$(cat "$FAKE_DOCKER_LOG")" 'compose start sonarr radarr'
    assert_contains "$out" 'WARNING: nothing at homarr/db/db.sqlite'     # not in this fake app data
}

# A big app data folder (Tracearr's database is thousands of files): the check for the expected
# files still finds them, with no broken pipe
test_backup_finds_expected_files_in_a_big_backup() {
    installed
    mkdir -p "$A/aaa-many"
    (cd "$A/aaa-many" && for i in $(seq 1 6000); do : >"file-with-a-long-name-$i"; done)
    local out
    out=$("$B/backup-media-stack" 2>&1) || fail "backup failed: $out"
    assert_not_contains "$out" 'Broken pipe'
    assert_not_contains "$out" 'nothing at sonarr/sonarr.db'
    assert_not_contains "$out" 'nothing at radarr/radarr.db'
    assert_contains "$out" 'WARNING: nothing at homarr/db/db.sqlite'
}

test_backup_keeps_the_newest_eight() {
    installed
    local i
    mkdir -p "$BK"
    for i in 1 2 3 4 5 6 7 8 9; do mkdir "$BK/media-stack-2020-01-0$i-000000"; done
    mkdir "$BK/pre-restore-2020-01-01-000000"
    "$B/backup-project" media-stack >/dev/null 2>&1 || fail "backup failed"
    assert_eq 8 "$(ls -1d "$BK"/media-stack-[0-9]* | grep -c .)"
    [ ! -e "$BK/media-stack-2020-01-02-000000" ] || fail "kept an old backup"
    [ -e "$BK/pre-restore-2020-01-01-000000" ] || fail "removed a restore's folder"
}

test_a_failed_backup_leaves_nothing_and_restarts_the_apps() {
    installed
    chmod 000 "$A/radarr"
    local out
    out=$("$B/backup-project" media-stack 2>&1) && fail "backup should fail"
    chmod 755 "$A/radarr"
    assert_contains "$out" 'FAILED, removing the partial'
    [ -z "$(ls -1d "$BK"/media-stack-[0-9]* 2>/dev/null)" ] || fail "left a partial backup"
    assert_contains "$(cat "$FAKE_DOCKER_LOG")" 'compose start sonarr radarr'
}

# Docker refuses to start a container it still holds an old process record for (seen on a real
# server after OrbStack trouble): the backup recreates it, and the backup stands
test_backup_recreates_an_app_docker_wont_start_again() {
    installed
    local out
    out=$(FAKE_DOCKER_STUCK=radarr "$B/backup-media-stack" 2>&1) || fail "backup failed: $out"
    assert_contains "$out" 'AlreadyExists'
    assert_contains "$out" 'Not running: radarr. Recreating'
    assert_not_contains "$out" 'still not running'
    assert_contains "$(cat "$FAKE_DOCKER_LOG")" 'compose up -d --no-deps --force-recreate radarr ('
    [ -n "$(newest)" ] || fail "no backup"
}

# One that won't start even then: the backup is kept, but it fails, naming only that app
test_backup_fails_when_an_app_it_stopped_stays_down() {
    installed
    local out
    out=$(FAKE_DOCKER_STUCK=radarr FAKE_DOCKER_STUCK_HARD=1 "$B/backup-media-stack" 2>&1) && fail "backup should fail"
    assert_contains "$out" 'WARNING: still not running: radarr.'
    assert_not_contains "$out" 'still not running: sonarr'
    assert_contains "$out" 'the backup is complete, but some apps it stopped'
    assert_not_contains "$out" 'FAILED, removing the partial'
    [ -n "$(newest)" ] || fail "removed a complete backup"
}

# The same in a restore: its start recreates what Docker won't start
test_restore_recreates_an_app_docker_wont_start_again() {
    installed
    "$B/backup-project" media-stack >/dev/null 2>&1 || fail "backup failed"
    : >"$FAKE_DOCKER_LOG"
    local out
    out=$(FAKE_DOCKER_STUCK=sonarr RESTORE_YES=1 "$B/restore-media-stack" 2>&1) || fail "restore failed: $out"
    assert_contains "$out" 'Not running: sonarr. Recreating'
    assert_contains "$(cat "$FAKE_DOCKER_LOG")" 'compose up -d --no-deps --force-recreate sonarr ('
    assert_eq 2 "$(grep -c 'compose up -d --wait' "$FAKE_DOCKER_LOG")"
}

test_restore_project_puts_data_and_pins_back() {
    installed
    "$B/backup-project" media-stack >/dev/null 2>&1 || fail "backup failed"
    local pin; pin=$(awk '$1 == "sonarr" { print $2 }' "$D/images.lock")
    echo broken >"$A/sonarr/sonarr.db"
    sed -i '' "s|^sonarr .*|sonarr lscr.io/linuxserver/sonarr:latest@sha256:$(printf '%064d' 0)|" "$D/images.lock"
    local out
    out=$(RESTORE_YES=1 "$B/restore-media-stack" 2>&1) || fail "restore failed: $out"
    assert_contains "$out" 'backup sonarr lscr.io/linuxserver/sonarr'   # the pin change it shows
    assert_eq db1 "$(cat "$A/sonarr/sonarr.db")"
    assert_eq poster "$(cat "$A/sonarr/MediaCover/1.jpg")"         # carried over
    assert_contains "$(cat "$D/compose.d/zz-images.yml")" "image: $pin"
    local aside; aside=$(ls -1d "$BK"/pre-restore-*)
    assert_eq broken "$(cat "$aside/appdata/sonarr/sonarr.db")"
    assert_contains "$(cat "$FAKE_DOCKER_LOG")" 'compose up -d --wait'
}

test_restore_asks_before_changing_anything() {
    installed
    "$B/backup-project" media-stack >/dev/null 2>&1 || fail "backup failed"
    echo changed >"$A/sonarr/sonarr.db"
    local out
    out=$("$B/restore-project" media-stack </dev/null 2>&1) && fail "restore should refuse"
    assert_contains "$out" 'run it in Terminal to confirm'
    assert_eq changed "$(cat "$A/sonarr/sonarr.db")"
}

test_update_project_repins_newer_images_after_a_backup() {
    installed
    local before; before=$(cat "$D/images.lock")
    local out
    out=$(FAKE_DOCKER_SALT=newer FAKE_REGISTRY_TAGS='v2.11.1 v2.12.0 v3.0.0' "$B/update-media-stack" 2>&1) \
        || fail "update failed: $out"
    [ -n "$(newest)" ] || fail "no backup first"
    assert_contains "$out" 'Updating:'
    local sonarr; sonarr=$(awk '$1 == "sonarr" { print $2 }' "$D/images.lock")
    assert_not_contains "$before" "$sonarr"
    assert_contains "$(cat "$D/compose.d/zz-images.yml")" "image: $sonarr"
    # Homarr follows its series to the newest 2.x, not 3.0
    assert_contains "$(cat "$D/images.lock")" 'homarr ghcr.io/homarr-labs/homarr:v2.12.0@sha256:'
    assert_contains "$(grep '^homarr ' "$D/images.lock")" ' v2.*'
    assert_contains "$(cat "$FAKE_DOCKER_LOG")" 'compose up -d --wait'
    [ ! -f "$KIT_SERVER_DIR/logs/health/.maintenance" ] || fail "left its maintenance window open"
    # Nothing newer: nothing restarts
    : >"$FAKE_DOCKER_LOG"
    out=$(FAKE_DOCKER_SALT=newer FAKE_REGISTRY_TAGS='v2.11.1 v2.12.0' "$B/update-project" media-stack 2>&1) \
        || fail "second update failed: $out"
    assert_contains "$out" 'media-stack is up to date; nothing restarted'
    assert_not_contains "$(cat "$FAKE_DOCKER_LOG")" 'up -d'
}

test_update_all_updates_and_ends_with_check_health() {
    installed
    local out
    out=$(FAKE_DOCKER_SALT=newer KIT_TEST_PATH=/nonexistent "$B/update-all" 2>&1)
    assert_contains "$out" '==== media-stack'
    assert_contains "$out" 'Everything updated'
    assert_contains "$out" 'health,'                         # check-health's report header
    assert_contains "$(cat "$FAKE_DOCKER_LOG")" 'image prune -af'
}

test_backup_and_restore_config() {
    installed
    local out
    out=$("$B/backup-config" 2>&1) || fail "backup-config failed: $out"
    local n; n=$(ls -1d "$KIT_SERVER_DIR"/backups/config/config-* | tail -n 1)
    local c; c=$(tar -tzf "$n/config.tgz")
    assert_contains "$c" 'answers.conf'
    assert_contains "$c" 'kit/generated-secrets.conf'
    assert_contains "$c" 'media-stack/images.lock'
    [ -x "$n/restore-config" ] || fail "no restore-config next to the archive"
    printf 'MEDIA_ROOT=/changed\n' >>"$KIT_SERVER_DIR/answers.conf"
    # Run from the backup folder itself, as on a new Mac
    out=$(RESTORE_YES=1 bash "$n/restore-config" 2>&1) || fail "restore-config failed: $out"
    assert_not_contains "$(cat "$KIT_SERVER_DIR/answers.conf")" '/changed'
    assert_contains "$(tar -xOzf "$KIT_SERVER_DIR"/backups/config/pre-restore-*/replaced.tgz answers.conf)" '/changed'
    assert_eq 600 "$(stat -f %Lp "$KIT_SERVER_DIR/kit/generated-secrets.conf")"
}

test_copy_backups_is_off_without_a_drive_and_copies_with_one() {
    installed
    "$B/backup-project" media-stack >/dev/null 2>&1 || fail "backup failed"
    local out
    out=$("$B/copy-backups" 2>&1) || fail "copy-backups failed: $out"
    assert_contains "$out" 'the external copy is off'
    local drive=$TEST_TMP/drive/server
    printf "BACKUP_DRIVE='%s'\nEXTERNAL_KEEP=2\n" "$drive" >>"$KIT_SERVER_DIR/kit/runtime.conf"
    out=$("$B/copy-backups" 2>&1) && fail "should refuse a folder that isn't on a drive"
    assert_contains "$out" 'must be a drive under /Volumes, or a folder on one'
    # An unplugged drive is skipped without a failure, so backup-all still succeeds
    printf "BACKUP_DRIVE='/Volumes/kit-no-such-drive/server'\n" >>"$KIT_SERVER_DIR/kit/runtime.conf"
    out=$("$B/copy-backups" 2>&1) || fail "an unplugged drive failed: $out"
    assert_contains "$out" "/Volumes/kit-no-such-drive isn't plugged in; nothing copied"
    assert_contains "$(cut -f2,3 "$KIT_SERVER_DIR/logs/copy-backups.status")" "skipped	/Volumes/kit-no-such-drive isn't plugged in"
    printf 'BACKUP_DRIVE=/Volumes/kit-no-such-drive/server\n' >>"$KIT_SERVER_DIR/answers.conf"
    out=$(kit status 2>&1)
    assert_contains "$out" "To /Volumes/kit-no-such-drive/server, after each weekly backup-all"
    assert_contains "$out" "Last try"
    assert_contains "$out" "No copy has worked yet"
    printf "BACKUP_DRIVE='%s'\n" "$drive" >>"$KIT_SERVER_DIR/kit/runtime.conf"
    mkdir -p "$BK/pre-restore-2020-01-01-000000" "$BK/media-stack-2020-01-01-000000" "$BK/media-stack-2020-01-02-000000"
    out=$(KIT_TEST_ANY_DRIVE=1 "$B/copy-backups" 2>&1) || fail "copy failed: $out"
    [ -f "$drive/media-stack/$(basename "$(newest)")/appdata.tgz" ] || fail "not copied"
    [ ! -e "$drive/media-stack/pre-restore-2020-01-01-000000" ] || fail "copied a restore's folder"
    assert_eq 2 "$(ls -1d "$drive"/media-stack/media-stack-[0-9]* | grep -c .)"
    assert_eq 3 "$(ls -1d "$BK"/media-stack-[0-9]* | grep -c .)"       # local ones untouched
    assert_eq ok "$(cut -f2 "$KIT_SERVER_DIR/logs/copy-backups.status")"
    [ -n "$(cut -f4 "$KIT_SERVER_DIR/logs/copy-backups.status")" ] || fail "no last copy time"
}

test_backup_all_backs_up_projects_then_config() {
    installed
    local out
    out=$("$B/backup-all" 2>&1) || fail "backup-all failed: $out"
    [ -n "$(newest)" ] || fail "no project backup"
    ls -d "$KIT_SERVER_DIR"/backups/config/config-* >/dev/null 2>&1 || fail "no config backup"
    assert_contains "$out" 'Everything backed up'
    [ ! -f "$KIT_SERVER_DIR/logs/health/.maintenance" ] || fail "left its maintenance window open"
}

test_weekly_jobs() {
    installed
    local p=$HOME/Library/LaunchAgents/io.github.andy327.mac-server-kit
    plutil -lint "$p.backup-all.plist" >/dev/null || fail "backup-all plist doesn't lint"
    assert_contains "$(cat "$p.backup-all.plist")" '<key>StartCalendarInterval</key>'
    assert_contains "$(tr -d ' \n' <"$p.backup-all.plist")" '<key>Weekday</key><integer>0</integer><key>Hour</key><integer>5</integer><key>Minute</key><integer>30</integer>'
    assert_not_contains "$(cat "$p.backup-all.plist")" 'RunAtLoad'
    [ ! -e "$p.update-all.plist" ] || fail "update-all is scheduled without UPDATE_SCHEDULE=weekly"
    printf 'UPDATE_SCHEDULE=weekly\n' >>"$KIT_SERVER_DIR/answers.conf"
    local out
    out=$(kit install 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Job update-all: weekly, Sunday 06:30'
    [ -e "$p.update-all.plist" ] || fail "update-all isn't scheduled"
}

test_install_pins_a_release_series_and_records_it() {
    installed
    assert_contains "$(grep '^homarr ' "$D/images.lock")" 'ghcr.io/homarr-labs/homarr:v2.11.1@sha256:'
    assert_contains "$(grep '^homarr ' "$D/images.lock")" ' v2.*'
    # A pin from before the hold (tracking latest) keeps its digest, and gets the series to follow
    sed -i '' "s|^homarr .*|homarr ghcr.io/homarr-labs/homarr:latest@sha256:$(printf '%064d' 7)|" "$D/images.lock"
    kit install >/dev/null 2>&1 || fail "install failed"
    assert_eq "homarr ghcr.io/homarr-labs/homarr:latest@sha256:$(printf '%064d' 7) v2.*" "$(grep '^homarr ' "$D/images.lock")"
}

test_newest_tag_takes_plain_releases_of_the_series() {
    load_libs
    assert_eq v2.11.1 "$(FAKE_REGISTRY_TAGS='latest v2.9.3 v2.11.1 v2.10.0 v2.12.0-beta.1 v2.11.1-alpine v3.0.0' newest_tag ghcr.io/x/y 'v2.*')"
    assert_eq 3.21.2 "$(FAKE_REGISTRY_TAGS='3.9 3.21.2 3.21 edge 4.0' newest_tag alpine '3.*')"
    assert_eq '' "$(FAKE_REGISTRY_TAGS='latest' newest_tag ghcr.io/x/y 'v2.*')"
}

# A project whose files are on a drive that isn't mounted: update and restore refuse before
# touching anything, and wait-volumes gives up after its wait (runtime.conf names the drive)
test_a_missing_drive_stops_update_and_restore() {
    installed
    assert_contains "$(cat "$KIT_SERVER_DIR/kit/runtime.conf")" "VOLUMES_media_stack=''"     # media in ~/Media
    sed -i '' "s|^VOLUMES_media_stack=.*|VOLUMES_media_stack='/Volumes/NoSuchDrive-kit-test'|" "$KIT_SERVER_DIR/kit/runtime.conf"
    : >"$FAKE_DOCKER_LOG"
    local out
    out=$("$B/update-project" media-stack 2>&1) && fail "update should refuse"
    assert_contains "$out" "/Volumes/NoSuchDrive-kit-test isn't mounted, and media-stack keeps its files there"
    assert_not_contains "$(cat "$FAKE_DOCKER_LOG")" 'compose stop'
    out=$(printf 'restore\n' | "$B/restore-project" media-stack 2>&1) && fail "restore should refuse"
    assert_contains "$out" "isn't mounted"
    out=$(WAIT_VOLUMES_MINUTES=0 KIT_WAIT_STEP=1 "$B/wait-volumes" 2>&1) || fail "wait-volumes failed: $out"
    assert_contains "$out" 'Gave up waiting for the drives of: media-stack'
    assert_not_contains "$(cat "$FAKE_DOCKER_LOG")" 'compose up'
}

# The drive is there but Docker never answers: it says what docker said, and starts nothing
test_wait_volumes_says_why_docker_did_not_answer() {
    installed
    sed -i '' "s|^VOLUMES_media_stack=.*|VOLUMES_media_stack='/Volumes/NoSuchDrive-kit-test'|" "$KIT_SERVER_DIR/kit/runtime.conf"
    : >"$FAKE_DOCKER_LOG"
    mkdir -p "$TEST_TMP/fakemount" && ln -s "$TEST_ROOT/tests/fake-host" "$TEST_TMP/fakemount/mount"
    export KIT_TEST_PATH=$TEST_TMP/fakemount FAKE_HOST_MOUNTS=/Volumes/NoSuchDrive-kit-test WAIT_VOLUMES_MINUTES=0
    local out
    out=$(FAKE_DOCKER_FAIL=info WAIT_DOCKER_SECONDS=0 KIT_WAIT_STEP=1 "$B/wait-volumes" 2>&1) || fail "wait-volumes failed: $out"
    assert_contains "$out" "Docker isn't answering (fake-docker: failing on purpose: info); nothing started: media-stack"
    assert_not_contains "$(cat "$FAKE_DOCKER_LOG")" 'compose up'
    out=$("$B/wait-volumes" 2>&1) || fail "wait-volumes failed: $out"
    assert_contains "$out" 'Started media-stack (its drive is mounted)'
}

test_wait_volumes_does_nothing_without_drives() {
    installed
    : >"$FAKE_DOCKER_LOG"
    local out
    out=$("$B/wait-volumes" 2>&1) || fail "wait-volumes failed: $out"
    assert_eq '' "$out"
    assert_eq '' "$(cat "$FAKE_DOCKER_LOG")"
    assert_contains "$(cat "$HOME/Library/LaunchAgents/io.github.andy327.mac-server-kit.wait-volumes.plist")" '<key>RunAtLoad</key>'
}
