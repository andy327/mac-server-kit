#!/bin/bash
# demo.sh: the README's demo GIF. Types each command at a steady pace, then runs it.
#
# Recorded from another Mac over SSH, so the server needs nothing installed. <server> is its
# SSH host. Window about 85 columns by 20 rows (stty size).
#
#   brew install asciinema agg
#   ssh -fN -o ControlMaster=yes -o ControlPath=/tmp/demo-cm -o ControlPersist=10m <server>
#   scp -q -o ControlPath=/tmp/demo-cm docs/demo/demo.sh <server>:~/demo.sh
#   asciinema rec demo.cast --overwrite --idle-time-limit 2.5 -c "ssh -q -o ControlPath=/tmp/demo-cm -t <server> 'zsh -lc ~/demo.sh'"
#   ssh -o ControlPath=/tmp/demo-cm -O exit <server>
#
# Scrub the names, check, then render (*.cast stays out of the repo):
#
#   cp demo.cast clean.cast
#   while IFS= read -r w; do [ -n "$w" ] && sed -i '' "s/$w/server/g" clean.cast; done < ~/.config/mac-server-kit/private-words
#   sed -i '' -e "s/$(whoami)/me/g" -e 's/[a-z0-9-]*\.ts\.net/tail1234.ts.net/g' -e '/Shared connection/d' clean.cast
#   grep -nE 'ts\.net|/Users/' clean.cast | grep -v tail1234      # should print nothing
#   agg --font-size 20 --last-frame-duration 4 clean.cast docs/demo/demo.gif
#
# Run ./kit install once by hand first, so the recorded run reports nothing new.

KIT=${KIT:-$HOME/mac-server-kit}

prompt() { printf '\033[1;32m$\033[0m '; }

# type_run <command> [seconds to hold the output]
type_run() {
    sleep 0.8                       # prompt sits there before typing
    for ((i = 0; i < ${#1}; i++)); do printf '%s' "${1:i:1}"; sleep 0.04; done
    sleep 0.6                       # pause before pressing enter
    echo
    eval "$1"
    sleep "${2:-2}"                 # time to read the output
    prompt
}

cd "$KIT" || exit 1
clear
prompt                              # first frame shows a prompt, not a blank screen

type_run './kit check'
type_run './kit install' 2.4        # hold the summary a little longer
type_run 'check-health'
