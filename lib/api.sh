# shellcheck shell=bash
# App APIs over HTTP, for the wire hooks: settings that live in app databases (root folders,
# download clients, Prowlarr's apps). Stock curl and text tools only, no jq. Sourced by ./kit.
#
# Everything is create-if-missing: look the thing up first (by name or path), create it only if
# it isn't there. App APIs change between versions, so a failed step warns and the install goes on.

# curl, through one function so tests can swap in a fake (KIT_CURL)
kcurl() { "${KIT_CURL:-curl}" "$@"; }

API_STATUS=''       # the last call's HTTP status (000: no answer)
API_BODY=''         # the last call's response body
API_KEY_HEADER=X-Api-Key    # the header the key goes in (Homarr: ApiKey)
API_JAR=''          # a cookie file to send and update, when set (Homarr's sign-in)

api_call() {        # method url api-key [json] -> 0 on a 2xx answer; sets API_STATUS and API_BODY
    local out opts
    opts=(-sS --max-time 30 -X "$1" -H "$API_KEY_HEADER: $3" -w '\n%{http_code}')
    [ -z "$API_JAR" ] || opts+=(-b "$API_JAR" -c "$API_JAR")
    [ $# -lt 4 ] || opts+=(-H 'Content-Type: application/json' --data "$4")
    out=$(kcurl "${opts[@]}" "$2" 2>&1)
    API_STATUS=${out##*$'\n'}
    API_BODY=${out%$'\n'*}
    case "$API_STATUS" in [0-9][0-9][0-9]) ;; *) API_STATUS=000; API_BODY=$out ;; esac
    case "$API_STATUS" in 2??) return 0 ;; esac
    return 1
}

# JSON on one line with no spaces around { } [ ] : and , so a fixed string such as "path":"/tv"
# can be searched for, and lists split at "},{", whatever the app's formatting. (Spaces next to
# those characters inside strings go too; fine for searching.)
json_flat() { tr -d '\n' | sed 's/[[:space:]]*\([][{}:,]\)[[:space:]]*/\1/g'; }

# Why a call failed, for a warning: the apps' first error message, else the status.
api_error() {
    local msg
    msg=$(printf '%s' "$API_BODY" | json_flat | sed -n 's/.*"errorMessage":"\([^"]*\)".*/\1/p' | head -n 1)
    [ -n "$msg" ] || msg=$(printf '%s' "$API_BODY" | json_flat | sed -n 's/.*"error":"\([^"]*\)".*/\1/p' | head -n 1)
    # Homarr (tRPC): {"error":{"json":{"message":...}}}, or an error inside a 200 answer,
    # {"result":{"data":{"json":{"error":{...,"message":...,"data":{...,"reason":...}}}}}}
    [ -n "$msg" ] || msg=$(printf '%s' "$API_BODY" | json_flat | sed -n \
        -e 's/^{"error":{"json":{"message":"\([^"]*\)".*/\1/p' \
        -e 's/.*"json":{"error":{[^}]*"message":"\([^"]*\)","data":{[^}]*"reason":"\([^"]*\)".*/\1 (\2)/p' \
        -e 's/.*"json":{"error":{[^}]*"message":"\([^"]*\)".*/\1/p' | head -n 1)
    # Seerr: {"message":"request/body must have required property '...'",...}
    [ -n "$msg" ] || msg=$(printf '%s' "$API_BODY" | json_flat | sed -n 's/^{"message":"\([^"]*\)".*/\1/p' | head -n 1)
    case "$API_STATUS" in
        000) printf 'no answer' ;;
        *) printf 'HTTP %s%s' "$API_STATUS" "${msg:+: $msg}" ;;
    esac
}

WIRE_WARNINGS=0

# Create one thing unless it's there: GET the list, look for a fixed string in it, else POST.
api_ensure() {      # label list-url api-key needle json [post-url]
    local label=$1 url=$2 key=$3 needle=$4 json=$5 post=${6:-$2}
    if ! api_call GET "$url" "$key"; then
        warn "$label: couldn't read the current settings ($(api_error)); skipped"
        WIRE_WARNINGS=$((WIRE_WARNINGS + 1))
        return 1
    fi
    if printf '%s' "$API_BODY" | json_flat | grep -qF -- "$needle"; then
        note "$label (already set)"
        return 0
    fi
    if api_call POST "$post" "$key" "$json"; then
        ok "$label"
        return 0
    fi
    warn "$label: $(api_error); set it by hand"
    WIRE_WARNINGS=$((WIRE_WARNINGS + 1))
    return 1
}

# The "id" of the list entry whose "label"/"name" is the given one (Prowlarr tags, quality
# profiles): entries are split at "},{" and the first match wins.
api_id_of() {       # field value -> id (reads the JSON list in API_BODY)
    printf '%s' "$API_BODY" | json_flat | sed 's/},{/}\
{/g' | grep -F "\"$1\":\"$2\"" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p' | head -n 1
}

# JSON string escaping for values the kit puts in request bodies (passwords, keys)
json_str() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
