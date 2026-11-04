# shellcheck shell=bash
# ./kit prepare: the ready list and the two templates (repo modules)

WG=$FAKE_WG
TSKEY=$FAKE_TSKEY

test_prepare_lists_base_needs_without_touching_server_dir() {
    local out
    out=$(kit prepare 2>&1) || fail "prepare failed: $out"
    assert_contains "$out" 'WIREGUARD_PRIVATE_KEY'
    assert_contains "$out" 'account.protonvpn.com'
    assert_contains "$out" 'A Plex account'
    assert_contains "$out" 'After the first install'
    assert_contains "$out" 'HOMARR_API_KEY'
    assert_not_contains "$out" 'Jellyfin: open'
    [ ! -e "$KIT_SERVER_DIR" ] || fail "prepare created $KIT_SERVER_DIR"
}

test_prepare_follows_choices() {
    local out
    out=$(kit prepare --vpn nordvpn --media-server jellyfin 2>&1) || fail "prepare failed: $out"
    assert_contains "$out" 'nordlynx_private_key'
    assert_not_contains "$out" 'account.protonvpn.com'
    assert_contains "$out" 'Jellyfin: open'
    assert_not_contains "$out" 'A Plex account'
    assert_contains "$out" 'VPN: nordvpn'
}

test_prepare_rejects_bad_input() {
    assert_fails kit prepare --vpn mullvad
    assert_fails kit prepare nonsense
    assert_fails kit prepare media-stack
    assert_fails kit prepare open-webui          # needs ollama
    assert_ok kit prepare ollama open-webui
}

test_every_asked_prompt_has_help() {
    load_libs
    modules_discover
    local m pf file key missing=''
    for m in $MODULES_ALL; do
        pf="$(mod_dir "$m")/prompts"
        [ -f "$pf" ] || continue
        while IFS='|' read -r file key _ <&3; do
            case "$file" in answers|secrets) ;; *) continue ;; esac
            grep -q "^$key|" "$(mod_dir "$m")/help" 2>/dev/null || missing="$missing $m:$key"
        done 3<"$pf"
    done
    [ -z "$missing" ] || fail "no help for:$missing"
}

test_secrets_template() {
    local f=$TEST_TMP/s.conf
    kit prepare --secrets-template "$f" >/dev/null 2>&1 || fail "template failed"
    assert_eq 600 "$(stat -f %Lp "$f")"
    local t; t=$(cat "$f")
    assert_contains "$t" 'WIREGUARD_PRIVATE_KEY=""'
    assert_contains "$t" 'TS_AUTHKEY=""'
    assert_contains "$t" '#HEALTHCHECK_URL=""'
    assert_contains "$t" '#HOMARR_API_KEY=""'
    assert_contains "$t" 'Needed after the first install'
    assert_not_contains "$t" 'SONARR_API_KEY'
    assert_fails kit prepare --secrets-template "$f"     # never overwrites
}

test_answers_template_has_defaults_and_choices() {
    local f=$TEST_TMP/a.conf
    kit prepare --vpn nordvpn --answers-template "$f" romm >/dev/null 2>&1 || fail "template failed"
    local t; t=$(cat "$f")
    assert_contains "$t" 'MEDIA_ROOT=~/Media'
    assert_contains "$t" 'VPN_PROVIDER=nordvpn'
    assert_contains "$t" 'MODULES=romm'
    assert_contains "$t" '#UPDATE_SCHEDULE=off'
}

test_install_from_templates_asks_nothing() {
    local a=$TEST_TMP/a.conf s=$TEST_TMP/s.conf
    kit prepare --answers-template "$a" --secrets-template "$s" >/dev/null 2>&1 || fail "templates failed"
    sed -i '' -e "s|^WIREGUARD_PRIVATE_KEY=\"\"|WIREGUARD_PRIVATE_KEY=\"$WG\"|" \
        -e "s|^TS_AUTHKEY=\"\"|TS_AUTHKEY=\"$TSKEY\"|" -e 's|^#HEALTHCHECK_URL=""|HEALTHCHECK_URL=""|' \
        -e 's|^#NTFY_TOPIC=""|NTFY_TOPIC=""|' -e 's|^#HOMARR_API_KEY=""|HOMARR_API_KEY=""|' "$s"
    export KIT_INTERACTIVE=1                    # any question would hit end of input and fail
    local out
    out=$(kit install --answers "$a" --secrets "$s" </dev/null 2>&1) || fail "install asked or failed: $out"
    assert_contains "$out" 'Modules: core media-stack plex glances health'
    assert_eq "$HOME/Media" "$(cd "$TEST_ROOT" && KIT_DIR=$TEST_ROOT /bin/bash -c '. lib/common.sh; . lib/config.sh; . lib/modules.sh; modules_discover; answer MEDIA_ROOT')"
}

test_install_from_unfilled_secrets_template_reports_missing() {
    local s=$TEST_TMP/s.conf out
    kit prepare --secrets-template "$s" >/dev/null 2>&1 || fail "template failed"
    out=$(kit install --secrets "$s" 2>&1) && fail "install should fail"
    assert_contains "$out" 'WIREGUARD_PRIVATE_KEY (secrets.conf)'
}
