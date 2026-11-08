# shellcheck shell=bash
# Release tags from an image registry, for tracking a release series (v2.*) instead of a tag.
# Sourced by kit-runtime.sh (update-project) and by ./kit install (lib/project.sh), so both pick
# the same release. Needs only curl. Installed by mac-server-kit; ./kit install replaces it.

# The tags a registry lists for a repo, one per line. ghcr.io (and lscr.io, which serves the
# same images) and Docker Hub; anonymous pull tokens, which public images allow.
# A registry's host, the repo's path there and an anonymous pull token (REG_HOST, REG_PATH,
# REG_TOKEN): ghcr.io (and lscr.io, which serves the same images) and Docker Hub
registry_auth() {   # repo
    local repo=$1 token
    case "$repo" in
        ghcr.io/*|lscr.io/*) REG_HOST=ghcr.io; REG_PATH=${repo#*/} ;;
        docker.io/*) REG_HOST=registry-1.docker.io; REG_PATH=${repo#docker.io/} ;;
        */*/*) return 1 ;;      # another registry: not supported
        */*) REG_HOST=registry-1.docker.io; REG_PATH=$repo ;;
        *) REG_HOST=registry-1.docker.io; REG_PATH=library/$repo ;;
    esac
    case "$REG_HOST" in
        ghcr.io) token=$("${KIT_CURL:-curl}" -fsS -m 20 "https://ghcr.io/token?scope=repository:$REG_PATH:pull") || return 1 ;;
        *) token=$("${KIT_CURL:-curl}" -fsS -m 20 "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$REG_PATH:pull") || return 1 ;;
    esac
    REG_TOKEN=$(printf '%s' "$token" | tr -d '\n' | sed -n 's/.*"token" *: *"\([^"]*\)".*/\1/p')
    [ -n "$REG_TOKEN" ]
}

# The digest a tag points at now (what a pull would get), from a HEAD of its manifest: for
# ./kit install --plan, which pulls nothing
registry_digest() { # repo tag -> sha256:...
    local d
    registry_auth "$1" || return 1
    d=$("${KIT_CURL:-curl}" -fsSI -m 20 -H "Authorization: Bearer $REG_TOKEN" \
        -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json' \
        "https://$REG_HOST/v2/$REG_PATH/manifests/$2" 2>/dev/null | tr -d '\r' | sed -n 's/^[Dd]ocker-[Cc]ontent-[Dd]igest: *//p' | head -n 1)
    case "$d" in sha256:*) printf '%s' "$d" ;; *) return 1 ;; esac
}

# The tags a registry lists for a repo, one per line (anonymous pull tokens, which public
# images allow)
registry_tags() {   # repo
    local host path token url
    registry_auth "$1" || return 1
    host=$REG_HOST path=$REG_PATH token=$REG_TOKEN
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

