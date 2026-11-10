# shellcheck shell=bash
# ./kit install --plan (and ./kit add|disable ... --plan): a preview of what an install would do,
# changing nothing. Sourced by ./kit after common.sh.
#
# The plan runs the install's own steps with KIT_PLAN=1, and four things keep it from changing
# anything:
#   1. Generated files are rendered into PLAN_DIR (plan_out maps ~/server/x to $PLAN_DIR/root/...)
#      and diffed against the live ones. answers.conf, secrets.conf and generated-secrets.conf are
#      copies in PLAN_DIR, as --answers drafts are.
#   2. Guards: dk, klaunchctl, kbrew, ksudo, kpmset, kdefaults and kcurl run only read-only calls,
#      and write_generated, kv_append, seed_file, lock_set, mark_write and make_dir never write
#      outside PLAN_DIR. A refused call stops the step and is reported as a kit bug.
#   3. Hooks: install hooks stop after their "already installed" check; wire hooks run with every
#      API call that isn't a GET answered by "would" (api_call sends nothing); flows that need an
#      answer from a POST say what they would do in one line.
#   4. macOS's sandbox-exec, when it works here: the plan re-runs itself in a sandbox that denies
#      file writes outside PLAN_DIR (and /dev).
# Output: "+" the install would do this, "⚠" check this before installing, "?" can't tell without
# running it. A summary box ends it.

KIT_PLAN=${KIT_PLAN:-0}
PLAN_DIR=${KIT_PLAN_DIR:-}

in_plan() { [ "$KIT_PLAN" = 1 ]; }

# ---------------------------------------------------------------- entering a plan

plan_sandbox_profile() {    # dir -> a sandbox-exec profile that allows writes only there and /dev
    local p extra
    # bash 3.2 makes its here-documents' temporary files in /tmp, whatever TMPDIR says
    p='(version 1)(allow default)(deny file-write*)(allow file-write* (subpath "/dev") (subpath "/private/tmp") (subpath "'$1'")'
    # Tests: their fakes keep logs and state outside the plan's folder (colon-separated paths)
    if [ -n "${KIT_PLAN_WRITABLE:-}" ]; then
        for extra in $(printf '%s' "$KIT_PLAN_WRITABLE" | tr ':' ' '); do
            # The sandbox sees paths with symlinks followed (/var is /private/var)
            case "$extra" in /var/*|/tmp/*|/etc/*) extra=/private$extra ;; esac
            p="$p (subpath \"$extra\")"
        done
    fi
    printf '%s)' "$p"
}

# Called by ./kit before the command runs: makes PLAN_DIR and, when sandbox-exec works, runs the
# kit again inside the sandbox (KIT_PLAN_SANDBOX=on there). KIT_PLAN_SANDBOX=off skips it.
plan_enter() {      # the kit's arguments
    local dir
    if [ -z "$PLAN_DIR" ]; then
        dir=$(cd "${TMPDIR:-/tmp}" && pwd -P)
        PLAN_DIR=$(mktemp -d "$dir/kit-plan.XXXXXX") || die "could not make a temporary folder for the plan"
    fi
    export KIT_PLAN=1 KIT_PLAN_DIR=$PLAN_DIR
    mkdir -p "$PLAN_DIR/tmp" "$PLAN_DIR/root" "$PLAN_DIR/config"
    export TMPDIR=$PLAN_DIR/tmp
    # One try for an app that isn't answering, not a wait
    export KIT_JELLYFIN_WAIT=1 KIT_OLLAMA_WAIT=1
    # Nothing is asked: no prompts, no sudo, no Homarr widget questions
    export KIT_INTERACTIVE=0
    KIT_PLAN=1
    case "${KIT_PLAN_SANDBOX:-}" in
        on) PLAN_SANDBOX=on ;;
        off) PLAN_SANDBOX=off ;;
        *)
            PLAN_SANDBOX=off
            if [ -x /usr/bin/sandbox-exec ] && /usr/bin/sandbox-exec -p "$(plan_sandbox_profile "$PLAN_DIR")" /usr/bin/true 2>/dev/null; then
                export KIT_PLAN_SANDBOX=on
                exec /usr/bin/sandbox-exec -p "$(plan_sandbox_profile "$PLAN_DIR")" /bin/bash "$KIT_DIR/kit" "$@"
            fi ;;
    esac
    # shellcheck disable=SC2064  # the folder's name now
    trap "rm -rf '$PLAN_DIR'" EXIT
}
PLAN_SANDBOX=off

# ---------------------------------------------------------------- output and records

plan_record() { [ -n "$PLAN_DIR" ] && printf '%s\n' "$2" >>"$PLAN_DIR/$1"; return 0; }   # file line
plan_add()  { printf '  %s+%s %s\n' "$C_GRN" "$C_OFF" "$*"; plan_record changes "$*"; }
plan_flag() { printf '  %s⚠%s %s\n' "$C_YEL" "$C_OFF" "$*"; plan_record flags "$*"; }
plan_cant() { printf '  %s? can'"'"'t tell: %s%s\n' "$C_DIM" "$*" "$C_OFF"; plan_record cant "$*"; }
plan_cant_once() {  # key text: said once a run (hooks run in subshells, so a file remembers)
    [ -e "$PLAN_DIR/once-$1" ] && return 0
    : >"$PLAN_DIR/once-$1"
    plan_cant "$2"
}

plan_refuse() {     # what
    plan_record refused "$*"
    printf '%skit:%s plan refused %s. A plan never changes anything, so this is a kit bug; please report it.\n' \
        "$C_RED" "$C_OFF" "$*" >&2
    exit 1
}

plan_inside() { case "$1" in "$PLAN_DIR"/*) return 0 ;; esac; return 1; }
plan_guard() { in_plan || return 0; plan_inside "$1" || plan_refuse "to write $1"; }

# path -> where an install writes it: the path itself, or in a plan its copy under PLAN_DIR
plan_out() {
    if in_plan; then
        mkdir -p "$PLAN_DIR/root$(dirname "$1")" && printf '%s' "$PLAN_DIR/root$1"
    else
        printf '%s' "$1"
    fi
}
plan_live() { printf '%s' "${1#"$PLAN_DIR/root"}"; }     # a plan_out path -> the live one

# A folder the install makes (mkdir -p). In a plan, a missing one is listed (quiet: only recorded).
make_dir() {        # path [quiet]
    if in_plan; then
        [ -d "$1" ] && return 0
        grep -qxF -- "$1" "$PLAN_DIR/folders" 2>/dev/null && return 0
        plan_record folders "$1"
        [ "${2:-}" = quiet ] || plan_add "Make folder $(tilde "$1")"
        return 0
    fi
    mkdir -p "$1" || die "could not create $1"
}

# A mark file in an app's data (kit-checked, kit-admin): written by the wiring, never by a plan
mark_write() {      # file text
    if in_plan; then plan_add "Write $(tilde "$1")"; return 0; fi
    printf '%s\n' "$2" >"$1"
}

# ---------------------------------------------------------------- command guards

plan_dk_ok() {      # docker arguments -> 0 when read-only
    case "${1:-}" in
        ps|inspect|version|info) return 0 ;;
        image|context) [ "${2:-}" = inspect ]; return ;;
        compose)
            shift
            while [ $# -gt 0 ]; do
                case "$1" in
                    -f|--file|-p|--project-name|--project-directory|--env-file|--profile) shift 2 ;;
                    -*) shift ;;
                    config|ps|version|ls) return 0 ;;
                    *) return 1 ;;
                esac
            done
            return 1 ;;
    esac
    return 1
}

plan_curl_ok() {    # curl arguments -> 0 for a GET or HEAD that writes only into PLAN_DIR
    while [ $# -gt 0 ]; do
        case "$1" in
            -X|--request) case "${2:-}" in GET|HEAD) ;; *) return 1 ;; esac; shift 2 ;;
            -d|--data|--data-*|-F|--form|--form-*|-T|--upload-file|--json) return 1 ;;
            -o|--output|-c|--cookie-jar|-D|--dump-header)
                case "${2:-}" in /dev/null|-) ;; *) plan_inside "${2:-}" || return 1 ;; esac
                shift 2 ;;
            *) shift ;;
        esac
    done
    return 0
}

# Wrap the kit's command functions (common.sh, api.sh, runtime.sh, native.sh, mac.sh) with the
# guards. Called once the libraries are loaded, only in a plan.
# shellcheck disable=SC2329  # they replace the libraries' functions of the same names
plan_guards() {
    dk() { plan_dk_ok "$@" || plan_refuse "docker $*"; "${KIT_DOCKER:-docker}" "$@"; }
    kcurl() { plan_curl_ok "$@" || plan_refuse "curl $*"; "${KIT_CURL:-curl}" "$@"; }
    klaunchctl() { case "${1:-}" in print|list) ;; *) plan_refuse "launchctl $*" ;; esac; "${KIT_LAUNCHCTL:-launchctl}" "$@"; }
    kbrew() { [ "${1:-}" = --prefix ] || plan_refuse "brew $*"; "${KIT_BREW:-brew}" "$@"; }
    ksudo() { plan_refuse "sudo $*"; }
    kpmset() { [ "${1:-}" = -g ] || plan_refuse "pmset $*"; "${KIT_PMSET:-pmset}" "$@"; }
    kdefaults() { [ "${1:-}" = read ] || plan_refuse "defaults $*"; "${KIT_DEFAULTS:-defaults}" "$@"; }
    # What the install would make or change prints as "+", and counts for the summary
    ok() { plan_add "$*"; }
}

# ---------------------------------------------------------------- answers and secrets

PLAN_LIVE_ANSWERS='' PLAN_LIVE_SECRETS='' PLAN_LIVE_GEN=''

# Copies of the three files, which the install's prompts append to in place of the real ones
plan_config_copy() {
    local v live copy header
    for v in ANSWERS SECRETS GEN_SECRETS; do
        live=${!v}
        copy=$PLAN_DIR/config/$(basename "$live")
        case "$v" in
            ANSWERS) PLAN_LIVE_ANSWERS=$live header=$ANSWERS_HEADER ;;
            SECRETS) PLAN_LIVE_SECRETS=$live header=$SECRETS_HEADER ;;
            *) PLAN_LIVE_GEN=$live header=$GEN_HEADER ;;
        esac
        if [ -f "$live" ]; then cp "$live" "$copy"; else printf '%s\n\n' "$header" >"$copy"; fi
        printf -v "$v" '%s' "$copy"
    done
}

plan_added_lines() {    # live copy -> the lines the copy has that the live file doesn't (appended)
    if [ -f "$1" ]; then diff "$1" "$2" | sed -n 's/^> //p'; else grep -v '^#' "$2" | sed '/^$/d'; fi
}

# A new generated secret that an app's existing data was made with another value of. "data":
# a database's password or an encryption key (the app can't open its data). "session": a key
# that signs sessions and tokens (everyone is signed out, and apps' tokens stop working).
plan_secret_risk() {    # key -> data | session, or 1 for neither
    case "$1" in
        *DB_PASSWORD|*DB_ROOT_PASSWORD|*MEILI_KEY|*ENCRYPTION_KEY) echo data ;;
        *JWT_SECRET|*COOKIE_SECRET|*AUTH_SECRET|*SESSION_SECRET|*APP_SECRET|*_SECRET_KEY) echo session ;;
        *) return 1 ;;
    esac
}

plan_report_config() {  # modules...
    local line key file def opt m p data risk
    section "Answers and secrets (would change)"
    [ -f "$PLAN_LIVE_ANSWERS" ] || plan_add "Create $(tilde "$PLAN_LIVE_ANSWERS")"
    [ -f "$PLAN_LIVE_SECRETS" ] || plan_add "Create $(tilde "$PLAN_LIVE_SECRETS") (private)"
    [ -f "$PLAN_LIVE_GEN" ] || plan_add "Create $(tilde "$PLAN_LIVE_GEN") (private)"
    case "$ANSWER_OVERRIDES" in *MODULES=*)
        plan_add "answers.conf: MODULES=$(answer MODULES || true) (the ./kit add or disable without --plan writes it)" ;;
    esac
    if [ -f "$PLAN_DIR/asked" ]; then
        while IFS='|' read -r file key def opt; do
            if [ "$file" = secrets ]; then
                plan_add "Ask for $key (secrets.conf)${opt:+, or Enter to skip}"
            else
                plan_add "Ask for $key (answers.conf)${def:+, default $def}${opt:+, or Enter to skip}"
            fi
        done <"$PLAN_DIR/asked"
    fi
    # Lines added by an --answers or --secrets file (the asked ones are listed above)
    plan_added_lines "$PLAN_LIVE_ANSWERS" "$ANSWERS" | while IFS= read -r line; do
        [ -n "$line" ] || continue
        grep -q "^answers|${line%%=*}|" "$PLAN_DIR/asked" 2>/dev/null && continue
        plan_add "answers.conf: $line"
    done
    plan_added_lines "$PLAN_LIVE_SECRETS" "$SECRETS" | while IFS= read -r line; do
        [ -n "$line" ] || continue
        grep -q "^secrets|${line%%=*}|" "$PLAN_DIR/asked" 2>/dev/null && continue
        plan_add "secrets.conf: ${line%%=*} (value not shown)"
    done
    plan_added_lines "$PLAN_LIVE_GEN" "$GEN_SECRETS" | while IFS= read -r line; do
        key=${line%%=*}
        [ -n "$line" ] || continue
        plan_add "generated-secrets.conf: $key (made at random)"
        risk=$(plan_secret_risk "$key") || continue
        for m in "$@"; do
            grep -q "^gen|$key|" "$(mod_dir "$m")/prompts" 2>/dev/null || continue
            p=$(mod_conf "$m" PROJECT)
            [ -n "$p" ] || continue
            data=$(project_appdata "$p")
            if [ -d "$data" ] && [ -n "$(ls -A "$data" 2>/dev/null)" ]; then
                if [ "$risk" = data ]; then
                    plan_flag "$key is new, but $(tilde "$data") already has data, which was made with another value: the app couldn't open it. Put the old value in $(tilde "$PLAN_LIVE_GEN") as $key first."
                else
                    plan_flag "$key is new, but $(tilde "$data") already has data: with a new value, everyone signed in is signed out, and tokens made with the old one (apps, API tokens) stop working. To keep them, put the old value in $(tilde "$PLAN_LIVE_GEN") as $key first."
                fi
            fi
        done
    done
    plan_values_file
}

# Every secret's value, for masking diffs (kept in PLAN_DIR, removed with it)
plan_values_file() {
    local f k
    : >"$PLAN_DIR/values"
    for f in "$SECRETS" "$GEN_SECRETS" "$PLAN_LIVE_SECRETS" "$PLAN_LIVE_GEN"; do
        [ -f "$f" ] || continue
        for k in $(kv_keys "$f"); do kv_get "$f" "$k" >>"$PLAN_DIR/values"; printf '\n' >>"$PLAN_DIR/values"; done
    done
}

# ---------------------------------------------------------------- generated files

# A diff with secrets hidden: a changed line whose key looks secret or whose value holds one of
# the secrets shows as KEY=•••, and a secret anywhere else as •••
plan_mask() {
    awk -v vf="$PLAN_DIR/values" '
        BEGIN { while ((getline v < vf) > 0) if (length(v) >= 6) s[++n] = v }
        /^[-+ ][A-Za-z_][A-Za-z0-9_]*=/ {
            key = substr($0, 2); sub(/=.*/, "", key)
            m = (toupper(key) ~ /PASSW|SECRET|_KEY$|TOKEN|AUTHKEY|API_KEY/)
            for (i = 1; i <= n && !m; i++) if (index($0, s[i])) m = 1
            if (m) { print substr($0, 1, 1) key "=•••"; next }
        }
        { line = $0
          for (i = 1; i <= n; i++) while ((p = index(line, s[i])) > 0) line = substr(line, 1, p - 1) "•••" substr(line, p + length(s[i]))
          print line }'
}

PLAN_SAME=''
plan_diff_file() {      # live new label: says how new differs from live
    local live=$1 new=$2 label=$3
    if [ ! -f "$live" ]; then
        plan_add "New $label"
    elif cmp -s "$live" "$new"; then
        PLAN_SAME="${PLAN_SAME:+$PLAN_SAME, }$label"
    else
        plan_add "Change $label:"
        diff -u "$live" "$new" | tail -n +3 | grep -v '^@@' | grep '^[-+]' | plan_mask | sed "s/^/      $C_DIM/; s/\$/$C_OFF/"
    fi
}
plan_same_report() {
    [ -z "$PLAN_SAME" ] || note "Unchanged: $PLAN_SAME"
    PLAN_SAME=''
}

# The project's generated files (rendered by generate_projects into PLAN_DIR) against the live
# ones, and the images the install would pull
plan_report_projects() {    # modules...
    local p live new f name svc ref track line
    for p in $(projects_of "$@"); do
        live=$(project_dir "$p")
        new=$PLAN_DIR/root$live
        [ -d "$new" ] || continue
        printf '  %s%s%s (%s)\n' "$C_BLD" "$p" "$C_OFF" "$(tilde "$live")"
        plan_diff_file "$live/.env" "$new/.env" .env
        [ -f "$new/project.yml" ] && plan_diff_file "$live/project.yml" "$new/project.yml" project.yml
        for f in "$new"/compose.d/*.yml; do
            [ -f "$f" ] || continue
            name=compose.d/${f##*/}
            plan_diff_file "$live/$name" "$f" "$name"
        done
        for f in "$live"/compose.d/*.yml; do
            [ -f "$f" ] || continue
            [ -f "$new/compose.d/${f##*/}" ] || plan_add "Remove compose.d/${f##*/} (no enabled module has it)"
        done
        for f in "$new"/tailscale/*/serve.json; do
            [ -f "$f" ] || continue
            name=${f#"$new"/}
            plan_diff_file "$live/$name" "$f" "$name"
        done
        plan_same_report
        [ -f "$PLAN_DIR/pulls" ] || continue
        while IFS='|' read -r line svc ref track; do
            [ "$line" = "$p" ] || continue
            plan_add "Pull $ref for $svc and pin it in images.lock${track:+ (newest release of $track)}"
        done <"$PLAN_DIR/pulls"
    done
}

# ---------------------------------------------------------------- containers
#
# What `docker compose up` would do, from Compose's own config hashes: a container whose
# com.docker.compose.config-hash label differs from `docker compose config --hash` is recreated.
# Read-only docker calls only (compose config, ps, inspect, image inspect).

# docker compose config's normalized output -> "svc|kind|a|b" lines: name|container_name,
# mount|source|target|type, port|published, net|<service whose network it shares>, and
# "<volume key>|volname|<its Docker name>" for the top-level named volumes
plan_parse_config() {
    awk '
        function flush() { if (src != "" || tgt != "") print msvc "|mount|" src "|" tgt "|" typ; src = ""; tgt = ""; typ = "" }
        /^volumes:/ { flush(); s = 0; tv = 1; next }
        tv && /^  [^ ]/ { vk = $1; sub(/:$/, "", vk); next }
        tv && /^    name: / { n = $0; sub(/^    name: */, "", n); gsub(/"/, "", n); print vk "|volname|" n; next }
        /^services:/ { s = 1; tv = 0; next }
        /^[^ ]/ { flush(); s = 0; tv = 0; next }
        !s { next }
        /^  [^ ]/ { flush(); svc = $1; sub(/:$/, "", svc); sect = ""; next }
        /^    [^ ]/ {
            flush(); k = $1; sub(/:$/, "", k); sect = k
            if (k == "container_name") { x = $0; sub(/^    container_name: */, "", x); print svc "|name|" x }
            if (k == "network_mode") { x = $0; sub(/^    network_mode: */, "", x); gsub(/"/, "", x)
                if (x ~ /^service:/) { sub(/^service:/, "", x); print svc "|net|" x } }
            next }
        sect == "volumes" && /^      - / { flush(); msvc = svc }
        sect == "volumes" && /^      [- ] (source|target|type): / {
            x = $0; sub(/^      [- ] (source|target|type): */, "", x)
            if ($0 ~ /source: /) src = x; else if ($0 ~ /target: /) tgt = x; else typ = x }
        sect == "ports" && /published: / { v = $0; sub(/.*published: */, "", v); gsub(/"/, "", v); print svc "|port|" v }
        END { flush() }
    '
}

PLAN_PS_FORMAT='{{.Names}}|{{.Label "com.docker.compose.project"}}|{{.Label "com.docker.compose.service"}}|{{.Label "com.docker.compose.config-hash"}}|{{.Image}}|{{.State}}|{{.Ports}}'

plan_container() {      # name -> its ps line (name|project|service|hash|image|state|ports)
    awk -F'|' -v n="$1" '$1 == n { print; exit }' "$PLAN_DIR/containers" 2>/dev/null
}

plan_project_running() {    # project -> 0 when one of its containers runs
    awk -F'|' -v p="$1" '$2 == p && $6 == "running" { f = 1 } END { exit !f }' "$PLAN_DIR/containers" 2>/dev/null
}

# A media server the kit runs natively, already running in a container: the kit's own would start
# fresh beside it, and scan the whole library again
plan_native_in_docker() {   # modules...
    local m pat name image
    for m in "$@"; do
        case "$m" in
            plex) pat='plex' ;;
            jellyfin) pat='jellyfin/jellyfin|linuxserver/jellyfin|/jellyfin:' ;;
            *) continue ;;
        esac
        while IFS='|' read -r name _ _ _ image _; do
            [ -n "$name" ] || continue
            case "$name" in *-proxy) continue ;; esac
            printf '%s' "$image" | grep -qiE "$pat" || continue
            printf '%s' "$image" | grep -qi socat && continue
            plan_flag "$m runs in a container here ($name, $image). The kit runs $m as an app on this Mac instead, which starts fresh (its own setup and a full library scan) unless you move its data over first."
        done <"$PLAN_DIR/containers"
    done
}

# Media folders the /data move expects the old mounts to be (media-stack's wire hook moves the
# apps' paths from /tv, /movies and /downloads to /data/..., without moving files)
PLAN_OLD_MEDIA='/tv|TV Shows
/movies|Movies
/downloads|Downloads'

plan_mounts_compare() {     # project svc container-name
    local p=$1 svc=$2 cname=$3 old src tgt typ osrc otyp oname vname media want sub
    # type|volume name|source|destination per mount
    old=$(dk inspect --format '{{range .Mounts}}{{.Type}}|{{.Name}}|{{.Source}}|{{.Destination}}{{println}}{{end}}' "$cname" 2>/dev/null | sed '/^$/d')
    while IFS='|' read -r src tgt typ; do
        [ -n "$tgt" ] || continue
        IFS='|' read -r otyp oname osrc <<MOUNT
$(printf '%s\n' "$old" | awk -F'|' -v t="$tgt" '$4 == t { print $1 "|" $2 "|" $3; exit }')
MOUNT
        [ -n "$osrc" ] || continue
        if [ "$typ" = volume ]; then
            # A named volume: Compose names it <project>_<key> unless the file names it
            vname=$(awk -F'|' -v k="$src" '$1 == k && $2 == "volname" { print $3; exit }' "$PLAN_DIR/mounts")
            vname=${vname:-${p}_$src}
            [ "$otyp" = volume ] && [ "$oname" = "$vname" ] && continue
            if [ "$otyp" = volume ]; then
                plan_flag "$svc: $tgt would come from the Docker volume $vname instead of the volume $oname: $svc starts fresh unless you copy its data over first"
            else
                plan_flag "$svc: $tgt would come from the Docker volume $vname instead of $(tilde "$osrc"): $svc starts fresh unless you copy its data over first"
            fi
            continue
        fi
        [ "${osrc%/}" = "${src%/}" ] && continue
        if [ "$otyp" = volume ]; then
            plan_flag "$svc: $tgt would come from $(tilde "$src") instead of the Docker volume $oname: copy the volume's data there first, or $svc starts fresh"
            continue
        fi
        if [ -e "$src" ] && [ -n "$(ls -A "$src" 2>/dev/null)" ]; then
            plan_flag "$svc: $tgt would come from $(tilde "$src") instead of $(tilde "$osrc") (both hold data; the app sees the new one)"
        else
            plan_flag "$svc: $tgt would come from $(tilde "$src"), which is empty, instead of $(tilde "$osrc"): $svc starts fresh unless you move its data there first"
        fi
    done <<EOF
$(awk -F'|' -v s="$svc" '$1 == s && $2 == "mount" { print $3 "|" $4 "|" $5 }' "$PLAN_DIR/mounts")
EOF
    [ "$p" = media-stack ] || return 0
    media=$(resolve_path "$(answer MEDIA_ROOT)")
    while IFS='|' read -r tgt sub; do
        osrc=$(printf '%s\n' "$old" | awk -F'|' -v t="$tgt" '$4 == t { print $3; exit }')
        [ -n "$osrc" ] || continue
        want=$media/$sub
        if [ "${osrc%/}" = "$want" ]; then
            note "$svc: $tgt is $(tilde "$want") now, which /data/$sub is too (the apps' paths move, the files stay)"
        else
            plan_flag "$svc: $tgt comes from $(tilde "$osrc") now, but the install moves the apps' $tgt paths to /data/$sub, which is $(tilde "$want"). Their records would point at folders that don't hold the files (everything shows missing, and may download again). Make MEDIA_ROOT's layout match first."
        fi
    done <<EOF
$PLAN_OLD_MEDIA
EOF
}

# Whether the image the install would pull and pin is the one a container runs now
plan_image_compare() {      # svc container-name repo:tag
    local svc=$1 cname=$2 ref=$3 id have want
    id=$(dk inspect --format '{{.Image}}' "$cname" 2>/dev/null)
    have=$(dk image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "${id:-$cname}" 2>/dev/null |
        awk -v r="${ref%:*}@" 'index($0, r) == 1 { sub(/.*@/, ""); print; exit }')
    want=$(registry_digest "${ref%:*}" "${ref##*:}" 2>/dev/null)
    if [ -z "$want" ]; then
        plan_cant "whether $ref is newer than what $svc runs now (the registry didn't answer)"
    elif [ -z "$have" ]; then
        plan_cant "which version $svc runs now, to compare with $ref"
    elif [ "$have" = "$want" ]; then
        note "$svc: $ref is the image it runs now"
    else
        plan_flag "$svc: $ref is newer than the image it runs now; it starts on the new version (an app may update its database one way: back it up first)"
    fi
}

# A service on another's network (network_mode: service:X): Compose hashes it with the network
# resolved to that container (container:<id>), so its label never matches config --hash. Hash it
# the same way, with an override naming X's current container; when X has no container yet the
# hash stays as it is (the service is made new anyway).
plan_net_hashes() {     # project live new hashes files... -> hashes, with those replaced
    local p=$1 live=$2 new=$3 hashes=$4 svc parent pname id over h
    shift 4
    while IFS='|' read -r svc _ parent; do
        [ -n "$svc" ] || continue
        pname=$(awk -F'|' -v s="$parent" '$1 == s && $2 == "name" { print $3; exit }' "$PLAN_DIR/mounts")
        id=$(dk inspect --format '{{.Id}}' "${pname:-$p-$parent-1}" 2>/dev/null) || continue
        [ -n "$id" ] || continue
        over=$PLAN_DIR/net-$p-$svc.yml
        printf 'services:\n  %s:\n    network_mode: "container:%s"\n' "$svc" "$id" >"$over"
        h=$(dk compose -p "$p" --project-directory "$live" --env-file "$new/.env" "$@" -f "$over" config --hash "$svc" 2>/dev/null |
            awk -v s="$svc" '$1 == s { print $2; exit }')
        [ -n "$h" ] || continue
        hashes=$(printf '%s\n' "$hashes" | awk -v s="$svc" -v h="$h" '$1 == s { $2 = h } { print }')
    done <<NET
$(awk -F'|' '$2 == "net"' "$PLAN_DIR/mounts")
NET
    printf '%s\n' "$hashes"
}

plan_start() {      # modules...
    local p live new files f entry cfg hashes svc hash cname row rproj rhash rimg reason pull port holder same orphan ver net changed
    if ! dk info >/dev/null 2>&1; then
        plan_cant "Docker isn't answering, so the plan can't compare containers"
        return 0
    fi
    dk ps -a --format "$PLAN_PS_FORMAT" >"$PLAN_DIR/containers" 2>/dev/null || : >"$PLAN_DIR/containers"
    plan_native_in_docker "$@"
    for p in $(projects_of "$@"); do
        live=$(project_dir "$p")
        new=$PLAN_DIR/root$live
        [ -f "$new/compose.d/zz-images.yml" ] || continue
        printf '  %s%s%s\n' "$C_BLD" "$p" "$C_OFF"
        files=()
        for entry in $(sed -n 's/^COMPOSE_FILE=//p' "$new/.env" | tr -d "'" | tr ':' ' '); do
            if [ -f "$new/$entry" ]; then files+=(-f "$new/$entry"); else files+=(-f "$live/$entry"); fi
        done
        if ! cfg=$(dk compose -p "$p" --project-directory "$live" --env-file "$new/.env" "${files[@]}" config 2>&1) ||
            ! hashes=$(dk compose -p "$p" --project-directory "$live" --env-file "$new/.env" "${files[@]}" config --hash '*' 2>/dev/null); then
            plan_cant "what changes in $p: docker compose config failed ($(printf '%s' "$cfg" | tail -n 1))"
            continue
        fi
        printf '%s\n' "$cfg" | plan_parse_config >"$PLAN_DIR/mounts"
        hashes=$(plan_net_hashes "$p" "$live" "$new" "$hashes" "${files[@]}")
        same=''; changed=' '
        while read -r svc hash; do
            [ -n "$svc" ] || continue
            cname=$(awk -F'|' -v s="$svc" '$1 == s && $2 == "name" { print $3; exit }' "$PLAN_DIR/mounts")
            [ -n "$cname" ] || cname=$p-$svc-1
            pull=$(awk -F'|' -v p="$p" -v s="$svc" '$1 == p && $2 == s { print $3; exit }' "$PLAN_DIR/pulls" 2>/dev/null)
            row=$(plan_container "$cname")
            net=$(awk -F'|' -v s="$svc" '$1 == s && $2 == "net" { print $3; exit }' "$PLAN_DIR/mounts")
            if [ -z "$row" ]; then
                plan_add "Create $svc${pull:+ ($pull)}"
                changed="$changed$svc "
            else
                IFS='|' read -r _ rproj _ rhash rimg _ <<EOF
$row
EOF
                if [ "$rproj" != "$p" ]; then
                    plan_flag "$svc: a container named $cname already exists ($([ -n "$rproj" ] && printf 'compose project %s' "$rproj" || printf 'not made by Compose'), $rimg). The install stops at Start until it's gone: check where its data is, then docker rm -f $cname."
                    plan_mounts_compare "$p" "$svc" "$cname"
                    [ -z "$pull" ] || plan_image_compare "$svc" "$cname" "$pull"
                elif [ "$rhash" = "$hash" ] && { [ -z "$net" ] || [ "${changed#* "$net" }" = "$changed" ]; }; then
                    same="${same:+$same }$svc"
                    continue
                else
                    reason='its settings changed'
                    [ "$rhash" != "$hash" ] || reason="it shares $net's network, which is made again"
                    [ -z "$pull" ] || reason="pinned to $pull"
                    plan_add "Recreate $svc ($reason; its data stays)"
                    changed="$changed$svc "
                    plan_mounts_compare "$p" "$svc" "$cname"
                    [ -z "$pull" ] || plan_image_compare "$svc" "$cname" "$pull"
                fi
                if [ "$svc" = romm ]; then
                    ver=$(dk inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' "$cname" 2>/dev/null)
                    case "$ver" in
                        5|5.*) ;;
                        '') plan_cant "which RomM version runs now (the kit runs RomM 5; an older one's database changes one way)" ;;
                        *) plan_flag "romm: RomM $ver runs now, and the kit runs RomM 5: its database is upgraded one way. Back up $(tilde "$(project_appdata romm)") (and the old database) first." ;;
                    esac
                fi
            fi
            # Host ports another container holds
            # shellcheck disable=SC2013  # port numbers, one word each
            for port in $(awk -F'|' -v s="$svc" '$1 == s && $2 == "port" { print $3 }' "$PLAN_DIR/mounts"); do
                holder=$(awk -F'|' -v n="$cname" -v pt=":$port->" '$1 != n && index($7, pt) { print $1; exit }' "$PLAN_DIR/containers")
                [ -z "$holder" ] || plan_flag "$svc: port $port is taken by the container $holder; $svc can't start until that one stops"
            done
            # A new Tailscale machine: its state folder is new
            case "$svc" in *-tailscale)
                f=$(awk -F'|' -v s="$svc" '$1 == s && $2 == "mount" && $4 == "/var/lib/tailscale" { print $3; exit }' "$PLAN_DIR/mounts")
                if [ -n "$f" ] && { [ ! -d "$f" ] || [ -z "$(ls -A "$f" 2>/dev/null)" ]; }; then
                    plan_add "${svc%-tailscale}: a new machine in your tailnet (if its name is taken, Tailscale adds -1)"
                fi ;;
            esac
        done <<EOF
$hashes
EOF
        [ -z "$same" ] || note "Unchanged: $same"
        orphan=$(awk -F'|' -v p="$p" '$2 == p { print $3 }' "$PLAN_DIR/containers" | while read -r svc; do
            printf '%s\n' "$hashes" | awk -v s="$svc" '$1 == s { f = 1 } END { exit f }' && printf '%s ' "$svc"; done)
        [ -z "$orphan" ] || plan_add "Remove ${orphan% } (no enabled module has it; its data stays)"
    done
}

# ---------------------------------------------------------------- connecting the apps

plan_wire() {       # modules...
    local m p
    for m in "$@"; do
        [ -f "$(mod_dir "$m")/hooks/wire" ] || continue
        p=$(mod_conf "$m" PROJECT)
        if [ -n "$p" ] && ! plan_project_running "$p"; then
            plan_cant "$m's settings: $p isn't running yet, so the plan can't read them (the install sets them after the start)"
            continue
        fi
        run_hooks wire "$m"
    done
}

# ---------------------------------------------------------------- summary

plan_count() { [ -f "$PLAN_DIR/$1" ] && grep -c . "$PLAN_DIR/$1" || echo 0; }

plan_summary() {
    local c f q w head line
    c=$(plan_count changes) f=$(plan_count flags) q=$(plan_count cant)
    w=0
    [ -z "${KIT_RUN_LOG:-}" ] || w=$(grep -c '^warn|' "$KIT_RUN_LOG" 2>/dev/null) || w=0
    head="${C_BLD}Plan${C_OFF} · $c to do"
    if [ "$f" -eq 0 ]; then head="$head · ${C_GRN}nothing to check first${C_OFF}"; else head="$head · ${C_YEL}$f to check first (⚠)${C_OFF}"; fi
    [ "$q" -eq 0 ] || head="$head · $q can't tell"
    [ "$w" -eq 0 ] || head="$head · $w warnings"
    printf '\n%s╭%s %s\n' "$C_DIM" "$C_OFF" "$head"
    if [ "$f" -gt 0 ]; then
        while IFS= read -r line; do
            printf '%s\n' "$line" | fold -s -w 84 | sed 's/ *$//' |
                awk -v d="$C_DIM" -v o="$C_OFF" -v y="$C_YEL" 'NR == 1 { print d "│" o " " y "⚠" o " " $0; next } { print d "│" o "   " $0 }'
        done <"$PLAN_DIR/flags"
    fi
    if [ -s "$PLAN_DIR/refused" ]; then
        printf '%s╰%s %sThe plan stopped a step that would have changed something (above): a kit bug. Nothing was changed.%s\n' \
            "$C_DIM" "$C_OFF" "$C_RED" "$C_OFF"
        return 1
    fi
    line='Plan only: nothing was changed.'
    [ "$PLAN_SANDBOX" = on ] && line="$line (macOS's sandbox kept it from writing any file.)"
    printf '%s╰%s %s ./kit install does the above.\n' "$C_DIM" "$C_OFF" "$line"
}
