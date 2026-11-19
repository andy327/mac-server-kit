#!/bin/bash
# mac-server-kit one-line install:
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/andy327/mac-server-kit/main/install.sh)"
#
# Gets the kit into ~/mac-server-kit (a git clone when the Command Line Tools are installed,
# otherwise a download of main), then runs ./kit install. To pass ./kit install options, put them
# after a placeholder for $0: bash -c "$(curl ...)" _ --answers answers.conf --secrets secrets.conf
# An existing folder is used as it is; update it by hand (git pull --ff-only).
#
# MSK_DIR=<folder> installs somewhere else; MSK_REF=<branch or tag> picks another ref.

set -eu -o pipefail

REPO=andy327/mac-server-kit
DIR=${MSK_DIR:-$HOME/mac-server-kit}
REF=${MSK_REF:-main}

say() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || die "mac-server-kit runs on macOS only"

if [ -x "$DIR/kit" ]; then
    say "Using the kit already in $DIR"
elif [ -e "$DIR" ]; then
    die "$DIR exists but has no kit in it; move it aside or set MSK_DIR"
elif xcode-select -p >/dev/null 2>&1; then
    # /usr/bin/git is only a stub that offers to install the Command Line Tools until they're in
    say "Cloning $REPO into $DIR"
    git clone --quiet --branch "$REF" "https://github.com/$REPO.git" "$DIR"
else
    say "Downloading $REPO ($REF) into $DIR"
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL "https://codeload.github.com/$REPO/tar.gz/$REF" | tar -xzf - -C "$tmp"
    mv "$tmp"/mac-server-kit-* "$DIR"
    rmdir "$tmp"; trap - EXIT           # the exec below would skip the trap
    say "Without git, update later by downloading again (or install the Command Line Tools and clone)"
fi

cd "$DIR"

say "Running ./kit install (safe to run again; ./kit prepare lists what to have ready)"

# Under curl | bash, stdin is the script; install's questions need the terminal. Only the exec
# gets /dev/tty: bash reads a piped script from stdin as it goes, so a plain exec </dev/tty
# would make it read the rest of this script from the terminal.
if [ ! -t 0 ] && (exec </dev/tty) 2>/dev/null; then
    exec ./kit install "$@" </dev/tty
fi
exec ./kit install "$@"
