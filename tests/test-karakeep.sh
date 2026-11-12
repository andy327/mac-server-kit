# shellcheck shell=bash
# The karakeep module: its own project, the admin the kit makes before anything serves it, sign-ups
# turned off with a restart, the check before Funnel, AI tags with ollama, its Homarr tile and
# widget, and backups. Also the when forms it needs (+module, a,b, @mark). Docker and Karakeep's
# API are fakes (fake-docker, fake-curl).

secrets_src() {     # a filled-in secrets file
    S=$TEST_TMP/secrets-src.conf
    printf '%s\n' "WIREGUARD_PRIVATE_KEY=\"$FAKE_WG\"" "TS_AUTHKEY=\"$FAKE_TSKEY\"" >"$S"
}
gen() { sed -n "s/^$1=\"\\(.*\\)\"\$/\\1/p" "$KIT_SERVER_DIR/kit/generated-secrets.conf"; }

install_with() {    # modules [answers-line...] [-- env...]: a first install
    local mods=$1 envs=()
    shift
    secrets_src
    printf 'MEDIA_SERVER=plex\nMODULES=%s\n' "$mods" >"$TEST_TMP/answers-src.conf"
    while [ $# -gt 0 ]; do
        [ "$1" = -- ] && { shift; envs=("$@"); break; }
        printf '%s\n' "$1" >>"$TEST_TMP/answers-src.conf"
        shift
    done
    OUT=$(env ${envs[@]+"${envs[@]}"} "$TEST_ROOT/kit" install --secrets "$S" --answers "$TEST_TMP/answers-src.conf" 2>&1) \
        || fail "install failed: $OUT"
    P=$KIT_SERVER_DIR/karakeep
    A=$KIT_SERVER_DIR/appdata/karakeep
}

test_karakeep_is_its_own_project_with_its_admin_made_by_the_kit() {
    install_with karakeep
    assert_contains "$OUT" 'Modules: core media-stack plex karakeep'
    local env; env=$(cat "$P/.env")
    assert_contains "$env" "KARAKEEP_NEXTAUTH_SECRET='$(gen KARAKEEP_NEXTAUTH_SECRET)'"
    assert_contains "$env" "KARAKEEP_MEILI_KEY='$(gen KARAKEEP_MEILI_KEY)'"
    assert_contains "$env" "TS_HOSTNAME_KARAKEEP='karakeep'"
    local lock k; lock=$(cat "$P/images.lock")
    for k in karakeep karakeep-chrome karakeep-meilisearch karakeep-tailscale; do
        printf '%s\n' "$lock" | grep -q "^$k " || fail "$k isn't pinned"
    done
    assert_contains "$lock" 'karakeep-meilisearch getmeili/meilisearch:v1.55@sha256:'
    # The kit made the first account (the admin), then turned sign-ups off with a restart
    assert_eq 1 "$(grep -c '^admin@karakeep.local|admin$' "$FAKE_CURL_DIR/karakeep-users")"
    assert_contains "$OUT" 'Karakeep: made its admin account (admin@karakeep.local)'
    [ -f "$A/kit-admin" ] || fail "no kit-admin"
    assert_contains "$(cat "$P/.env")" "KARAKEEP_DISABLE_SIGNUPS='true'"
    assert_contains "$OUT" 'Restarting karakeep with its new settings'
    assert_contains "$OUT" "Karakeep: its admin is the kit's, and sign-ups are off"
    [ -f "$A/kit-checked" ] || fail "no kit-checked"
    # Served on its node in the same run, tailnet-only by default
    local sj; sj=$(cat "$P/tailscale/karakeep/serve.json")
    assert_contains "$sj" '"Proxy": "http://karakeep:3000"'
    assert_not_contains "$sj" 'AllowFunnel'
    # No AI without ollama: not asked, nothing in .env
    assert_not_contains "$(cat "$KIT_SERVER_DIR/answers.conf")" 'KARAKEEP_AI'
    assert_not_contains "$(cat "$P/.env")" 'KARAKEEP_AI_KEY'
    # Homarr: the tile and the widget connection with the key the kit made
    assert_eq ak2_fakekarakeepkey_0123456789 "$(gen KARAKEEP_API_KEY)"
    assert_contains "$(cat "$FAKE_CURL_DIR/homarr-apps")" '"pingUrl":"http://karakeep-proxy:3040/api/health"'
    local integ; integ=$(cat "$FAKE_CURL_DIR/homarr-integrations")
    assert_contains "$integ" '"kind":"karakeep"'
    assert_contains "$integ" '"value":"ak2_fakekarakeepkey_0123456789"'
    ls "$KIT_SERVER_DIR"/media-stack/compose.d/*-karakeep.yml >/dev/null 2>&1 || fail "no karakeep-proxy in the media stack"
    assert_contains "$("$KIT_SERVER_DIR/bin/show-logins" karakeep)" "user: admin@karakeep.local   password: $(gen KARAKEEP_ADMIN_PASSWORD)"
}

test_a_second_install_makes_no_second_account_or_key() {
    install_with karakeep
    local out
    out=$(kit install 2>&1) || fail "second install failed: $out"
    assert_eq 1 "$(wc -l <"$FAKE_CURL_DIR/karakeep-users" | tr -d ' ')"
    assert_eq 1 "$(wc -l <"$FAKE_CURL_DIR/karakeep-keys" | tr -d ' ')"
    assert_not_contains "$out" 'Restarting karakeep'
    assert_not_contains "$out" 'Karakeep: made'
    assert_not_contains "$out" 'Karakeep: its admin is'
}

# The summary that ends an install: what was new, what restarted, the warnings again, the counts
test_the_install_ends_with_a_summary() {
    install_with karakeep
    local sum; sum=$(printf '%s\n' "$OUT" | sed -n '/╭ Done in/,$p')
    assert_contains "$sum" ' new · 1 restarted · '
    assert_contains "$sum" '✓ Sonarr: library folder /data/TV Shows'
    assert_contains "$sum" 'more (above)'
    assert_contains "$sum" 'Restarted with new settings: karakeep'
    assert_contains "$sum" 'apps to open · '
    [ "$(printf '%s\n' "$sum" | grep -c '✓')" -le 5 ] || fail "more than 5 new lines shown"
    # No colors when the output isn't a terminal
    assert_not_contains "$OUT" $'\033['
    local out
    out=$(kit install 2>&1) || fail "second install failed: $out"
    sum=$(printf '%s\n' "$out" | sed -n '/╭ Done in/,$p')
    assert_contains "$sum" '· nothing new · '
    assert_not_contains "$sum" 'Restarted'
}

test_the_summary_repeats_the_warnings() {
    install_with karakeep -- FAKE_KARAKEEP_OTHER_ADMIN=1
    local sum; sum=$(printf '%s\n' "$OUT" | sed -n '/╭ Done in/,$p')
    assert_contains "$sum" 'warning'
    assert_contains "$sum" "! Karakeep: admin@karakeep.local isn't its admin"
}

# Someone else made the first account: the kit's sign-up makes an ordinary one, so nothing is
# served, sign-ups stay as they were, and the warning says how to start over
test_someone_elses_first_account_keeps_karakeep_off_the_tailnet() {
    install_with karakeep -- FAKE_KARAKEEP_OTHER_ADMIN=1
    assert_contains "$OUT" "admin@karakeep.local isn't its admin"
    assert_contains "$OUT" 'delete ~/server/appdata/karakeep/data'
    [ ! -f "$A/kit-admin" ] || fail "kit-admin written for someone else's Karakeep"
    [ ! -f "$A/kit-checked" ] || fail "kit-checked written"
    assert_not_contains "$(cat "$P/tailscale/karakeep/serve.json")" 'karakeep:3000'
    assert_contains "$(cat "$P/.env")" "KARAKEEP_DISABLE_SIGNUPS='false'"
    [ -z "$(gen KARAKEEP_API_KEY)" ] || fail "made a key on someone else's Karakeep"
}

test_karakeep_funnel_waits_for_the_check() {
    install_with karakeep 'EXPOSE_karakeep=funnel'
    assert_contains "$(cat "$P/tailscale/karakeep/serve.json")" 'AllowFunnel'
    assert_contains "$OUT" 'Karakeep: public now (Funnel)'
}

test_ai_tags_follow_ollama() {
    install_with 'ollama karakeep'
    assert_contains "$(cat "$KIT_SERVER_DIR/answers.conf")" 'KARAKEEP_AI=on'
    local env model
    env=$(cat "$P/.env")
    model=$(sed -n 's/^OLLAMA_MODEL=//p' "$KIT_SERVER_DIR/answers.conf" | tr -d '"')
    assert_contains "$env" "KARAKEEP_AI_KEY='ollama'"
    assert_contains "$env" "KARAKEEP_AI_MODEL='$model'"
    assert_contains "$OUT" "✓ Karakeep: AI tags from $model"
    local again
    again=$(kit install 2>&1) || fail "second install failed: $again"
    assert_contains "$again" "Karakeep: AI tags from $model (already set)"
    assert_not_contains "$again" "✓ Karakeep: AI tags"
    # AI off again with no model, and with ollama disabled
    printf 'OLLAMA_MODEL=none\n' >>"$KIT_SERVER_DIR/answers.conf"
    kit install >/dev/null 2>&1 || fail "install with no model failed"
    assert_not_contains "$(cat "$P/.env")" 'KARAKEEP_AI_KEY'
    kit disable ollama >/dev/null 2>&1 || fail "disable ollama failed"
    kit install >/dev/null 2>&1 || fail "install without ollama failed"
    assert_not_contains "$(cat "$P/.env")" 'KARAKEEP_AI_MODEL'
}

test_backup_all_and_restore_cover_karakeep() {
    install_with karakeep
    local B=$KIT_SERVER_DIR/bin out
    mkdir -p "$A/data" "$A/tailscale-karakeep"
    echo bookmarks >"$A/data/db.db"
    echo state >"$A/tailscale-karakeep/tailscaled.state"
    sed -i '' "s/^AFTER_START_media_stack=.*/AFTER_START_media_stack=''/" "$KIT_SERVER_DIR/kit/runtime.conf"
    out=$("$B/backup-karakeep" 2>&1) || fail "backup-karakeep failed: $out"
    assert_not_contains "$out" 'nothing at'
    echo changed >"$A/data/db.db"
    out=$(RESTORE_YES=1 "$B/restore-karakeep" 2>&1) || fail "restore-karakeep failed: $out"
    assert_eq bookmarks "$(cat "$A/data/db.db")"
    [ -x "$B/update-karakeep" ] || fail "no update-karakeep"
    assert_contains "$(cat "$KIT_SERVER_DIR/kit/runtime.conf")" "BACKUP_PROJECTS='media-stack karakeep'"
}

# ---------------------------------------------------------------- the when forms

test_when_module_all_of_and_marks() {
    load_libs
    config_init
    printf 'A=1\nB=2\n' >>"$ANSWERS"
    # shellcheck disable=SC2034  # when_ok reads it
    ENABLED='core ollama'
    when_ok '+ollama' || fail "+ollama with ollama enabled"
    when_ok '+romm' && fail "+romm without romm"
    when_ok 'A=1,B=2' || fail "both hold"
    when_ok 'A=1,B=3' && fail "one doesn't hold"
    when_ok 'A=1,+ollama,B!=3' || fail "three hold"
    WHEN_PROJECT=''
    when_ok '@kit-admin' && fail "a mark with no project"
    # shellcheck disable=SC2034  # when_ok reads it
    WHEN_PROJECT=p
    mkdir -p "$(project_appdata p)"
    when_ok '@kit-admin' && fail "a mark that isn't there"
    when_ok '!@kit-admin' || fail "!mark when it isn't there"
    touch "$(project_appdata p)/kit-admin"
    when_ok '@kit-admin' || fail "a mark that's there"
    when_ok '!@kit-admin' && fail "!mark when it's there"
    return 0
}
