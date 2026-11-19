# shellcheck shell=bash
# Sonarr's and Radarr's quality settings (modules/media-stack/hooks/arr-quality.sh): seeded by
# the wire hook into apps with stock settings, and left alone after. Against tests/fake-curl, whose apps start with two stock profiles (Any, Ultra-HD), three quality sizes and
# a profile template of four qualities.

secrets_src() {     # a filled-in secrets file
    S=$TEST_TMP/secrets-src.conf
    printf '%s\n' "WIREGUARD_PRIVATE_KEY=\"$FAKE_WG\"" "TS_AUTHKEY=\"$FAKE_TSKEY\"" >"$S"
}
stored() { cat "$FAKE_CURL_DIR/127.0.0.1_$1" 2>/dev/null; }    # port_api_... -> what the fake app holds
profile() { stored "$1_api_v3_qualityprofile" | grep "\"name\":\"$2\""; }
mark() { cat "$KIT_SERVER_DIR/appdata/media-stack/$1/kit-quality" 2>/dev/null; }
calls() { grep -c "^$1 .*$2" "$FAKE_CURL_LOG"; }

# Settings of the user's own before the install: a custom format in Sonarr, a movie in Radarr's
# library
own_settings() {
    mkdir -p "$FAKE_CURL_DIR"
    echo '{"id":1,"name":"Mine","includeCustomFormatWhenRenaming":false,"specifications":[]}' >"$FAKE_CURL_DIR/127.0.0.1_8989_api_v3_customformat"
    echo '{"id":1,"title":"A Movie","path":"/data/Movies/A Movie"}' >"$FAKE_CURL_DIR/127.0.0.1_7878_api_v3_movie"
}

test_defaults_name_no_machine_and_parse() {
    load_libs
    # shellcheck source=../modules/media-stack/hooks/arr-quality.sh
    . "$TEST_ROOT/modules/media-stack/hooks/arr-quality.sh"
    local app n
    for app in sonarr radarr; do
        n=$(arrq_data "$app" | osascript -l JavaScript -e 'function run(a) { var d = JSON.parse(a[0]);
            return d.qualityProfiles.length + " " + d.qualityDefinitions.length; }' "$(arrq_data "$app")" 2>&1)
        case "$n" in [1-9]*' '[1-9]*) ;; *) fail "$app's defaults don't parse: $n" ;; esac
    done
    assert_contains "$(arrq_data sonarr)" '"name":"Anime"'
    assert_contains "$(arrq_data radarr)" '"removeProfiles":["Ultra-HD"]'
    assert_fails arrq_data lidarr
    # Anime's SD tier, between SDTV and Bluray-480p, cutoff 1080p; Anime (No Upgrades) the same
    # but for upgrades
    n=$(osascript -l JavaScript -e 'function run(a) { var d = JSON.parse(a[0]), p = {};
        d.qualityProfiles.forEach(function (x) { p[x.name] = x; });
        var A = p["Anime"], N = p["Anime (No Upgrades)"];
        var names = A.items.map(function (i) { return i.name || i.quality.name; });
        var sd = A.items.filter(function (i) { return i.name === "SD (DVD/WEB 480p)"; })[0];
        var c = JSON.parse(JSON.stringify(N)); c.name = A.name; c.upgradeAllowed = A.upgradeAllowed;
        return [names.slice(names.indexOf("SDTV"), names.indexOf("SDTV") + 3).join(","),
            sd.items.map(function (i) { return i.quality.name; }).join(","), A.cutoff, A.upgradeAllowed,
            N.upgradeAllowed, JSON.stringify(c) === JSON.stringify(A)].join(" | "); }' "$(arrq_data sonarr)" 2>&1)
    assert_eq 'SDTV,SD (DVD/WEB 480p),Bluray-480p | DVD,WEBRip-480p,WEBDL-480p | 1002 | true | false | true' "$n"
}

# Profiles go in by name: an existing one is updated in place, a missing one added, none twice
test_profiles_update_by_name() {
    load_libs
    # shellcheck source=../modules/media-stack/hooks/arr-quality.sh
    . "$TEST_ROOT/modules/media-stack/hooks/arr-quality.sh"
    local schema qp out
    schema='{"items":['
    for q in 0:Unknown 1:SDTV 2:DVD 12:WEBRip-480p 8:WEBDL-480p 13:Bluray-480p 22:Bluray-576p 4:HDTV-720p 9:HDTV-1080p 10:Raw-HD 14:WEBRip-720p 5:WEBDL-720p 6:Bluray-720p 15:WEBRip-1080p 3:WEBDL-1080p 7:Bluray-1080p 20:Bluray-1080p\ Remux 16:HDTV-2160p 17:WEBRip-2160p 18:WEBDL-2160p 19:Bluray-2160p 21:Bluray-2160p\ Remux; do
        schema="$schema{\"quality\":{\"id\":${q%%:*},\"name\":\"${q#*:}\"},\"items\":[],\"allowed\":false},"
    done
    schema="${schema%,}]}"
    ARRQ_IN=$TEST_TMP/arrq-in.json
    arrq_in() { { printf '{"data":'; arrq_data sonarr; printf ',"cf":[],"qp":%s,"schema":%s,"qd":[],"rp":[]}' "$1" "$schema"; } >"$ARRQ_IN"; }
    # An older Anime (DVD on its own, a WEB 480p group) and no Anime (No Upgrades)
    arrq_in '[{"id":7,"name":"Anime","upgradeAllowed":true,"cutoff":1002,"items":[],"formatItems":[]}]'
    out=$(arrq_changes rest | cut -d "$ARRQ_SEP" -f 1-3 | grep 'Anime')
    assert_eq "PUT${ARRQ_SEP}qualityprofile/7${ARRQ_SEP}quality profile Anime (updated)
POST${ARRQ_SEP}qualityprofile${ARRQ_SEP}quality profile Anime (No Upgrades)" "$out"
    # Both as the defaults have them: nothing to do
    qp=$(arrq_changes rest | cut -d "$ARRQ_SEP" -f 4 | grep '"name":"Anime' | osascript -l JavaScript -e 'function run(a) {
        return JSON.stringify(a[0].split("\n").map(function (l, i) { var p = JSON.parse(l); p.id = 7 + i; return p; })); }' "$(cat)" 2>&1)
    arrq_in "$qp"
    assert_eq '' "$(arrq_changes rest | grep 'Anime')"
    ARRQ_IN=''
}

test_first_install_seeds_the_defaults() {
    secrets_src
    local out
    out=$(kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Sonarr: custom format Season Pack'
    assert_contains "$out" 'Sonarr: quality profile Anime'
    assert_contains "$out" 'Sonarr: quality profile Anime (No Upgrades)'
    assert_contains "$out" 'Sonarr: quality profile TV Animation'
    assert_contains "$out" 'Sonarr: quality profile TV Live Action'
    assert_contains "$out" 'Radarr: quality profile Ultra-HD removed'
    assert_contains "$out" 'Radarr: custom format x265 / HEVC'
    assert_eq 8 "$(stored 8989_api_v3_customformat | grep -c .)"
    assert_not_contains "$(stored 8989_api_v3_customformat)" 'Oversize'
    # Any: upgrades, scores by the formats' ids here, and only the qualities this app knows, with
    # 1080p WEB and Bluray as one tier
    local any; any=$(profile 8989 Any)
    assert_contains "$any" '"upgradeAllowed":true'
    assert_contains "$any" '"name":"Season Pack","score":10'
    assert_contains "$any" '"name":"1080p","allowed":true,"items":[{"quality":{"id":3,"name":"WEBDL-1080p"}'
    assert_not_contains "$any" 'Bluray-2160p'
    assert_contains "$(profile 8989 Ultra-HD)" '"name":"Ultra-HD"'      # stock in Sonarr's defaults
    assert_eq '' "$(profile 7878 Ultra-HD)"
    # Radarr: x265 preferred (+25) in every profile, x264 still allowed
    assert_eq 1 "$(stored 7878_api_v3_customformat | grep -c .)"
    assert_contains "$(stored 7878_api_v3_customformat)" '"name":"x265","implementation":"ReleaseTitleSpecification","negate":false,"required":true'
    local p
    for p in Any SD HD-720p HD-1080p 'HD - 720p/1080p'; do
        assert_contains "$(profile 7878 "$p")" '"name":"x265 / HEVC","score":25'
        assert_contains "$(profile 7878 "$p")" '"minFormatScore":0,"cutoffFormatScore":0'
    done
    assert_contains "$(stored 7878_api_v3_qualitydefinition)" '"title":"WEBDL-1080p","minSize":10,"maxSize":58,"preferredSize":28'
    assert_contains "$(stored 7878_api_v3_qualitydefinition)" '"title":"Bluray-1080p","minSize":10,"maxSize":58,"preferredSize":28'
    assert_contains "$(stored 7878_api_v3_qualitydefinition)" '"title":"WEBDL-480p","minSize":2,"maxSize":20,"preferredSize":8'
    assert_contains "$(stored 8989_api_v3_qualitydefinition)" '"title":"Bluray-1080p","minSize":4,"maxSize":129.5,"preferredSize":95'
    assert_eq '' "$(stored 8989_api_v3_releaseprofile)"
    assert_contains "$(mark sonarr)" 'seeded '
    assert_contains "$(mark radarr)" 'seeded '
}

test_second_install_leaves_them_alone() {
    secrets_src
    kit install --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    # The user changes Any afterwards
    sed -i '' 's/"name":"Any","upgradeAllowed":true/"name":"Any","upgradeAllowed":false/' "$FAKE_CURL_DIR/127.0.0.1_8989_api_v3_qualityprofile"
    : >"$FAKE_CURL_LOG"
    local out
    out=$(kit install 2>&1) || fail "second install failed: $out"
    assert_contains "$out" 'Sonarr: quality settings (seeded '
    assert_contains "$out" 'Radarr: quality settings (seeded '
    assert_eq 0 "$(calls GET api/v3/customformat)"
    assert_contains "$(profile 8989 Any)" '"upgradeAllowed":false'
}

test_an_app_with_its_own_settings_keeps_them() {
    secrets_src
    own_settings
    local out
    out=$(kit install --secrets "$S" 2>&1) || fail "install failed: $out"
    assert_contains "$out" 'Sonarr: keeping its own quality settings (it has custom formats)'
    assert_contains "$out" "Radarr: keeping its own quality settings (its library isn't empty)"
    assert_eq 0 "$(calls POST qualityprofile)"
    assert_eq 0 "$(calls PUT qualityprofile)"
    assert_eq 1 "$(stored 8989_api_v3_customformat | grep -c .)"
    assert_contains "$(mark sonarr)" 'kept (it has custom formats)'
    assert_contains "$(profile 7878 Ultra-HD)" 'Ultra-HD'
    out=$(kit install 2>&1) || fail "second install failed: $out"
    assert_contains "$out" 'Sonarr: quality settings (kept (it has custom formats))'
}

test_a_failed_check_warns_and_tries_again() {
    secrets_src
    local out
    out=$(FAKE_CURL_FAIL=customformat kit install --secrets "$S" 2>&1) || fail "install should still succeed: $out"
    assert_contains "$out" "Sonarr: couldn't check its quality settings (custom formats: HTTP 500); the next ./kit install tries again"
    assert_eq '' "$(mark sonarr)"
    out=$(kit install 2>&1) || fail "second install failed: $out"
    assert_contains "$out" 'Sonarr: quality profile Anime'
}

test_an_app_with_no_profiles_yet_is_tried_again() {
    secrets_src
    mkdir -p "$FAKE_CURL_DIR"
    : >"$FAKE_CURL_DIR/127.0.0.1_7878_api_v3_qualityprofile"
    local out
    out=$(kit install --secrets "$S" 2>&1) || fail "install should still succeed: $out"
    assert_contains "$out" "Radarr: couldn't check its quality settings (no profiles yet: it's still starting)"
    assert_eq '' "$(mark radarr)"
    assert_contains "$(mark sonarr)" 'seeded '
}

test_plan_seeds_nothing() {
    secrets_src
    kit install --secrets "$S" >/dev/null 2>&1 || fail "install failed"
    rm -f "$KIT_SERVER_DIR/appdata/media-stack/radarr/kit-quality"
    rm -f "$FAKE_CURL_DIR"/127.0.0.1_7878_api_v3_qualit* "$FAKE_CURL_DIR"/127.0.0.1_7878_api_v3_customformat
    : >"$FAKE_CURL_LOG"
    local out
    out=$(kit install --plan 2>&1) || fail "plan failed: $out"
    assert_contains "$out" "Radarr: the kit's quality profiles, custom formats and sizes (it still has its stock ones)"
    assert_contains "$out" 'Sonarr: quality settings (seeded '
    assert_eq '' "$(grep -v '^GET ' "$FAKE_CURL_LOG" | grep -E '7878|8989')"
    assert_eq '' "$(mark radarr)"
}
