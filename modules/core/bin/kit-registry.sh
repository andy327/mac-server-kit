# shellcheck shell=bash
# Release tags from an image registry, for tracking a release series (v2.*) instead of a tag.
# Sourced by kit-runtime.sh (update-project) and by ./kit install (lib/project.sh), so both pick
# the same release. Needs only curl. Installed by mac-server-kit; ./kit install replaces it.

# The tags a registry lists for a repo, one per line. ghcr.io (and lscr.io, which serves the
# same images) and Docker Hub; anonymous pull tokens, which public images allow.
registry_tags() {   # repo
    local repo=$1 host path token url
    case "$repo" in
        ghcr.io/*|lscr.io/*) host=ghcr.io; path=${repo#*/} ;;
        docker.io/*) host=registry-1.docker.io; path=${repo#docker.io/} ;;
        */*/*) return 1 ;;      # another registry: not supported
        */*) host=registry-1.docker.io; path=$repo ;;
        *) host=registry-1.docker.io; path=library/$repo ;;
    esac
    case "$host" in
        ghcr.io) token=$("${KIT_CURL:-curl}" -fsS -m 20 "https://ghcr.io/token?scope=repository:$path:pull") || return 1 ;;
        *) token=$("${KIT_CURL:-curl}" -fsS -m 20 "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$path:pull") || return 1 ;;
    esac
    token=$(printf '%s' "$token" | tr -d '\n' | sed -n 's/.*"token" *: *"\([^"]*\)".*/\1/p')
    [ -n "$token" ] || return 1
    # A page holds at most 1,000 tags (ghcr.io; Docker Hub fewer), and a Link header names the
    # next: follow it, or an image with many build tags (Open WebUI) shows only its oldest releases
    local hdr page next last='' n=0
    hdr=$(mktemp "${TMPDIR:-/tmp}/kit-tags.XXXXXX") || return 1
    while :; do
        # A partial list would pick an old release, so too many pages is a failure
        n=$((n + 1))
        [ "$n" -le 300 ] || { rm -f "$hdr"; return 1; }
        url="https://$host/v2/$path/tags/list?n=1000${last:+&last=$last}"
        : >"$hdr"
        page=$("${KIT_CURL:-curl}" -fsS -m 30 -D "$hdr" -H "Authorization: Bearer $token" "$url") || { rm -f "$hdr"; return 1; }
        printf '%s' "$page" | tr -d '\n' | sed -n 's/.*"tags" *: *\[\(.*\)\].*/\1/p' | tr ',' '\n' | sed 's/^ *"//; s/" *$//'
        next=$(tr -d '\r' <"$hdr" | sed -n 's/^[Ll]ink:.*[?&]last=\([^&>]*\).*rel="next".*/\1/p' | head -n 1)
        [ -n "$next" ] && [ "$next" != "$last" ] || break
        last=$next
    done
    rm -f "$hdr"
}

# The newest release tag that a series like v2.* or 1.4.* matches: the tags that are the
# series' prefix plus dotted numbers only (no -beta, no -alpine), compared number by number.
newest_tag() {      # repo series
    local prefix=${2%\*}
    registry_tags "$1" | awk -v p="$prefix" '
        index($0, p) == 1 {
            rest = substr($0, length(p) + 1)
            if (rest !~ /^[0-9]+(\.[0-9]+)*$/) next
            n = split(rest, a, "."); key = ""
            for (i = 1; i <= 4; i++) key = key sprintf("%08d", (i <= n ? a[i] : 0))
            print key, $0
        }' | sort | tail -n 1 | cut -d' ' -f2
}

