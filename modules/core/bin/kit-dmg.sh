# shellcheck shell=bash disable=SC2034  # DMG_ERR, REL_* and OLLAMA_DIR are for the callers
# A native app's current release from Homebrew's public cask data (formulae.brew.sh, read with
# curl, so Homebrew needn't be installed), and installing it from its .dmg: downloaded, checked
# against the SHA-256 Homebrew publishes, mounted with hdiutil and copied with ditto. Sourced by
# kit-runtime.sh (update-jellyfin) and by ./kit install (lib/native.sh), so both pick the same
# release. Installed by mac-server-kit; ./kit install replaces it.

CASK_API=${KIT_CASK_API:-https://formulae.brew.sh/api/cask}
DMG_ERR=''

# Sets REL_VERSION, REL_URL and REL_SUM for this Mac's processor (arm64 or Intel). The cask lists
# one build at the top and the other under "variations", each a url with its sha256.
cask_release() {    # cask
    local json flat arch want pairs pair
    REL_VERSION='' REL_URL='' REL_SUM=''
    json=$("${KIT_CURL:-curl}" -fsSL --max-time 30 "$CASK_API/$1.json" 2>/dev/null) || { DMG_ERR="couldn't read $CASK_API/$1.json"; return 1; }
    arch=$(uname -m)
    case "$arch" in arm64) want='(arm64|aarch64)' ;; *) want='(amd64|x86_64|x64|intel)' ;; esac
    REL_VERSION=$(printf '%s' "$json" | plutil -extract version raw -o - - 2>/dev/null)
    flat=$(printf '%s' "$json" | tr -d '\n' | sed 's/[[:space:]]*\([][{}:,]\)[[:space:]]*/\1/g')
    pairs=$( { printf '"url":"%s","sha256":"%s"\n' "$(printf '%s' "$json" | plutil -extract url raw -o - - 2>/dev/null)" \
                   "$(printf '%s' "$json" | plutil -extract sha256 raw -o - - 2>/dev/null)"
               printf '%s' "$flat" | grep -oE '"url":"[^"]*","sha256":"[0-9a-f]{64}"'; } )
    pair=$(printf '%s\n' "$pairs" | grep -E "\"url\":\"[^\"]*${want}[^\"]*\\.dmg\"" | grep -E '"sha256":"[0-9a-f]{64}"' | head -n 1)
    REL_URL=$(printf '%s' "$pair" | sed -n 's/^"url":"\([^"]*\)".*/\1/p')
    REL_SUM=$(printf '%s' "$pair" | sed -n 's/.*"sha256":"\([0-9a-f]*\)"$/\1/p')
    [ -n "$REL_VERSION" ] && [ -n "$REL_URL" ] && [ -n "$REL_SUM" ] && return 0
    DMG_ERR="Homebrew's data for $1 has no .dmg for this Mac ($arch)"
    return 1
}

# Download a .dmg, check it, and copy the app in it into a folder. An app already there is
# replaced only once the new copy is complete.
dmg_install() {     # url sha256 app-name folder
    local url=$1 sum=$2 app=$3 dir=$4 tmp rc=1
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/kit-dmg.XXXXXX") || { DMG_ERR="couldn't make a temporary folder"; return 1; }
    while :; do
        "${KIT_CURL:-curl}" -fsSL --retry 2 --max-time 1800 -o "$tmp/app.dmg" "$url" 2>/dev/null \
            || { DMG_ERR="couldn't download $url"; break; }
        [ "$(shasum -a 256 "$tmp/app.dmg" | cut -d' ' -f1)" = "$sum" ] \
            || { DMG_ERR="the download of $url doesn't match its published checksum"; break; }
        mkdir "$tmp/mnt"
        "${KIT_HDIUTIL:-hdiutil}" attach -nobrowse -readonly -noautoopen -mountpoint "$tmp/mnt" "$tmp/app.dmg" >/dev/null 2>&1 \
            || { DMG_ERR="couldn't open $url (hdiutil attach)"; break; }
        if [ -d "$tmp/mnt/$app.app" ] && ditto "$tmp/mnt/$app.app" "$dir/.$app.app.new" 2>/dev/null; then
            rm -rf "$dir/$app.app" && mv "$dir/.$app.app.new" "$dir/$app.app" && rc=0
        else
            rm -rf "$dir/.$app.app.new"
            DMG_ERR="couldn't copy $app.app from the download into $dir"
        fi
        "${KIT_HDIUTIL:-hdiutil}" detach "$tmp/mnt" >/dev/null 2>&1 || "${KIT_HDIUTIL:-hdiutil}" detach -force "$tmp/mnt" >/dev/null 2>&1
        break
    done
    rm -rf "$tmp"
    return $rc
}

app_version() { "${KIT_DEFAULTS:-defaults}" read "$1/Contents/Info" CFBundleShortVersionString 2>/dev/null; }   # app-path

# Whether two versions are the same release (12.4 and 12.4.0 are)
same_version() { [ "$(printf '%s' "$1" | sed -E 's/(\.0)+$//')" = "$(printf '%s' "$2" | sed -E 's/(\.0)+$//')" ]; }

# ---------------------------------------------------------------- GitHub releases (Ollama)

GITHUB=${KIT_GITHUB:-https://github.com}

# Sets REL_VERSION (without its v), REL_URL and REL_SUM for one file of a project's latest GitHub
# release, its checksum from the sha256sum.txt the release itself publishes. The release is read
# from where github.com/<repo>/releases/latest redirects to, so no GitHub API (or its rate limit).
github_release() {  # owner/repo file
    local loc tag sums
    REL_VERSION='' REL_URL='' REL_SUM=''
    loc=$("${KIT_CURL:-curl}" -fsSI --max-time 30 "$GITHUB/$1/releases/latest" 2>/dev/null | tr -d '\r' |
        sed -n 's/^[Ll]ocation: *//p' | tail -n 1)
    tag=${loc##*/releases/tag/}
    [ -n "$tag" ] && [ "$tag" != "$loc" ] || { DMG_ERR="couldn't find $1's latest release on GitHub"; return 1; }
    sums=$("${KIT_CURL:-curl}" -fsSL --max-time 30 "$GITHUB/$1/releases/download/$tag/sha256sum.txt" 2>/dev/null) ||
        { DMG_ERR="couldn't read the checksums of $1 $tag"; return 1; }
    REL_SUM=$(printf '%s\n' "$sums" | awk -v f="$2" '{ n = $2; sub(/^\*/, "", n); sub(/^\.\//, "", n) } n == f && $1 ~ /^[0-9a-f]{64}$/ { print $1; exit }')
    [ -n "$REL_SUM" ] || { DMG_ERR="$1 $tag lists no checksum for $2"; return 1; }
    REL_URL=$GITHUB/$1/releases/download/$tag/$2
    REL_VERSION=${tag#v}
}

# Download a .tgz, check it, and unpack it as a folder, replacing one already there only once
# the new one is complete
tgz_install() {     # url sha256 folder
    local url=$1 sum=$2 dir=$3 tmp rc=1
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/kit-tgz.XXXXXX") || { DMG_ERR="couldn't make a temporary folder"; return 1; }
    while :; do
        "${KIT_CURL:-curl}" -fsSL --retry 2 --max-time 1800 -o "$tmp/app.tgz" "$url" 2>/dev/null \
            || { DMG_ERR="couldn't download $url"; break; }
        [ "$(shasum -a 256 "$tmp/app.tgz" | cut -d' ' -f1)" = "$sum" ] \
            || { DMG_ERR="the download of $url doesn't match its published checksum"; break; }
        if ! { mkdir -p "$(dirname "$dir")" && rm -rf "$dir.new" && mkdir "$dir.new"; }; then
            DMG_ERR="couldn't write $(dirname "$dir")"
            break
        fi
        if tar -xzf "$tmp/app.tgz" -C "$dir.new" 2>/dev/null; then
            rm -rf "$dir" && mv "$dir.new" "$dir" && rc=0
        else
            rm -rf "$dir.new"
            DMG_ERR="couldn't unpack $url"
        fi
        break
    done
    rm -rf "$tmp"
    return $rc
}

# Where Ollama's command may be: the kit's own copy (from its release .tgz), Homebrew's (Apple
# Silicon, Intel), or inside an Ollama.app someone installed
OLLAMA_DIR=${KIT_SERVER_DIR:-$HOME/server}/apps/ollama
ollama_path() {     # [apps folder]
    local p d
    for p in ${KIT_OLLAMA_PATHS:-$OLLAMA_DIR/ollama /opt/homebrew/bin/ollama /usr/local/bin/ollama}; do
        [ -x "$p" ] && { printf '%s' "$p"; return 0; }
    done
    for d in ${1:+"$1"} "${KIT_SYSTEM_APPS:-/Applications}" "$HOME/Applications"; do
        p=$d/Ollama.app/Contents/Resources/ollama
        [ -x "$p" ] && { printf '%s' "$p"; return 0; }
    done
    return 1
}
# Its version, from "ollama -v" ("ollama version is 0.40.15", or "client version is ..." when
# no server answers)
ollama_version() { "$1" -v 2>&1 | sed -n 's/.*version is \([0-9][0-9.]*\).*/\1/p' | tail -n 1; }
