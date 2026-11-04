# shellcheck shell=bash
# The install steps after configuration: folders, PATH, compose projects, seeding, start.
# Sourced by ./kit after modules.sh.

ZPROFILE=$HOME/.zprofile
ZPROFILE_MARK='# added by mac-server-kit'

# ---------------------------------------------------------------- folders and PATH

# A folder on an external drive (/Volumes/<drive>/...) is only used when the drive is mounted.
# Otherwise mkdir would quietly create it on the startup disk, and media would fill that instead.
check_volume() {    # path
    local vol
    case "$1" in
        /Volumes/*/*|/Volumes/*) vol=/Volumes/$(printf '%s' "${1#/Volumes/}" | cut -d/ -f1) ;;
        *) return 0 ;;
    esac
    [ -d "$vol" ] || die "$vol isn't mounted. Connect the drive (or change $1 in $(tilde "$ANSWERS")), then run ./kit install again."
}

layout_create() {
    local media d
    media=$(answer MEDIA_ROOT)
    check_volume "$media"
    for d in bin appdata backups logs kit; do
        mkdir -p "$SERVER_DIR/$d" || die "could not create $SERVER_DIR/$d"
    done
    for d in Downloads Movies 'TV Shows'; do
        mkdir -p "$media/$d" || die "could not create $media/$d"
    done
    ok "Folders: $(tilde "$SERVER_DIR"), $(tilde "$media")"
}

# One marked line in ~/.zprofile puts ~/server/bin on the PATH. Added once; never changed after.
# shellcheck disable=SC2016  # $HOME and $PATH are for zsh to expand, not us
zprofile_line() {
    local bin=$SERVER_DIR/bin
    case "$bin" in "$HOME"/*) bin='$HOME'${bin#"$HOME"} ;; esac
    printf 'export PATH="%s:$PATH"  %s' "$bin" "$ZPROFILE_MARK"
}

zprofile_add() {
    if [ -f "$ZPROFILE" ] && grep -qF "$ZPROFILE_MARK" "$ZPROFILE"; then
        return 0
    fi
    if [ -s "$ZPROFILE" ] && [ -n "$(tail -c 1 "$ZPROFILE")" ]; then printf '\n' >>"$ZPROFILE"; fi
    { zprofile_line; printf "\n"; } >>"$ZPROFILE" || die "could not write $(tilde "$ZPROFILE")"
    ok "Added $(tilde "$SERVER_DIR/bin") to the PATH in $(tilde "$ZPROFILE") (new Terminal windows)"
}
