# shellcheck shell=bash
# ./kit prepare: what to have ready before installing, and fill-in templates for the answers and
# secrets files. Everything comes from the modules (prompts, help and ready files), so it can't
# drift from what ./kit install asks. Read-only except for the template files it's asked to write.
#
# A module's ready file lists what isn't a key, one item per line:
#   group|when|text      group: before (needed for the questions), machine (about this Mac),
#                        after (after the first install: no need to have it yet)

bullet() {          # text -> "  • text", wrapped
    printf '%s\n' "$1" | fold -s -w 86 | sed 's/ *$//' | awk 'NR == 1 { print "  • " $0; next } { print "    " $0 }'
}
sub_lines() {       # text -> indented under a bullet, wrapped and dimmed
    printf '%s\n' "$1" | wrap "      $C_DIM" 84 | sed "s/\$/$C_OFF/"
}

ready_items() {     # group modules... -> one item per line
    local group=$1 m rf g when text
    shift
    for m in "$@"; do
        rf="$(mod_dir "$m")/ready"
        [ -f "$rf" ] || continue
        while IFS='|' read -r g when text <&3; do
            case "$g" in ''|'#'*) continue ;; esac
            [ "$g" = "$group" ] || continue
            when_ok "$when" || continue
            printf '%s\n' "$text"
        done 3<"$rf"
    done
}

# Prompts entries the user answers, for the chosen modules: module|file|key|default|spec|question
asked_entries() {   # file(answers|secrets) modules...
    local want=$1 m pf file key def spec q when
    shift
    for m in "$@"; do
        pf="$(mod_dir "$m")/prompts"
        [ -f "$pf" ] || continue
        while IFS='|' read -r file key def spec q when <&3; do
            [ "$file" = "$want" ] || continue
            when_ok "$when" || continue
            printf '%s|%s|%s|%s|%s|%s\n' "$m" "$file" "$key" "$def" "$spec" "$q"
        done 3<"$pf"
    done
}

key_bullet() {      # module key question
    local about get
    about=$(help_field "$1" "$2" 2 || true)
    get=$(help_field "$1" "$2" 3 || true)
    bullet "$3 ($2)"
    [ -z "$about" ] || sub_lines "$about"
    [ -z "$get" ] || sub_lines "$get"
}

choices_line() {    # modules -> "base install · VPN ... · media server ... · modules ..."
    local m extra=''
    for m in "$@"; do
        [ "$(mod_conf "$m" KIND)" = optional ] || continue
        in_list "$m" "$(media_server_modules)" && continue
        extra=$(list_add "$extra" "$m")
    done
    printf 'base install · VPN: %s · media server: %s · modules: %s' \
        "$(answer VPN_PROVIDER)" "$(answer MEDIA_SERVER)" "${extra:-none}"
}

prepare_list() {    # modules...
    local item m key spec q opt='' after=''
    printf '%sWhat to have ready%s\n' "$C_BLD" "$C_OFF"
    note "For: $(choices_line "$@")"

    section "Have ready for the questions"
    ready_items before "$@" | while IFS= read -r item; do bullet "$item"; done
    while IFS='|' read -r m _ key _ spec q <&3; do
        [ -n "$q" ] || continue
        if [ "$(help_field "$m" "$key" 4 || true)" = after ]; then after="$after$m|$key|$q
"; continue; fi
        case "$spec" in '?'*) opt="$opt$m|$key|$q
"; continue ;; esac
        key_bullet "$m" "$key" "$q"
    done 3< <(asked_entries secrets "$@")
    if [ -n "$opt" ]; then
        printf '\n  Optional (install asks; Enter skips):\n'
        printf '%s' "$opt" | while IFS='|' read -r m key q; do key_bullet "$m" "$key" "$q"; done
    fi
    note "Install also asks a few choices (paths, names, the media server); each has a default."

    section "About this Mac"
    ready_items machine "$@" | while IFS= read -r item; do bullet "$item"; done

    section "After the first install (no need to have these yet)"
    printf '%s' "$after" | while IFS='|' read -r m key q; do [ -n "$key" ] && key_bullet "$m" "$key" "$q"; done
    { ready_items after "$@"; ready_items note "$@"; } | while IFS= read -r item; do bullet "$item"; done

    section "Then"
    info "./kit install"
    note "Or fill in templates first and install without questions:"
    note "  ./kit prepare --answers-template answers.conf --secrets-template secrets.conf"
    note "  ./kit install --answers answers.conf --secrets secrets.conf"
}

comment_block() {   # text -> wrapped "# " lines
    [ -n "$1" ] || return 0
    printf '%s\n' "$1" | wrap '# ' 96
}

template_target() { # file: refuse to overwrite
    [ -e "$1" ] && die "$1 already exists; the kit won't overwrite it. Pick another name or remove it."
    return 0
}

secrets_template() {    # file modules...
    local file=$1 m key spec q about get after
    shift
    template_target "$file"
    {
        echo "# mac-server-kit secrets for: $(choices_line "$@")"
        echo "# Fill in the values, then: ./kit install --secrets <this file>"
        echo "# Keep this file private, and delete it once installed: install copies it to"
        echo "# ~/server/secrets.conf with private permissions."
        echo "#"
        echo "# Required keys are listed as KEY=\"\". Optional ones are commented out: leave them that"
        echo "# way to be asked during install, or uncomment one and leave it empty to skip it for good."
        echo "# The kit generates every other secret it needs (app passwords, API keys) by itself."
        asked_entries secrets "$@" | while IFS='|' read -r m _ key _ spec q; do
            [ -n "$q" ] || continue
            about=$(help_field "$m" "$key" 2 || true)
            get=$(help_field "$m" "$key" 3 || true)
            after=$(help_field "$m" "$key" 4 || true)
            echo
            comment_block "$q."
            comment_block "$about"
            comment_block "$get"
            if [ "$after" = after ]; then
                echo "# Needed after the first install; leave it commented out for now."
                echo "#$key=\"\""
            else
                case "$spec" in '?'*) echo "#$key=\"\"" ;; *) echo "$key=\"\"" ;; esac
            fi
        done
    } | (umask 077; cat >"$file") || die "could not write $file"
    chmod 600 "$file"
}

answers_template() {    # file modules...
    local file=$1 m key def spec q about val extra=''
    shift
    template_target "$file"
    for m in "$@"; do
        [ "$(mod_conf "$m" KIND)" = optional ] || continue
        in_list "$m" "$(media_server_modules)" && continue
        extra=$(list_add "$extra" "$m")
    done
    {
        echo "# mac-server-kit answers for: $(choices_line "$@")"
        echo "# Change what you want, then: ./kit install --answers <this file> --secrets <secrets file>"
        echo "# With every value here, install asks no questions. \"~/\" means the home folder of the"
        echo "# Mac being installed. A key left empty (KEY=) means none."
        asked_entries answers "$@" | while IFS='|' read -r m _ key def spec q; do
            [ -n "$q" ] || continue
            val=$(answer "$key")
            case "$def" in '~'*) [ "$val" = "$(expand_default "$def")" ] && val=$def ;; esac
            val=$(tilde "$val")
            echo
            comment_block "$q"
            comment_block "$(help_field "$m" "$key" 2 || true)"
            echo "$key=$val"
        done
        echo
        echo "# Optional modules (./kit add <module> later does the same)."
        echo "MODULES=$extra"
        echo
        echo "# ---- Advanced: never asked; the defaults below apply. Uncomment to change one."
        asked_entries answers "$@" | while IFS='|' read -r m _ key def spec q; do
            [ -z "$q" ] || continue
            echo
            comment_block "$(help_field "$m" "$key" 2 || true)"
            echo "#$key=$def"
        done
    } >"$file" || die "could not write $file"
}
