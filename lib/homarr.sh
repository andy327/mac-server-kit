# shellcheck shell=bash
# Homarr, the dashboard: its admin account, an API key for the kit, and a tile (app) plus a
# widget connection (integration) for each app. Checked against Homarr 2.3. Sourced by ./kit.
#
# Tiles go through Homarr's published API (/api/apps). Integrations, the first account and the
# key go through the calls Homarr's own pages make (/api/trpc/...), which aren't a published
# API: they may change between versions, so every failure warns and the install goes on.
# Nothing is placed on a board; that's left to the user.

HOMARR=http://127.0.0.1:7575
HOMARR_KEY=''
HOMARR_ADMIN='admin'
HOMARR_ICONS=https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons@master/svg

homarr_call() {     # method path [json] -> like api_call; a tRPC error inside a 200 answer fails too
    # shellcheck disable=SC2034  # api_call reads it
    local API_KEY_HEADER=ApiKey
    api_call "$1" "$HOMARR$2" "$HOMARR_KEY" "${@:3}" || return 1
    case "$API_BODY" in '{"error":'*|*'"json":{"error":{'*) return 1 ;; esac
    return 0
}

homarr_warn() {     # text
    warn "Homarr: $1"
    WIRE_WARNINGS=$((WIRE_WARNINGS + 1))
}

# Find or make the kit's API key. A fresh Homarr gets its admin account (admin, with the
# generated HOMARR_ADMIN_PASSWORD) and a key, kept in generated-secrets.conf. A Homarr that
# already has an account needs a key from its owner, in secrets.conf as HOMARR_API_KEY.
# shellcheck disable=SC2153  # SECRETS and GEN_SECRETS come from config.sh
homarr_prepare() {  # -> 0 with HOMARR_KEY set
    local mine step
    mine=$(kv_get "$SECRETS" HOMARR_API_KEY || true)
    HOMARR_KEY=${mine:-$(kv_get "$GEN_SECRETS" HOMARR_API_KEY || true)}
    if [ -n "$HOMARR_KEY" ]; then
        homarr_call GET /api/info && return 0
        if [ -n "$mine" ]; then
            homarr_warn "HOMARR_API_KEY in $(tilde "$SECRETS") isn't accepted ($(api_error)); no tiles made"
            return 1
        fi
    fi
    HOMARR_KEY=''
    if ! homarr_call GET /api/trpc/onboard.currentStep; then
        homarr_warn "couldn't read its setup state ($(api_error)); no tiles made"
        return 1
    fi
    step=$(printf '%s' "$API_BODY" | json_flat | sed -n 's/.*"current":"\([^"]*\)".*/\1/p')
    case "$step" in
        start|user) homarr_onboard "$step" ;;
        *)
            note "Homarr already has an account, so the kit needs a key from you: sign in, create an API key under Management → Tools → API, put it in $(tilde "$SECRETS") as HOMARR_API_KEY and run ./kit install again."
            return 1 ;;
    esac
}

# Homarr's first-run steps up to the account, then a key: claim the setup (a cookie), step past
# the welcome page, create the admin, sign in, create a key. The rest of the setup (server
# settings, the first board) is left for the user.
homarr_onboard() {  # current-step
    local API_JAR pw csrf status key rc=1
    pw=$(secret HOMARR_ADMIN_PASSWORD) || { homarr_warn "no HOMARR_ADMIN_PASSWORD"; return 1; }
    API_JAR=$(mktemp "$KIT_STATE/.homarr.XXXXXX") || { homarr_warn "couldn't create a cookie file"; return 1; }
    chmod 600 "$API_JAR"
    while :; do
        homarr_call POST /api/onboarding/claim '{}' || { homarr_warn "couldn't start its setup ($(api_error))"; break; }
        if [ "$1" = start ]; then
            homarr_call POST /api/trpc/onboard.nextStep '{"json":{}}' \
                || { homarr_warn "couldn't step past its welcome page ($(api_error))"; break; }
        fi
        homarr_call POST /api/trpc/user.initUser \
            "{\"json\":{\"username\":\"$HOMARR_ADMIN\",\"password\":\"$(json_str "$pw")\",\"confirmPassword\":\"$(json_str "$pw")\"}}" \
            || { homarr_warn "couldn't create the admin account ($(api_error))"; break; }
        homarr_call GET /api/auth/csrf || { homarr_warn "couldn't sign in ($(api_error))"; break; }
        csrf=$(printf '%s' "$API_BODY" | json_flat | sed -n 's/.*"csrfToken":"\([^"]*\)".*/\1/p')
        status=$(kcurl -sS --max-time 30 -o /dev/null -w '%{http_code}' -b "$API_JAR" -c "$API_JAR" \
            --data-urlencode "csrfToken=$csrf" --data-urlencode "name=$HOMARR_ADMIN" \
            --data-urlencode "password=$pw" "$HOMARR/api/auth/callback/credentials" 2>/dev/null || true)
        homarr_call GET /api/auth/session
        case "$API_BODY" in *"\"name\":\"$HOMARR_ADMIN\""*) ;; *)
            homarr_warn "couldn't sign in as $HOMARR_ADMIN (HTTP $status); sign in yourself with HOMARR_ADMIN_PASSWORD from $(tilde "$GEN_SECRETS")"
            break ;;
        esac
        homarr_call POST /api/trpc/apiKeys.create '{"json":{}}' \
            || { homarr_warn "couldn't create an API key ($(api_error))"; break; }
        key=$(printf '%s' "$API_BODY" | json_flat | sed -n 's/.*"apiKey":"\([^"]*\)".*/\1/p')
        [ -n "$key" ] || { homarr_warn "no API key in its answer"; break; }
        kv_append "$GEN_SECRETS" HOMARR_API_KEY "$key" quote force
        HOMARR_KEY=$key
        ok "Homarr: admin account ($HOMARR_ADMIN) and an API key for the kit"
        rc=0
        break
    done
    rm -f "$API_JAR"
    return $rc
}

homarr_id_of() {    # name -> the "id" of the entry with that "name" in the list in API_BODY
    printf '%s' "$API_BODY" | json_flat | sed 's/},{/}\
{/g' | grep -F "\"name\":\"$1\"" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | head -n 1
}

# One app: its tile, and, with HOMARR_INTEGRATIONS=on, its widget connection, linked to the tile.
# Either can be left out: an empty href makes no tile, an empty kind no integration.
homarr_app() {      # name description icon href ping-url kind url secrets-json
    local name=$1 desc=$2 icon=$3 href=$4 ping=$5 kind=$6 url=$7 secrets=$8 id='' app=''
    [ -n "$HOMARR_KEY" ] || return 0
    if [ -n "$href" ]; then
        if ! homarr_call GET /api/apps; then
            homarr_warn "couldn't read its apps ($(api_error)); skipped $name"
            return 1
        fi
        id=$(homarr_id_of "$name")
        if [ -n "$id" ]; then
            note "Homarr: $name tile (already there)"
        elif homarr_call POST /api/apps "{\"name\":\"$name\",\"description\":\"$(json_str "$desc")\",\"iconUrl\":\"$HOMARR_ICONS/$icon.svg\",\"href\":\"$href\",\"pingUrl\":\"$ping\"}"; then
            id=$(printf '%s' "$API_BODY" | json_flat | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
            ok "Homarr: $name tile"
        else
            homarr_warn "$name tile: $(api_error)"
        fi
    fi
    [ -n "$kind" ] && [ "$(answer HOMARR_INTEGRATIONS || true)" != off ] || return 0
    if ! homarr_call GET /api/trpc/integration.all; then
        homarr_warn "couldn't read its integrations ($(api_error)); skipped $name"
        return 1
    fi
    if printf '%s' "$API_BODY" | json_flat | grep -qF "\"name\":\"$name\""; then
        note "Homarr: $name widget connection (already there)"
        return 0
    fi
    [ -z "$id" ] || app=",\"app\":{\"id\":\"$id\"}"
    if homarr_call POST /api/trpc/integration.create \
        "{\"json\":{\"name\":\"$name\",\"url\":\"$url\",\"kind\":\"$kind\",\"secrets\":[$secrets],\"attemptSearchEngineCreation\":false$app}}"; then
        ok "Homarr: $name widget connection"
    else
        homarr_warn "$name widget connection: $(api_error)"
    fi
}

homarr_secret() {   # kind value -> one entry of an integration's secrets list
    printf '{"kind":"%s","value":"%s"}' "$1" "$(json_str "$2")"
}

# ---------------------------------------------------------------- custom widgets
#
# A module's homarr-widget.json is a Homarr custom widget (a "homarr-custom-widget-v2"
# definition, without its template) and homarr-widget.jsx is its template. Each is imported
# once, by name, through customWidget.import (checked against Homarr 2.11). Like tiles, it's
# left to the user to put on a board.

json_text() {       # file -> its text as one JSON string, quotes included
    awk 'BEGIN { ORS = ""; print "\"" }
         { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); if (NR > 1) print "\\n"; print }
         END { print "\"" }' "$1"
}

homarr_widgets() {  # modules...
    local m d def name listed=''
    HOMARR_KEY=$(kv_get "$SECRETS" HOMARR_API_KEY || kv_get "$GEN_SECRETS" HOMARR_API_KEY || true)
    [ -n "$HOMARR_KEY" ] || return 0        # the Homarr step above said why
    for m in "$@"; do
        d=$(mod_dir "$m")
        [ -f "$d/homarr-widget.json" ] && [ -f "$d/homarr-widget.jsx" ] || continue
        def=$(json_flat <"$d/homarr-widget.json")
        name=$(printf '%s' "$def" | grep -o '"name":"[^"]*"' | head -n 1 | sed 's/^"name":"//; s/"$//')
        if [ -z "$listed" ]; then
            if ! homarr_call GET /api/trpc/customWidget.list; then
                homarr_warn "couldn't read its custom widgets ($(api_error)); custom widgets need a newer Homarr"
                return 1
            fi
            listed=$API_BODY
        fi
        if printf '%s' "$listed" | json_flat | grep -qF "\"name\":\"$name\""; then
            note "Homarr: $name widget (already there)"
        elif homarr_call POST /api/trpc/customWidget.import \
            "{\"json\":{\"widget\":${def%\}},\"template\":$(json_text "$d/homarr-widget.jsx")}}}"; then
            ok "Homarr: $name widget (Management → Custom widgets; add it to a board)"
        else
            homarr_warn "$name widget: $(api_error)"
        fi
    done
}
