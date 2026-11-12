# shellcheck shell=bash
# Validators, prompts, generated secrets and holds (lib/config.sh)

WG=$FAKE_WG

test_validators_accept() {
    load_libs
    assert_ok validate choice:plex,jellyfin,both both
    assert_ok validate dir /Volumes/Drive/Media
    assert_ok validate nodename media-2
    assert_ok validate tz America/New_York
    assert_ok validate tskey "$FAKE_TSKEY"
    assert_ok validate wgkey "$WG"
    assert_ok validate cidr 10.2.0.2/32
    assert_ok validate hcurl "$FAKE_HC_URL"
    assert_ok validate hcurl https://hc-ping.com/AbCdEfGhIjKlMnOpQrStUv/my-server
    assert_ok validate hcurl https://hc.example.org/ping/0f8a1d2c-1111-4a4a-9b9b-123456789abc
    assert_ok validate ntfy my_topic-1
    assert_ok validate ntfy https://ntfy.sh/my_topic
    assert_ok validate homarrkey abcdefghij.klmnopqrstuvwxyz
    assert_ok validate subnet24 172.31.97.0/24
    assert_ok validate countries "United States,Canada"
    assert_ok validate '?wgkey' ''
}

test_validators_reject() {
    load_libs
    assert_fails validate choice:plex,jellyfin pl
    assert_fails validate dir relative/path
    assert_fails validate dir /
    assert_fails validate dir /a/../b
    assert_ok validate volume /Volumes/Backup
    assert_ok validate volume /Volumes/Backup/server
    assert_ok validate '?volume' ''
    assert_fails validate volume ~/round2-drive/kit-backups
    assert_fails validate volume /Volumes
    assert_fails validate volume /Volumes/
    assert_fails validate volume /Volumes/a/../b
    assert_fails validate nodename Media
    assert_fails validate nodename -media
    assert_fails validate tz Not/AZone
    assert_fails validate tz ../../etc/passwd
    assert_fails validate tskey tskey-client-abc
    assert_fails validate wgkey short=
    assert_fails validate cidr 10.2.0.2
    assert_fails validate hcurl https://example.com/0f8a1d2c
    assert_fails validate ntfy 'has space'
    assert_fails validate homarrkey 'no-dot-in-this-key-at-all'
    assert_fails validate subnet24 172.31.97.1/24
    assert_fails validate subnet24 172.31.300.0/24
    assert_fails validate subnet24 10.0.0.0/16
    assert_fails validate countries "Côte d'Ivoire"
    assert_fails validate wgkey ''
}

test_validator_message() {
    load_libs
    validate choice:a,b c || true
    assert_eq 'must be one of: a, b' "$VALID_MSG"
}

# shellcheck disable=SC2088  # literal ~ is the input under test
test_normalize_dir() {
    load_libs
    assert_eq "$HOME/Media" "$(normalize_value dir '~/Media/')"
    assert_eq "$HOME" "$(normalize_value '?dir' '~')"
    assert_eq '/Volumes/X' "$(normalize_value dir '/Volumes/X//')"
    assert_eq 'abc/' "$(normalize_value nodename 'abc/')"
}

setup_prompt_module() {     # one module "m" with the given prompts lines
    fake_modules
    mkmod m KIND=base
    printf '%s\n' "$@" >"$KIT_MODULES_DIR/m/prompts"
    load_libs
    config_init
    modules_discover
}

test_prompts_noninteractive_writes_defaults_skips_optional() {
    setup_prompt_module \
        'answers|ROOT|~/Media|dir|Where?|' \
        'answers|OPT||?dir|Optional?|' \
        'answers|SILENT|on|choice:on,off||' \
        'secrets|KEY||wgkey|Key?|'
    run_prompts m
    assert_eq "$HOME/Media" "$(kv_get "$ANSWERS" ROOT)"
    assert_fails kv_has "$ANSWERS" OPT
    assert_fails kv_has "$ANSWERS" SILENT
    assert_eq on "$(answer SILENT)"
    assert_eq 'KEY (secrets.conf)' "$PROMPTS_MISSING"
}

test_prompts_interactive_reprompts_until_valid() {
    setup_prompt_module \
        'answers|ROLE|server|choice:server,laptop|Role?|' \
        'answers|ROOT|~/Media|dir|Where?|' \
        'secrets|KEY||wgkey|Key?|' \
        'secrets|HC||?hcurl|HC?|'
    export KIT_INTERACTIVE=1
    run_prompts m 2>/dev/null <<EOF
desktop
laptop

bad-key
$WG

EOF
    assert_eq laptop "$(kv_get "$ANSWERS" ROLE)"
    assert_eq "$HOME/Media" "$(kv_get "$ANSWERS" ROOT)"
    assert_eq "$WG" "$(kv_get "$SECRETS" KEY)"
    assert_contains "$(cat "$SECRETS")" "KEY=\"$WG\""
    assert_eq '' "$(kv_get "$SECRETS" HC)"
}

# A choices file: a numbered list under the question, the default's number marked as suggested;
# a number picks from it, anything else is taken as typed
test_prompts_with_a_list_to_pick_from() {
    setup_prompt_module 'answers|PICK|b|any|Which?|' 'answers|PICK2|b|any|Which?|' 'answers|PICK3|b|any|Which?|'
    printf '%s\n' 'PICK|a|the first' 'PICK|b|the second' 'PICK|c|the third' \
        'PICK2|a|x' 'PICK2|b|y' 'PICK3|a|x' 'PICK3|b|y' >"$KIT_MODULES_DIR/m/choices"
    export KIT_INTERACTIVE=1
    local err
    err=$(run_prompts m 2>&1 >/dev/null <<EOF
3

other:1b
EOF
)
    assert_eq c "$(kv_get "$ANSWERS" PICK)"
    assert_eq b "$(kv_get "$ANSWERS" PICK2)"          # Enter: the suggestion
    assert_eq other:1b "$(kv_get "$ANSWERS" PICK3)"   # not on the list
    assert_contains "$err" ' 2  b             the second (suggested for this Mac)'
    assert_contains "$err" 'Which? [2]:'
}

test_prompts_skip_keys_already_set() {
    setup_prompt_module 'answers|ROLE|server|choice:server,laptop|Role?|'
    printf 'ROLE=laptop\n' >>"$ANSWERS"
    export KIT_INTERACTIVE=1
    run_prompts m </dev/null 2>/dev/null
    assert_eq laptop "$(kv_get "$ANSWERS" ROLE)"
    assert_eq 1 "$(grep -c '^ROLE=' "$ANSWERS")"
}

test_prompts_when_condition() {
    setup_prompt_module \
        'answers|VPN|protonvpn|choice:protonvpn,nordvpn|VPN?|' \
        'answers|PROTON_ONLY|x|any|P?|VPN=protonvpn' \
        'answers|NORD_ONLY|y|any|N?|VPN=nordvpn' \
        'answers|NOT_NORD|z|any|NN?|VPN!=nordvpn'
    run_prompts m
    assert_eq x "$(kv_get "$ANSWERS" PROTON_ONLY)"
    assert_fails kv_has "$ANSWERS" NORD_ONLY
    assert_eq z "$(kv_get "$ANSWERS" NOT_NORD)"
}

test_generated_secrets_created_once() {
    setup_prompt_module 'gen|PW|alnum24||||' 'gen|HEX|hex16||||'
    run_prompts m
    local pw hex
    pw=$(secret PW); hex=$(secret HEX)
    [[ $pw =~ ^[A-Za-z0-9]{24}$ ]] || fail "bad alnum24: $pw"
    [[ $hex =~ ^[0-9a-f]{32}$ ]] || fail "bad hex16: $hex"
    run_prompts m
    assert_eq "$pw" "$(secret PW)"
    assert_eq 600 "$(stat -f %Lp "$GEN_SECRETS")"
}

test_user_secret_wins_over_generation() {
    setup_prompt_module 'gen|PW|alnum24||||'
    printf 'PW="mine"\n' >>"$SECRETS"
    run_prompts m
    assert_eq mine "$(secret PW)"
    assert_fails kv_has "$GEN_SECRETS" PW
}

test_check_values_reports_without_printing_secrets() {
    setup_prompt_module 'secrets|KEY||wgkey|Key?|' 'answers|ROLE|server|choice:server,laptop|Role?|'
    printf 'KEY="not-a-real-key-SECRET"\n' >>"$SECRETS"
    printf 'ROLE=desk\n' >>"$ANSWERS"
    local out
    out=$(check_values m 2>&1) && fail "check_values should fail"
    assert_contains "$out" 'KEY in'
    assert_contains "$out" 'ROLE in'
    assert_not_contains "$out" 'SECRET'
}

test_config_init_permissions() {
    load_libs
    config_init
    assert_eq 600 "$(stat -f %Lp "$SECRETS")"
    assert_eq 700 "$(stat -f %Lp "$KIT_STATE")"
}

test_import_secrets_file() {
    load_libs
    local src=$TEST_TMP/mine.conf
    printf 'TS_AUTHKEY="tskey-auth-a-b"\n' >"$src"
    import_secrets_file "$src"
    assert_eq 600 "$(stat -f %Lp "$SECRETS")"     # the draft is private too
    import_commit >/dev/null
    assert_eq 600 "$(stat -f %Lp "$SECRETS")"
    assert_ok import_secrets_file "$src"            # identical: fine
    printf 'X=1\n' >>"$src"
    assert_fails import_secrets_file "$src"         # differs: never overwritten
    assert_fails grep -q '^X=' "$SECRETS"
    local out
    out=$( (import_secrets_file "$src") 2>&1)
    assert_contains "$out" "Install reads $(tilde "$SECRETS")"
    assert_contains "$out" 'without --secrets'
}

test_holds_merge_and_lift() {
    fake_modules
    mkmod a KIND=base
    printf '%s\n' '# comment' 'meilisearch v1.41 2026-09 index format change' 'redis 8-alpine 2026-10 pin major' \
        >"$KIT_MODULES_DIR/a/holds"
    load_libs
    config_init
    modules_discover
    printf '%s\n' 'HOLD_meilisearch=v1.40 # bug in 1.41, 2026-10' 'HOLD_redis=none' >>"$ANSWERS"
    local out
    out=$(holds_list a)
    assert_contains "$out" 'meilisearch|v1.40|2026-10|bug in 1.41|answers'
    assert_contains "$out" 'redis|none|||answers'
    assert_eq 0 "$(printf '%s\n' "$out" | grep -c '|a$')" "module holds should be overridden"
    assert_eq 2 "$(printf '%s\n' "$out" | grep -c .)"
}

test_months_since() {
    load_libs
    assert_eq 0 "$(months_since "$(date +%Y-%m)")"
    assert_eq 12 "$(months_since "$(( $(date +%Y) - 1 ))-$(date +%m)")"
    assert_eq '' "$(months_since 2026-1)"
}

test_prompts_stop_when_input_ends() {
    setup_prompt_module 'secrets|KEY||wgkey|Key?|'
    export KIT_INTERACTIVE=1
    local out
    out=$(printf 'bad\n' | run_prompts m 2>&1) && fail "should stop at end of input"
    assert_contains "$out" 'input ended before KEY'
}

test_answers_tilde_paths_are_expanded() {
    setup_prompt_module 'answers|ROOT|~/Media|dir|Where?|'
    printf 'ROOT=~/Elsewhere/\n' >>"$ANSWERS"
    assert_eq "$HOME/Elsewhere" "$(answer ROOT)"
    assert_ok check_values m
}

test_answer_overrides_win() {
    setup_prompt_module 'answers|VPN|protonvpn|choice:protonvpn,nordvpn|VPN?|'
    printf 'VPN=protonvpn\n' >>"$ANSWERS"
    override_answer VPN nordvpn
    assert_eq nordvpn "$(answer VPN)"
    override_answer VPN protonvpn
    assert_eq protonvpn "$(answer VPN)"
}

test_required_key_left_empty_is_asked_again() {
    setup_prompt_module 'secrets|KEY||wgkey|Key?|' 'secrets|OPT||?hcurl|HC?|'
    printf 'KEY=""\nOPT=""\n' >>"$SECRETS"
    export KIT_INTERACTIVE=1
    printf '%s\n' "$WG" | run_prompts m 2>/dev/null
    assert_eq "$WG" "$(kv_get "$SECRETS" KEY)"
    assert_eq 1 "$(grep -c '^KEY=""$' "$SECRETS")" "the empty line stays untouched"
    assert_eq '' "$(kv_get "$SECRETS" OPT)"
}

test_required_key_left_empty_noninteractive_is_missing() {
    setup_prompt_module 'secrets|KEY||wgkey|Key?|'
    printf 'KEY=""\n' >>"$SECRETS"
    run_prompts m
    assert_eq 'KEY (secrets.conf)' "$PROMPTS_MISSING"
}

test_help_field_uses_when() {
    setup_prompt_module 'answers|VPN|protonvpn|choice:protonvpn,nordvpn|VPN?|'
    printf '%s\n' 'K|proton about|proton get||VPN=protonvpn' 'K|nord about|nord get||VPN=nordvpn' 'L|l about||after|' \
        >"$KIT_MODULES_DIR/m/help"
    assert_eq 'proton get' "$(help_field m K 3)"
    override_answer VPN nordvpn
    assert_eq 'nord about' "$(help_field m K 2)"
    assert_eq after "$(help_field m L 4)"
    assert_fails help_field m NOPE 2
}

test_prompt_shows_help() {
    setup_prompt_module 'answers|ROLE|server|choice:server,laptop|Role?|'
    printf 'ROLE|Explains the role.|Where to look.||\n' >"$KIT_MODULES_DIR/m/help"
    export KIT_INTERACTIVE=1
    local out
    out=$(printf '\n' | run_prompts m 2>&1)
    assert_contains "$out" 'Explains the role.'
    assert_contains "$out" 'Where to look.'
}

test_import_answers_file() {
    load_libs
    local src=$TEST_TMP/a.conf
    printf 'MEDIA_SERVER=jellyfin\n' >"$src"
    import_answers_file "$src"
    assert_eq jellyfin "$(kv_get "$ANSWERS" MEDIA_SERVER)"     # the run reads the draft
    [ ! -e "$KIT_SERVER_DIR/answers.conf" ] || fail "copied before the values passed"
    assert_eq "$src" "$(shown "$ANSWERS")"
    import_commit >/dev/null
    assert_eq jellyfin "$(kv_get "$KIT_SERVER_DIR/answers.conf" MEDIA_SERVER)"
    assert_eq "$KIT_SERVER_DIR/answers.conf" "$ANSWERS"
    printf 'X=1\n' >>"$src"
    assert_fails import_answers_file "$src"                 # differs from the one in place now
}

test_apikey_secrets_never_look_like_numbers() {
    load_libs
    local k
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        k=$(gen_secret apikey)
        [[ $k =~ ^[a-f][0-9a-f]{31}$ ]] || fail "bad apikey: $k"
    done
}

test_when_key_is_set() {
    setup_prompt_module 'answers|A|alpha|any||' 'answers|EMPTY||?any||' 'secrets|S||?any|S?|'
    assert_ok when_ok 'A?'                  # a default counts
    assert_fails when_ok 'EMPTY?'
    assert_fails when_ok 'S?'
    printf 'S="set"\n' >>"$SECRETS"
    assert_ok when_ok 'S?'
}
