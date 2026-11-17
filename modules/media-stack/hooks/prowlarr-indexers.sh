# shellcheck shell=bash
# Prowlarr's indexers: the kit's suggested public indexers (no accounts or keys) and the code that
# adds them through Prowlarr's API, into a Prowlarr that has no indexers yet. Sourced by the media
# stack's wire hook (a file of hooks/ that isn't a step of its own), which has lib/api.sh's
# api_call, api_id_of and api_js, and the kit's ok and warn. Each indexer starts from Prowlarr's
# own template for it (GET indexer/schema, by definitionName), so its fields are this Prowlarr
# version's; the kit sets only enable, priority, tags and the sync profile. Prowlarr tests an
# indexer as it's added and refuses one it can't reach. One Cloudflare refused is tried again with
# the flaresolverr tag; one still refused is added anyway (turned off, then on with forceSave,
# which skips the test), since these sites' Cloudflare checks and outages come and go and
# Prowlarr keeps retrying a failing indexer on its own. Prowlarr then syncs them to Sonarr and
# Radarr.

# The defaults, one per line: definitionName|priority|tags|sync profile. Priority: lower is
# preferred when releases tie (Prowlarr's default is 25). Tags are Prowlarr tag labels (comma-
# separated): flaresolverr sends the indexer's requests through FlareSolverr. Whether a site shows
# Cloudflare's challenge depends on the visitor's address (Prowlarr goes out on the home
# connection, not the VPN) and on the day, so the tag is on the ones that show it most; the rest
# get it when Cloudflare refuses them as they're added. Sync profiles are Prowlarr's: Standard (its own), or the kit's
# Interactive only (below). Lines starting with # are comments. Left out on purpose:
# torrentdownloads (Cloudflare blocks it even through FlareSolverr), kickasstorrents and
# extratorrent (copycats of sites that closed).
pix_data() {
    cat <<'EOF'
# Anime first: Nyaa is the main anime tracker, and SubsPlease is where new episodes appear first,
# from a group the Anime profile's English Sub Groups format prefers
nyaasi|10||Standard
SubsPlease|10||Standard
# The big general ones, at Prowlarr's default priority: EZTV for TV (its Cloudflare check comes
# and goes), The Pirate Bay for everything, YTS for small movie encodes
eztv|25|flaresolverr|Standard
thepiratebay|25||Standard
yts|25||Standard
# Broad, but behind the big ones: 1337x shows its Cloudflare challenge on and off, Knaben
# searches many other trackers (so mostly repeats), Tokyo Toshokan overlaps Nyaa for anime
1337x|30|flaresolverr|Standard
Knaben|30||Standard
tokyotosho|30||Standard
# General sites with fewer seeders, for what the others don't have
limetorrents|35||Standard
torrentdownload|35||Standard
# Slow and rate-limited: only when someone searches by hand, never for RSS or automatic searches
uindex|40|flaresolverr|Interactive only
EOF
}

# The kit's own sync profile, for indexers that shouldn't be asked on every RSS sync or
# automatic search
PIX_INTERACTIVE='Interactive only'
PIX_INTERACTIVE_JSON='{"name":"Interactive only","enableRss":false,"enableAutomaticSearch":false,"enableInteractiveSearch":true,"minimumSeeders":1}'

PIX_ERR=''          # why a check or a read failed

pix_status() { case "$API_STATUS" in 000) printf 'no answer' ;; *) printf 'HTTP %s' "$API_STATUS" ;; esac; }

# Whether Prowlarr has no indexers yet, so the defaults can go in without mixing with anyone's.
# 0 none, 1 it has some (PIX_ERR says so), 2 couldn't tell (PIX_ERR says why).
pix_none() {        # url key
    api_call GET "$1/api/v1/indexer" "$2" || { PIX_ERR="its indexers: $(pix_status)"; return 2; }
    [ "$(printf '%s' "$API_BODY" | tr -d ' \n\t\r')" = '[]' ] && return 0
    PIX_ERR="it has indexers of its own"
    return 1
}

# The id of a sync profile, by name; the kit's Interactive only is made if it's missing.
pix_profile_id() {  # url key name -> id (empty when there's none)
    local id
    api_call GET "$1/api/v1/appprofile" "$2" || return 0
    id=$(api_id_of name "$3")
    if [ -z "$id" ] && [ "$3" = "$PIX_INTERACTIVE" ]; then
        if api_call POST "$1/api/v1/appprofile" "$2" "$PIX_INTERACTIVE_JSON"; then
            ok "Prowlarr: sync profile $PIX_INTERACTIVE (interactive search only, for slow indexers)" >&2
            # Its id from the list again: Prowlarr's answer has it last, after the settings
            ! api_call GET "$1/api/v1/appprofile" "$2" || id=$(api_id_of name "$3")
        else
            warn "Prowlarr: sync profile $PIX_INTERACTIVE: $(api_error)"
        fi
    fi
    printf '%s' "$id"
}

# An indexer's JSON with one change: tag <id> adds a tag, enable <true|false> turns it on or off.
pix_edit() {        # json tag|enable value -> json
    API_BODY=$1 api_js 'if (a[0] === "tag") { var t = Number(a[1]); if (d.tags.indexOf(t) < 0) d.tags.push(t); }
        else d.enable = a[1] === "true";
        return JSON.stringify(d);' "$2" "$3"
}

# Prowlarr tests the site as it's added, through FlareSolverr for a tagged one (up to 2 minutes
# each try, and it tries again), so an add may take minutes
PIX_ADD_TIMEOUT=360

# Add one indexer. Says what happened with ok or warn. 0 added and tested, 1 added though
# Prowlarr's test failed (or left turned off), 2 not added.
pix_add() {         # url key name json flaresolverr-tag-id
    local url=$1 key=$2 name=$3 body=$4 cf=$5 why tagged id
    if API_TIMEOUT=$PIX_ADD_TIMEOUT api_call POST "$url/api/v1/indexer" "$key" "$body"; then
        ok "Prowlarr: indexer $name"
        return 0
    fi
    why=$(api_error)
    # Cloudflare refused it: again through FlareSolverr, unless it went through it already
    case "$why" in *[Cc]loud[Ff]lare*)
        tagged=''
        [ -z "$cf" ] || tagged=$(pix_edit "$body" tag "$cf")
        if [ -n "$tagged" ] && [ "$tagged" != "$body" ]; then
            body=$tagged
            if API_TIMEOUT=$PIX_ADD_TIMEOUT api_call POST "$url/api/v1/indexer" "$key" "$body"; then
                ok "Prowlarr: indexer $name (tagged flaresolverr: Cloudflare blocked it)"
                return 0
            fi
            why=$(api_error)
        fi ;;
    esac
    # Still refused: added anyway. Prowlarr tests only an indexer that's on, and skips the test
    # of an update sent with forceSave, so it goes in turned off and is then turned on.
    if ! api_call POST "$url/api/v1/indexer" "$key" "$(pix_edit "$body" enable false)"; then
        warn "Prowlarr: indexer $name: $why; add it later in Prowlarr if you want it"
        return 2
    fi
    id=$(api_js 'return d.id || "";')
    if [ -n "$id" ] && api_call PUT "$url/api/v1/indexer/$id?forceSave=true" "$key" "$(pix_edit "$API_BODY" enable true)"; then
        warn "Prowlarr: indexer $name added, though Prowlarr's test failed ($why); Prowlarr tries it again on its own (if it keeps failing, disable or delete it in Prowlarr)"
    else
        warn "Prowlarr: indexer $name added turned off ($why); turn it on in Prowlarr once its Test passes"
    fi
    return 1
}

# Add the defaults. Says what it did with ok and what failed with warn. Returns 0 when every one
# went in and passed Prowlarr's test, 1 when some didn't, 2 when it couldn't start (Prowlarr's
# templates unreadable: the next run tries again).
# shellcheck disable=SC2034  # PIX_ERR is for the wire hook's warning
pix_seed() {        # url key
    local url=$1 key=$2 def prio tags prof ids t tid pid cf lines='' name body bad=0 schema tagl='' profs='|'
    api_call GET "$url/api/v1/indexer/schema" "$key" || { PIX_ERR="its indexer templates: $(pix_status)"; return 2; }
    schema=$API_BODY
    ! api_call GET "$url/api/v1/tag" "$key" || tagl=$API_BODY
    cf=$(API_BODY=$tagl api_id_of label flaresolverr)
    # Tag labels and profile names to ids (profs remembers each profile's: |name=id|...)
    while IFS='|' read -r def prio tags prof; do
        case "$def" in ''|'#'*) continue ;; esac
        ids=''
        for t in $(printf '%s' "$tags" | tr ',' ' '); do
            tid=$(API_BODY=$tagl api_id_of label "$t")
            if [ -n "$tid" ]; then ids=${ids:+$ids,}$tid
            else warn "Prowlarr: no $t tag for $def; add the tag to it in Prowlarr"; bad=1; fi
        done
        case "$profs" in
            *"|$prof="*) pid=${profs#*|"$prof"=}; pid=${pid%%|*} ;;
            *) pid=$(pix_profile_id "$url" "$key" "$prof"); profs="$profs$prof=$pid|" ;;
        esac
        if [ -z "$pid" ]; then
            warn "Prowlarr: no sync profile $prof, so $def wasn't added; add it in Prowlarr if you want it"
            bad=1
            continue
        fi
        lines="$lines$def|$prio|$ids|$pid
"
    done <<EOF
$(pix_data)
EOF
    API_BODY=$schema
    # One line per default: definitionName<TAB>name<TAB>body, name and body empty when this
    # Prowlarr has no such definition. The body is Prowlarr's template for it with the kit's
    # settings, and the first of its site addresses chosen, as Prowlarr's add dialog does.
    while IFS="$(printf '\t')" read -r def name body; do
        [ -n "$def" ] || continue
        if [ -z "$body" ]; then
            warn "Prowlarr: this version has no $def indexer; skipped"
            bad=1
        else
            pix_add "$url" "$key" "$name" "$body" "$cf" || bad=1
        fi
    done <<EOF
$(api_js 'var out = [];
    a[0].split("\n").forEach(function (l) {
        if (!l) return;
        var f = l.split("|"), def = f[0], s = null;
        d.forEach(function (x) { if (!s && String(x.definitionName).toLowerCase() === def.toLowerCase()) s = x; });
        if (!s) return out.push(def + "\t\t");
        var b = JSON.parse(JSON.stringify(s));
        delete b.id;
        b.enable = true;
        b.priority = Number(f[1]);
        b.tags = f[2] ? f[2].split(",").map(Number) : [];
        b.appProfileId = Number(f[3]);
        (b.fields || []).forEach(function (x) {
            if (x.name === "baseUrl" && !x.value && b.indexerUrls && b.indexerUrls.length) x.value = b.indexerUrls[0];
        });
        out.push(def + "\t" + (b.name || def) + "\t" + JSON.stringify(b));
    });
    return out.join("\n");' "$lines")
EOF
    return "$bad"
}
