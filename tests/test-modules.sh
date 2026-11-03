# shellcheck shell=bash
# Module discovery and dependency resolution (lib/modules.sh)

setup_mods() { fake_modules; }
discover() { load_libs; modules_discover; }

test_discovers_repo_and_local_modules() {
    setup_mods
    mkmod core KIND=base
    mkmod romm
    MKMOD_ROOT=$KIT_SERVER_DIR/local-modules mkmod landing
    discover
    assert_eq 'core romm landing' "$MODULES_ALL"
    assert_eq "$KIT_SERVER_DIR/local-modules/landing" "$(mod_dir landing)"
    assert_eq core "$(modules_base)"
}

test_local_module_cannot_shadow_repo_module() {
    setup_mods
    mkmod romm
    MKMOD_ROOT=$KIT_SERVER_DIR/local-modules mkmod romm
    load_libs
    assert_fails modules_discover
}

test_local_module_cannot_be_base() {
    setup_mods
    mkmod core KIND=base
    MKMOD_ROOT=$KIT_SERVER_DIR/local-modules mkmod mine KIND=base
    load_libs
    assert_fails modules_discover
}

test_bad_kind_and_bad_name_rejected() {
    setup_mods
    mkmod odd KIND=sometimes
    load_libs
    assert_fails modules_discover
    rm -rf "$KIT_MODULES_DIR/odd"
    mkmod Bad_Name
    assert_fails modules_discover
}

test_folders_without_module_conf_ignored() {
    setup_mods
    mkmod core KIND=base
    mkdir -p "$KIT_MODULES_DIR/scratch"
    discover
    assert_eq core "$MODULES_ALL"
}

test_resolve_orders_dependencies() {
    setup_mods
    mkmod open-webui 'REQUIRES="ollama"'
    mkmod ollama
    mkmod core KIND=base
    discover
    assert_eq 'core ollama open-webui' "$(modules_resolve core open-webui ollama)"
}

test_resolve_requires_one_of() {
    setup_mods
    mkmod plex; mkmod jellyfin
    mkmod tracearr 'REQUIRES_ONE_OF="plex jellyfin"'
    discover
    assert_eq 'jellyfin tracearr' "$(modules_resolve tracearr jellyfin 2>/dev/null)"
    assert_fails modules_resolve tracearr
}

test_resolve_reports_every_problem() {
    setup_mods
    mkmod a 'REQUIRES="b"'
    mkmod c 'REQUIRES="d"'
    discover
    local out
    out=$(modules_resolve a c nope 2>&1) && fail "should fail"
    assert_contains "$out" 'a requires b'
    assert_contains "$out" 'c requires d'
    assert_contains "$out" 'unknown module: nope'
}

test_resolve_detects_cycles() {
    setup_mods
    mkmod a 'REQUIRES="b"'
    mkmod b 'REQUIRES="a"'
    discover
    local out
    out=$(modules_resolve a b 2>&1) && fail "should fail"
    assert_contains "$out" 'cycle'
}

test_requested_from_answers() {
    setup_mods
    mkmod core KIND=base
    mkmod plex; mkmod jellyfin; mkmod romm
    discover
    config_init
    printf 'MEDIA_SERVER=both\nMODULES=romm plex\n' >>"$ANSWERS"
    assert_eq 'core plex jellyfin romm' "$(modules_requested)"
}

test_enabled_file_round_trip() {
    setup_mods
    mkmod core KIND=base
    discover
    config_init
    write_enabled core plex
    assert_eq 'core plex' "$(read_enabled)"
}

test_backup_order_is_stable() {
    setup_mods
    mkmod a BACKUP_ORDER=30; mkmod b BACKUP_ORDER=10; mkmod c; mkmod d BACKUP_ORDER=30
    discover
    assert_eq 'b a d c' "$(by_backup_order a b c d)"
}

test_repo_modules_are_valid() {
    load_libs
    modules_discover
    local base all
    base=$(modules_base)
    assert_eq 'core glances health media-stack' "$base"
    all=$(modules_resolve $MODULES_ALL) || fail "repo modules don't resolve together"
    for m in $MODULES_ALL; do in_list "$m" "$all" || fail "$m missing from the resolved list"; done
}

test_discover_twice_is_fine() {
    setup_mods
    mkmod core KIND=base
    discover
    modules_discover
    assert_eq core "$MODULES_ALL"
}
