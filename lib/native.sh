# shellcheck shell=bash
# Native apps the kit installs on macOS itself (Plex, Glances): found in APPS_DIR, then
# /Applications and ~/Applications, so one that's already there isn't installed again; installed
# with Homebrew when it's there, else (or when Homebrew fails) from the vendor's own download. A failed install warns
# and the rest of the install goes on (check-health then shows the app as down).
# Sourced by ./kit. Modules use these from their hooks/install.

kbrew() { "${KIT_BREW:-brew}" "$@"; }
SYSTEM_APPS=${KIT_SYSTEM_APPS:-/Applications}

default_apps() { printf '%s' "$SYSTEM_APPS"; }      # APPS_DIR's default (modules/core/prompts)

# OLLAMA_MODEL's default (modules/ollama/prompts): the biggest Qwen 3.5 that leaves room for the
# rest of the server (OrbStack's VM, Plex or Jellyfin) in this Mac's memory
default_ollama_model() {
    local gb
    gb=${KIT_MEM_GB:-$(sysctl -n hw.memsize 2>/dev/null | awk '{ printf "%d", $1 / 1073741824 }')}
    if [ "${gb:-0}" -ge 48 ]; then printf 'qwen3.5:27b'      # 17.5 GB
    elif [ "${gb:-0}" -ge 24 ]; then printf 'qwen3.5:9b'     # 6.6 GB
    elif [ "${gb:-0}" -ge 16 ]; then printf 'qwen3.5:4b'     # 3.3 GB
    else printf 'qwen3.5:2b'; fi                             # 2.7 GB
}
apps_dir() { answer APPS_DIR || default_apps; }

app_find() {        # name -> the path of name.app, wherever it's installed
    local d
    for d in "$(apps_dir)" "$SYSTEM_APPS" "$HOME/Applications"; do
        [ -d "$d/$1.app" ] && { printf '%s' "$d/$1.app"; return 0; }
    done
    return 1
}

apps_dir_ready() {  # -> 0 when APPS_DIR exists (made if missing) and can be written
    local d
    d=$(apps_dir)
    in_plan && return 0
    mkdir -p "$d" 2>/dev/null
    [ -w "$d" ] && return 0
    warn "$(tilde "$d") can't be written by $(id -un). Set APPS_DIR=~/Applications in $(shown "$ANSWERS") (apps for this account only), or run ./kit install as an admin."
    return 1
}

# Download a file and check it against the vendor's published checksum
download_checked() {    # url sha1-or-sha256 file
    local url=$1 sum=$2 file=$3 got algo=1
    [ ${#sum} -eq 64 ] && algo=256
    kcurl -fsSL --retry 2 --max-time 900 -o "$file" "$url" 2>/dev/null || { NATIVE_ERR="couldn't download $url"; return 1; }
    got=$(shasum -a $algo "$file" | cut -d' ' -f1)
    [ "$got" = "$sum" ] && return 0
    NATIVE_ERR="the download of $url doesn't match its published checksum"
    rm -f "$file"
    return 1
}
# shellcheck disable=SC2034  # set here, read by the modules' install hooks
NATIVE_ERR=''
