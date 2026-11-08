# shellcheck shell=bash
# Tailscale nodes. Each node is a tailscale/tailscale container named <node>-tailscale in a
# compose project (the module's compose file defines it). What a node serves comes from the
# modules' serve files (serve, or serve.<project> to add to another project's node):
#
#   node|port|path|target|when|funnel
#     node     node id (its machine name is the answer TS_NODE_<node>)
#     port     HTTPS port on the node (443: https://<name>.<tailnet>.ts.net with no port)
#     path     URL path, e.g. / or /health/
#     target   where the node sends it, on the compose network (http://sonarr:8989)
#     when     optional condition, as in prompts files. With @mark (a file the kit writes in the
#              project's app data once it has set the app up, so nobody else can claim it first),
#              the node serves nothing until the mark is there, though it's still set up.
#     funnel   empty: tailnet only. Otherwise public through Funnel when EXPOSE_<node>=funnel,
#              port 443 only, and once the app is set up: "<file>~<regex>", a file under the
#              project's app data that has to match first (so nobody else can claim the app).
#              <file> may also be a path from @HOME@ (a native app's own data), or several,
#              comma-separated, of which one has to match. "always": no such check.
#
# The kit writes ~/server/<project>/tailscale/<node>/serve.json from them on every install. The
# container watches that folder, so a change applies without a restart. After the start, the
# kit reads each node's real address from its container into ~/server/kit/tailnet.conf.

TAILNET_FILE=$KIT_STATE/tailnet.conf

# shellcheck disable=SC2094  # reads the serve file on fd 3; only prints its name
serve_lines() {     # project modules... -> node|port|path|target|funnel lines (conditions applied;
                    # a line waiting for an @mark is node|-|-|-|funnel: the node still gets its file, and an app
                    # waiting to go public is named)
    local p=$1 m f node port path target when funnel
    shift
    # shellcheck disable=SC2034  # when_ok reads it
    WHEN_PROJECT=$p
    for m in "$@"; do
        f=$(module_project_file "$m" "$p" serve) || continue
        while IFS='|' read -r node port path target when funnel <&3; do
            case "$node" in ''|'#'*) continue ;; esac
            case "$port" in ''|*[!0-9]*) die "$(tilde "$f"): bad port '$port' for $node" ;; esac
            case "$path" in /*) ;; *) die "$(tilde "$f"): the path for $node:$port must start with /" ;; esac
            case "$target" in http://*|https://*) ;; *) die "$(tilde "$f"): bad target '$target' for $node:$port" ;; esac
            if ! when_ok "$when"; then
                case "$when" in *@*) printf '%s|-|-|-|%s\n' "$node" "$funnel" ;; esac
                continue
            fi
            printf '%s|%s|%s|%s|%s\n' "$node" "$port" "$path" "$target" "$funnel"
        done 3<"$f"
    done
}

# Whether a serve line's funnel field allows Funnel now. Sets FUNNEL_WAITING when it would be
# public but the app isn't set up yet.
FUNNEL_WAITING=''
funnel_ok() {       # project node funnel-field app -> 0 when the node's port 443 goes public
    local p=$1 node=$2 spec=$3 file re
    [ -n "$spec" ] || return 1
    [ "$(answer "EXPOSE_$node" || true)" = funnel ] || return 1
    [ "$spec" = always ] && return 0
    re=${spec#*~}
    for file in $(printf '%s' "${spec%%~*}" | tr ',' '\n' | sed 's/ /%20/g'); do
        file=${file//%20/ }
        case "$file" in
            @HOME@/*) file=$HOME/${file#@HOME@/} ;;
            /*) ;;
            *) file=$(project_appdata "$p")/$file ;;
        esac
        if [ -f "$file" ] && grep -Eq -- "$re" "$file"; then return 0; fi
    done
    FUNNEL_WAITING=$(list_add "$FUNNEL_WAITING" "$4")
    return 1
}

# Tailscale's serve config for one node, from its port|path|target|funnel lines on stdin.
# ${TS_CERT_DOMAIN} is for the container to fill in (the node's own name).
serve_json() {      # allow-funnel(yes|no)
    # shellcheck disable=SC2016  # ${TS_CERT_DOMAIN} is Tailscale's, not ours
    awk -F'|' -v funnel="$1" -v dom='${TS_CERT_DOMAIN}' '
        { if (!($1 in seen)) { order[++n] = $1; seen[$1] = 1 }
          h[$1] = h[$1] (h[$1] == "" ? "" : ", ") sprintf("\"%s\": { \"Proxy\": \"%s\" }", $2, $3) }
        END {
            print "{"
            print "  \"TCP\": {"
            for (i = 1; i <= n; i++) printf "    \"%s\": { \"HTTPS\": true }%s\n", order[i], (i < n ? "," : "")
            print "  },"
            print "  \"Web\": {"
            for (i = 1; i <= n; i++) printf "    \"%s:%s\": { \"Handlers\": { %s } }%s\n", dom, order[i], h[order[i]], (i < n ? "," : "")
            if (funnel == "yes" && ("443" in seen)) {
                print "  },"
                printf "  \"AllowFunnel\": { \"%s:443\": true }\n", dom
            } else print "  }"
            print "}"
        }'
}

serve_write() {     # project modules...
    local p=$1 lines node allow f spec app
    shift
    lines=$(serve_lines "$p" "$@") || exit 1
    [ -n "$lines" ] || return 0
    for node in $(printf '%s\n' "$lines" | cut -d'|' -f1 | awk '!s[$0]++'); do
        allow=no
        while IFS='|' read -r spec app; do
            [ -n "$spec" ] || continue
            app=$(node_app "$node" "$app" "$@")
            funnel_ok "$p" "$node" "$spec" "$app" && allow=yes
        done <<EOF2
$(printf '%s\n' "$lines" | awk -F'|' -v n="$node" '$1 == n && ($2 == 443 || $2 == "-") && $5 != "" {
    h = $4; sub(/^https?:\/\//, "", h); sub(/[:\/].*$/, "", h); sub(/-proxy$/, "", h); print $5 "|" toupper(substr(h, 1, 1)) substr(h, 2) }')
EOF2
        f=$(plan_out "$(project_dir "$p")/tailscale/$node/serve.json")
        mkdir -p "$(dirname "$f")" || die "could not create $(dirname "$f")"
        printf '%s\n' "$lines" | awk -F'|' -v n="$node" '$1 == n && $2 != "-" { print $2 "|" $3 "|" $4 }' | serve_json "$allow" \
            | write_generated "$f"
    done
}

# ---------------------------------------------------------------- after the start

ts_nodes_of() {     # project -> node ids that have a serve.json
    local d
    for d in "$(project_dir "$1")"/tailscale/*/serve.json; do
        [ -f "$d" ] || continue
        d=${d%/serve.json}
        printf '%s ' "${d##*/}"
    done
}

# Read each node's address from its container and say what isn't set up in the tailnet.
tailnet_read() {    # (STARTED_PROJECTS)
    local p node st dns asked app tmp='' any=''
    for p in $STARTED_PROJECTS; do any=$any$(ts_nodes_of "$p"); done
    [ -n "$any" ] || return 0
    section "Tailscale"
    for p in $STARTED_PROJECTS; do
        for node in $(ts_nodes_of "$p"); do
            if ! st=$(dk exec "$node-tailscale" tailscale status --json --peers=false 2>/dev/null | json_flat); then
                warn "Tailscale $node: couldn't read its status (docker compose logs $node-tailscale)"
                continue
            fi
            dns=$(printf '%s' "$st" | sed -n 's/.*"Self":{[^}]*"DNSName":"\([^"]*\)".*/\1/p')
            dns=${dns%.}
            if [ -z "$dns" ]; then
                warn "Tailscale $node: not logged in yet (docker compose logs $node-tailscale)"
                continue
            fi
            tmp="${tmp}TS_DNS_$node=$dns
"
            ok "Tailscale $node: https://$dns"
            asked=$(answer "TS_NODE_$node" || true)
            if [ -n "$asked" ] && [ "${dns%%.*}" != "$asked" ]; then
                warn "The name $asked was taken in your tailnet, so this machine is ${dns%%.*}. To get $asked back: admin console → Machines → remove the old $asked, then rename this one."
            fi
            printf '%s' "$st" | grep -qF '"MagicDNSEnabled":true' \
                || warn "MagicDNS is off in your tailnet: admin console → DNS → enable MagicDNS. Until then the names above don't resolve."
            printf '%s' "$st" | grep -qF '"CertDomains":["' \
                || warn "HTTPS certificates are off in your tailnet: admin console → DNS → HTTPS Certificates → Enable. Until then the https:// addresses don't work."
            printf '%s' "$st" | grep -qF '"Tags":["' \
                || warn "Tailscale $node has no tag, so its login expires in 180 days. Use an auth key with a tag (see TS_AUTHKEY in ./kit prepare), or: admin console → Machines → ${dns%%.*} → Disable key expiry."
        done
    done
    [ -n "$tmp" ] || return 0
    printf '# Generated by ./kit install: each Tailscale node'\''s address. Do not edit.\n%s' "$tmp" \
        | write_generated "$TAILNET_FILE"
}

# The app a node's port 443 serves, as the messages name it: its name in a urls file (Open WebUI),
# else the one made from its address (Seerr). Spaces become _ in FUNNEL_WAITING's word list.
node_app() {        # node fallback modules...
    local node=$1 fallback_name=$2 name="" m f
    shift 2
    for m in "$@"; do
        f="$(mod_dir "$m")/urls"
        [ -f "$f" ] || continue
        name=$(awk -F'|' -v t="$node:443" '$3 == t { print $1; exit }' "$f")
        [ -n "$name" ] && break
    done
    name=${name:-$fallback_name}
    printf '%s' "${name// /_}"
}

# After the wiring, write the serve files again: an app the kit sets up itself (Jellyfin) goes
# public in the same run, and the apps still waiting for their setup are named.
serve_refresh() {   # modules...
    local before=$FUNNEL_WAITING p app
    FUNNEL_WAITING=''
    for p in $STARTED_PROJECTS; do serve_write "$p" "$@"; done
    for app in $before; do
        in_list "$app" "$FUNNEL_WAITING" || ok "${app//_/ }: public now (Funnel), as it's set up"
    done
    for app in $FUNNEL_WAITING; do
        app=${app//_/ }
        note "$app stays tailnet-only until it's set up, so no one else can claim it first. The ./kit install after that makes it public (Funnel)."
    done
}

ts_url() {          # node port -> https://<node's address>[:port] ("" when not known)
    local dns
    dns=$(kv_get "$TAILNET_FILE" "TS_DNS_$1" 2>/dev/null) || return 0
    [ -n "$dns" ] || return 0
    if [ "$2" = 443 ]; then printf 'https://%s' "$dns"; else printf 'https://%s:%s' "$dns" "$2"; fi
}
