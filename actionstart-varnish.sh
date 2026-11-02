#!/usr/bin/env bash
#
# NPP Varnish / Vinyl Cache sync test runner for the Docker stack.
#
# Two layers:
#
#   Layer 1 (default)   the in-process harness of the plugin (varnish-test/run-varnish-tests.sh):
#                       unit + sanitize need only PHP; e2e starts a real varnishd INSIDE wordpress-fpm
#                       (Debian package, not the official image) in front of a counting backend.
#                       It does NOT test the container topology.
#
#   Layer 2 (--topology) the real topology with the official Varnish image as its own container:
#                         visitor -> nginx:443 (edge) -> varnish:80 -> nginx:8080 (fastcgi_cache) -> wordpress-fpm
#                       Brings the stack up with docker-compose.varnish.yml (nginx + wordpress switch to
#                       nginx/default.varnish.conf, the nginx and wordpress containers are recreated), installs
#                       the VCL taken from the plugin's Help tab into the varnish container, points NPP at it
#                       and checks the wiring. Then hands over to varnish-test/run-topology-tests.sh when the
#                       plugin branch ships it.
#
# Usage (on the Docker host, from the directory containing docker-compose.yml):
#   ./actionstart-varnish.sh                              layer 1: unit + sanitize + e2e
#   ./actionstart-varnish.sh --only unit sanitize         layer 1: only php, seconds
#   ./actionstart-varnish.sh --only unit:parse e2e:auth   layer 1: single sections
#   ./actionstart-varnish.sh --topology                   layer 2: bring-up + wiring checks (+ topology tests)
#   ./actionstart-varnish.sh --topology happy faults      layer 2: pass phases to run-topology-tests.sh
#   ./actionstart-varnish.sh --topology --image varnish:old        another image tag (fresh | old | stable)
#   ./actionstart-varnish.sh --topology --acl subnet      ACL = whole Docker subnet instead of the PHP container /32
#   ./actionstart-varnish.sh --topology --vcl noregex     install a broken VCL variant (noregex | aclnone | nopurge)
#   ./actionstart-varnish.sh --varnish-only               layer 2 with NO Nginx cache: Varnish-only mode (VO) topology
#   ./actionstart-varnish.sh --varnish-only --vo-scratch DIR   NPP "Nginx Cache Directory" (default /var/cache/npp-varnish-only)
#   ./actionstart-varnish.sh --vo-http-purge              --varnish-only, but HTTP Purge stays ON and an idle :8443 purge listener exists
#   ./actionstart-varnish.sh --src ../plugin/varnish-test copy the test from a local checkout first
#   ./actionstart-varnish.sh --build                      rebuild images while bringing the stack up
#   ./actionstart-varnish.sh --no-run                     prepare only, do not run the tests
#   ./actionstart-varnish.sh --status                     what is installed, which VCL/ACL/settings are active
#   ./actionstart-varnish.sh --shell                      root shell in the lab directory
#   ./actionstart-varnish.sh --clean                      stop varnishd of layer 1; leave the topology: restore
#                                                         NPP settings, drop the varnish container, base vhost
#   ./actionstart-varnish.sh --purge                      --clean + delete the lab run/ state
#
# Varnish-only topology (--varnish-only), for NPP's Varnish-only mode:
#                         visitor -> nginx:443 (edge) -> varnish:80 -> nginx:8080 (NO fastcgi_cache) -> wordpress-fpm
#                       Adds docker-compose.varnish-only.yml on top of the three files (nginx + wordpress switch to
#                       nginx/default.varnish-only.conf: no fastcgi_cache_path, no :8443 purge listener). NPP is set to
#                       Varnish sync ON + Varnish-only mode ON + HTTP Purge OFF, and its "Nginx Cache Directory" is pointed
#                       at an empty scratch directory inside wordpress-fpm (that is all the preload crawler needs in VO).
#                       With --vo-http-purge (implies --varnish-only) HTTP Purge is left ON and a fifth compose file
#                       (docker-compose.varnish-only-purge.yml) adds the :8443 listener on an unused cache zone. NPP never
#                       calls HTTP Purge in VO, so the wiring checks assert the listener sees NO purge request while
#                       `wp npp purge` runs (and that its status endpoint, which the Status tab polls, still answers).
#                       The settings it replaces are remembered and put back by --clean. Running the script again WITHOUT
#                       --varnish-only (--topology) switches back to the "Varnish in front of an Nginx cache" topology and
#                       turns VO off, so the two can never be mixed by accident.
#                       run-topology-tests.sh is NOT run in VO: it asserts the Nginx layer (NPP-FastCGI-Cache, :8443).
#                       The wiring checks below are VO-specific instead, incl. a real `wp npp purge` against Varnish.
#
# The e2e layer and the topology are independent: layer 1 never changes the stack topology, it follows the
# one that is running (a running `varnish` container keeps the three-file compose set).
# Everything layer 2 installs lives in containers; the VCL is regenerated on every run, so a recreated
# wordpress-fpm (new IP) is picked up by simply running the script again.
#
# Overridable environment:
#   C                  wordpress container name        (default: wordpress-fpm)
#   VC                 varnish container name          (default: varnish)
#   NGX                nginx container name            (default: nginx)
#   WP_USER            PHP-FPM pool user               (default: NPP_USER_ from .env, else npp)
#   WP_PATH            WordPress root in container     (default: /var/www/html)
#   LAB_DIR            lab dir in container            (default: /opt/npp-varnish-test)
#   VARNISH_IMAGE      varnish image                   (default: varnish:fresh, set in docker-compose.varnish.yml)
#   VARNISH_CONTROL_KEY secret for X-Control-Key       (default: npp-lab-control-key)
#   NET                docker network of the stack     (default: npp-wp)
#   WAIT               seconds to wait per stage       (default: 300)
set -euo pipefail

# ---------------------------------------------------------------- config ----
STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$STACK_DIR"

C="${C:-wordpress-fpm}"
VC="${VC:-varnish}"
NGX="${NGX:-nginx}"
WP_PATH="${WP_PATH:-/var/www/html}"
WAIT="${WAIT:-300}"
NET="${NET:-npp-wp}"
PLUGIN_SLUG="fastcgi-cache-purge-and-preload-nginx"
D="${LAB_DIR:-/opt/npp-varnish-test}"
KEY="${VARNISH_CONTROL_KEY:-npp-lab-control-key}"
VCL_REMOTE="/etc/varnish/npp-lab.vcl"
HOME_FALLBACK_URL="https://nginx/"   # what wp-post.sh writes as Purge Custom Base URL (restored by --clean)

COMPOSE_LAB=(docker compose -f docker-compose.yml -f docker-compose.lab.yml)
COMPOSE_TOPO=(docker compose -f docker-compose.yml -f docker-compose.lab.yml -f docker-compose.varnish.yml)
COMPOSE_VO=(docker compose -f docker-compose.yml -f docker-compose.lab.yml -f docker-compose.varnish.yml -f docker-compose.varnish-only.yml)
COMPOSE_VOP=(docker compose -f docker-compose.yml -f docker-compose.lab.yml -f docker-compose.varnish.yml -f docker-compose.varnish-only.yml -f docker-compose.varnish-only-purge.yml)
VO_SCRATCH_DEFAULT="/var/cache/npp-varnish-only"   # NPP "Nginx Cache Directory" in VO: preload scratch space only

env_val() { sed -nE "s/^(export )?$1=//p" .env 2>/dev/null | tail -n1 | tr -d "\"' \r" || true; }
if [ -z "${WP_USER:-}" ]; then WP_USER="$(env_val NPP_USER_)"; WP_USER="${WP_USER:-npp}"; fi
SITE_HOST="$(env_val NPP_HTTP_HOST)"; SITE_HOST="${SITE_HOST:-localhost}"

# ---------------------------------------------------------------- output ----
if [ -t 1 ]; then R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[36m'; N=$'\033[0m'; else R=; G=; Y=; B=; N=; fi
step() { printf '%s==>%s %s\n' "$B" "$N" "$*"; }
ok()   { printf '    %s[ok]%s %s\n' "$G" "$N" "$*"; }
warn() { printf '    %s[!!]%s %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '%s[xx] %s%s\n' "$R" "$*" "$N" >&2; exit 1; }

dx()   { docker exec "$@"; }
rx()   { docker exec -u root "$C" "$@"; }            # root in wordpress-fpm
vx()   { docker exec "$VC" "$@"; }                   # in the varnish container (image user)

# ------------------------------------------------------------- arg parse ----
MODE=run; LAYER=harness; BUILD=0; SRC=""; IMAGE=""; ACL_MODE=ip; VCL_VARIANT=example; VARNISH_ONLY=0; VO_HTTP_PURGE=0; VO_SCRATCH="$VO_SCRATCH_DEFAULT"; PASS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --topology) LAYER=topology ;;
        --varnish-only) LAYER=topology; VARNISH_ONLY=1 ;;
        --vo-http-purge) LAYER=topology; VARNISH_ONLY=1; VO_HTTP_PURGE=1 ;;
        --vo-scratch)   VO_SCRATCH="${2:?--vo-scratch DIR (absolute path inside wordpress-fpm)}"; shift ;;
        --build)    BUILD=1 ;;
        --no-run)   MODE=prepare ;;
        --status)   MODE=status ;;
        --clean)    MODE=clean ;;
        --purge)    MODE=purge ;;
        --shell)    MODE=shell ;;
        --src)      SRC="${2:?--src DIR}"; shift ;;
        --image)    IMAGE="${2:?--image varnish:fresh|old|stable}"; shift ;;
        --acl)      ACL_MODE="${2:?--acl ip|subnet}"; shift ;;
        --vcl)      VCL_VARIANT="${2:?--vcl example|noregex|aclnone|nopurge}"; shift ;;
        -h|--help)  sed -n '2,/^set -euo/p' "$0" | sed '$d;s/^# \{0,1\}//'; exit 0 ;;
        *)          PASS+=("$1") ;;
    esac
    shift
done
case "$ACL_MODE" in ip|subnet) ;; *) die "--acl must be ip or subnet" ;; esac
case "$VCL_VARIANT" in example|noregex|aclnone|nopurge) ;; *) die "--vcl must be example, noregex, aclnone or nopurge" ;; esac
case "$VO_SCRATCH" in /*) ;; *) die "--vo-scratch must be an absolute path" ;; esac
case "$VO_SCRATCH" in *[!A-Za-z0-9_./-]*) die "--vo-scratch may only contain letters, digits and _ . / -" ;; esac
[ "$VARNISH_ONLY" -eq 1 ] || [ "$VO_SCRATCH" = "$VO_SCRATCH_DEFAULT" ] || die "--vo-scratch only makes sense together with --varnish-only"
[ -z "$IMAGE" ] || export VARNISH_IMAGE="$IMAGE"
export VARNISH_CONTROL_KEY="$KEY"

# --------------------------------------------------------------- helpers ----
need_docker() {
    command -v docker >/dev/null 2>&1 || die "docker not found"
    docker compose version >/dev/null 2>&1 || die "'docker compose' plugin (v2) not found"
    [ -f docker-compose.lab.yml ] || die "docker-compose.lab.yml missing - run this from the stack repo"
}
exists()      { docker inspect "$1" >/dev/null 2>&1; }
running()     { [ "$(docker inspect -f '{{.State.Running}}' "${1:-$C}" 2>/dev/null || echo false)" = true ]; }
lab_mounted() { rx sh -c "grep -qs ' $D ' /proc/self/mounts" 2>/dev/null; }
topo_active() { exists "$VC" && running "$VC"; }
listener_mounted() {   # does nginx carry the optional VO :8443 purge listener (docker-compose.varnish-only-purge.yml)?
    local dst
    dst="$(docker inspect -f '{{range .Mounts}}{{.Destination}} {{end}}' "$NGX" 2>/dev/null || true)"
    case " $dst " in *" /etc/nginx/conf.d/npp-purge-listener.conf "*) return 0 ;; *) return 1 ;; esac
}
vhost_kind() {   # which vhost does the nginx container run?  base | varnish | varnish-only
    local src
    src="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/etc/nginx/conf.d/default.conf"}}{{.Source}}{{end}}{{end}}' "$NGX" 2>/dev/null || true)"
    case "${src##*/}" in
        default.varnish-only.conf) printf '%s\n' varnish-only ;;
        default.varnish.conf)      printf '%s\n' varnish ;;
        *)                         printf '%s\n' base ;;
    esac
}

wait_for() {  # wait_for "<label>" <cmd...>
    local label="$1"; shift
    local t0=$SECONDS
    until "$@" >/dev/null 2>&1; do
        [ $((SECONDS - t0)) -ge "$WAIT" ] && die "timeout (${WAIT}s) waiting for: $label"
        sleep 3
    done
    ok "$label ($((SECONDS - t0))s)"
}

wpc() { dx -u root "$C" runuser -u "$WP_USER" -- env HOME=/tmp/wp-home wp --path="$WP_PATH" "$@"; }

# The plugin loads its bootstrap (every nppp_* function) only for `wp npp ...` commands. A plain `wp eval` sees
# none of them, so function_exists() would report "no Varnish-only mode" and skip the state reset. Load it first.
WP_BOOT='if(function_exists("nppp_load_bootstrap")){nppp_load_bootstrap();}'

# Forget the breaker / throttled warning (and, when the plugin has it, the VO failure) of a previous run.
reset_varnish_state() {
    wpc eval "$WP_BOOT"'if(function_exists("nppp_varnish_only_reset_state")){nppp_varnish_only_reset_state();}elseif(function_exists("nppp_state_delete")){nppp_state_delete("varnish_breaker");nppp_state_delete("varnish_warn");}' >/dev/null 2>&1 || true
}

# Set one NPP option. `wp npp settings set` validates like the Settings page; when its environment
# check refuses (e.g. no nginx binary in this container) fall back to the raw option patch that
# wp-post.sh itself uses.
set_npp() {  # set_npp <key> <value> [lenient]   (lenient: the plugin may normalise the value, only report it)
    local k="$1" v="$2" lenient="${3:-}" got
    if ! wpc npp settings set "$k" "$v" >/dev/null 2>&1; then
        warn "wp npp settings set $k failed - using wp option patch (no plugin-side validation)"
        wpc option patch update nginx_cache_settings "$k" "$v" >/dev/null 2>&1 || die "cannot set $k"
    fi
    got="$(wpc option pluck nginx_cache_settings "$k" 2>/dev/null | tr -d '\r' || true)"
    if [ "$got" = "$v" ] || [ "$got" = "${v%/}" ]; then return 0; fi
    [ -n "$lenient" ] || die "setting $k reads back '$got', expected '$v'"
    ok "$k stored as '$got' (normalised by the plugin)"
}

compose_set() {  # which compose files match the stack that is running now: lab | topo | vo | vop
    if [ "$LAYER" = topology ]; then
        if [ "$VO_HTTP_PURGE" -eq 1 ]; then printf '%s\n' vop
        elif [ "$VARNISH_ONLY" -eq 1 ]; then printf '%s\n' vo
        else printf '%s\n' topo; fi
    elif topo_active; then   # layer 1 follows the topology that is running, it never changes it
        if [ "$(vhost_kind)" = varnish-only ]; then
            if listener_mounted; then printf '%s\n' vop; else printf '%s\n' vo; fi
        else printf '%s\n' topo; fi
    else
        printf '%s\n' lab
    fi
}
compose() {      # docker compose with the file set of compose_set
    case "$(compose_set)" in
        vop)  "${COMPOSE_VOP[@]}" "$@" ;;
        vo)   "${COMPOSE_VO[@]}" "$@" ;;
        topo) "${COMPOSE_TOPO[@]}" "$@" ;;
        *)    "${COMPOSE_LAB[@]}" "$@" ;;
    esac
}
up_stack() {
    local up=(up -d)
    [ "$BUILD" -eq 1 ] && up+=(--build)
    compose "${up[@]}"
}

ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }   # ver_ge have need

vnum_of() { sed -nE 's/.*[^0-9]([0-9]+\.[0-9]+)\.[0-9]+.*/\1/p' <<<"$1" | head -n1 || true; }   # "varnish-9.1.0 ..." -> 9.1

# One line that names the version of the RUNNING varnish container. `varnishd -V` is the normal source, but not every
# image accepts it through `docker exec` (varnish:stable answers "Error: -V must be the first argument"), so the CLI
# banner of the running daemon is the fallback: it answers whenever `varnishadm ping` does. Only the line that names
# varnish / vinyl is read - the banner also holds the kernel version ("Linux,6.1.0-..."), which must never be mistaken
# for the Varnish version.
# varnish:stable ships /usr/local/bin/varnishd, a wrapper that prepends "-n /var/lib/varnish" to every call, so
# "varnishd -V" reaches the daemon as "varnishd -n ... -V" and mgt_main.c rejects it (-V must be argv[1]).
# /usr/sbin/varnishd is the real binary (the wrapper itself execs it): ask that one first.
varnishd_v() { vx /usr/sbin/varnishd -V 2>&1 || vx varnishd -V 2>&1 || true; }

varnish_version_line() {
    local out line
    out="$(varnishd_v)"; line="${out%%$'\n'*}"
    if [ -n "$(vnum_of "$line")" ]; then printf '%s\n' "$line"; return 0; fi
    out="$(vx varnishadm banner 2>&1 || true)"
    line="$(grep -Eim1 '(varnish|vinyl)[-a-z ]*[0-9]+\.[0-9]+\.[0-9]+' <<<"$out" || true)"
    [ -n "$line" ] && [ -n "$(vnum_of "$line")" ] && { printf '%s (from varnishadm banner)\n' "$line"; return 0; }
    printf '%s\n' "${out%%$'\n'*}"
}

# ----------------------------------------------------------------- modes ----
mode_shell() {
    need_docker; running || die "container $C is not running"
    exec docker exec -it -u root -w "$D" -e WP_USER="$WP_USER" -e WP_PATH="$WP_PATH" \
        -e NPPP_INCLUDES="$WP_PATH/wp-content/plugins/$PLUGIN_SLUG/includes" "$C" bash
}

mode_status() {
    need_docker
    step "Containers"
    docker ps -a --filter "name=^${C}\$" --filter "name=^${NGX}\$" --filter "name=^${VC}\$" \
        --format '    {{.Names}}\t{{.Image}}\t{{.Status}}'
    case "$(vhost_kind)" in
        varnish-only) ok "nginx runs the Varnish-only vhost (default.varnish-only.conf): NO Nginx cache" ;;
        varnish)      ok "nginx runs the varnish vhost (default.varnish.conf): Varnish in front of an Nginx cache" ;;
        *)            warn "nginx runs the base vhost (topology is OFF)" ;;
    esac
    if topo_active; then
        step "Varnish ($VC)"
        varnish_version_line | sed 's/^/    /'
        vx varnishadm vcl.list 2>&1 | sed 's/^/    /' || true
        printf '    health: %s\n' "$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$VC")"
        step "Active ACL + control key line of $VCL_REMOTE"
        vx sh -c "grep -nE '^acl |X-Control-Key' '$VCL_REMOTE' | sed 's/^/    /'" 2>&1 || true
    fi
    if running; then
        step "NPP settings"
        for k in nginx_cache_path nppp_http_purge_enabled nppp_http_purge_custom_url nppp_http_purge_queue_status_path \
                 nppp_varnish_sync_enabled nppp_varnish_endpoints nppp_varnish_header nppp_varnish_only_enabled; do
            printf '    %-36s %s\n' "$k" "$(wpc option pluck nginx_cache_settings "$k" 2>/dev/null | tr -d '\r' || echo '?')"
        done
        printf '    %-36s %s\n' "Varnish-only mode (plugin view)" \
            "$(wpc eval "$WP_BOOT"'echo function_exists("nppp_varnish_only_mode") ? (nppp_varnish_only_mode() ? "ACTIVE" : "off") : "n/a (plugin has no VO)";' 2>/dev/null | tr -d '\r\n' || echo '?')"
    fi
    exit 0
}

mode_clean() {
    need_docker
    if running; then
        step "Stopping the harness varnishd (layer 1), if any"
        rx sh -c "pkill -f 'varnishd -F -n /tmp/npp-vt-la[b]' || true; rm -rf /tmp/npp-vt-lab-*"
        ok "stopped"
    fi
    if exists "$VC"; then
        if running; then
            step "Restoring the NPP settings (Varnish-only off, Varnish sync off, Purge Custom Base URL back)"
            prev="$HOME_FALLBACK_URL"
            if rx test -f "$D/run/prev_custom_url" 2>/dev/null; then prev="$(rx cat "$D/run/prev_custom_url" | tr -d '\r\n')"; fi
            rx mkdir -p /tmp/wp-home; rx chown "$WP_USER" /tmp/wp-home
            # VO first: the mode only exists while sync is ON with an endpoint, so switch it off before those go.
            set_npp nppp_varnish_only_enabled no
            # Only a --varnish-only run saves these two; without the file the setting was never touched.
            if rx test -f "$D/run/prev_http_purge" 2>/dev/null; then
                set_npp nppp_http_purge_enabled "$(rx cat "$D/run/prev_http_purge" | tr -d '\r\n')"
                rx rm -f "$D/run/prev_http_purge"
                ok "HTTP Purge restored"
            fi
            if rx test -f "$D/run/prev_cache_path" 2>/dev/null; then
                set_npp nginx_cache_path "$(rx cat "$D/run/prev_cache_path" | tr -d '\r\n')" lenient
                rx rm -f "$D/run/prev_cache_path"
                ok "Nginx Cache Directory restored"
            fi
            set_npp nppp_varnish_sync_enabled no
            set_npp nppp_varnish_endpoints ""
            set_npp nppp_varnish_header ""
            set_npp nppp_http_purge_custom_url "$prev"
            reset_varnish_state
            rx rm -f "$D/run/prev_custom_url"
            ok "Purge Custom Base URL = $prev"
        else
            warn "$C is not running: NPP settings were NOT restored (Purge Custom Base URL may still be https://nginx:8443)"
        fi
        step "Back to the base topology (varnish container removed, nginx + wordpress recreated with default.conf)"
        "${COMPOSE_LAB[@]}" up -d --remove-orphans
        ok "base topology"
    else
        ok "no topology active"
    fi
    if [ "$MODE" = purge ]; then
        step "Deleting $D/run"
        running && rx rm -rf "$D/run"
    fi
    exit 0
}

case "$MODE" in
    shell)  mode_shell ;;
    status) mode_status ;;
    clean|purge) mode_clean ;;
esac

# ------------------------------------------------------------ 1. preflight ----
need_docker
TOTAL=6; [ "$LAYER" = topology ] && TOTAL=8
WANT_VHOST=varnish; [ "$VARNISH_ONLY" -eq 1 ] && WANT_VHOST=varnish-only
step "1/$TOTAL Preflight ($LAYER)"
if [ ! -f .env ]; then
    cp .env.example .env
    warn ".env was missing - copied from .env.example (placeholder passwords, fine for a local lab)"
fi
grep -Eq '^(export )?NPP_EDGE_=1' .env || warn "NPP_EDGE_ is not 1 in .env: the plugin would come from wordpress.org and has no varnish-test/"
[ -z "$SRC" ] || [ -f "$SRC/run-varnish-tests.sh" ] || die "--src $SRC has no run-varnish-tests.sh"
if [ "$LAYER" = topology ]; then
    [ -f docker-compose.varnish.yml ]  || die "docker-compose.varnish.yml missing"
    [ -f nginx/default.varnish.conf ]  || die "nginx/default.varnish.conf missing"
    if [ "$VARNISH_ONLY" -eq 1 ]; then
        [ -f docker-compose.varnish-only.yml ] || die "docker-compose.varnish-only.yml missing"
        [ -f nginx/default.varnish-only.conf ] || die "nginx/default.varnish-only.conf missing"
        if [ "$VO_HTTP_PURGE" -eq 1 ]; then
            [ -f docker-compose.varnish-only-purge.yml ] || die "docker-compose.varnish-only-purge.yml missing"
            [ -f nginx/varnish-only-purge-listener.conf ] || die "nginx/varnish-only-purge-listener.conf missing"
        fi
        compose config >/dev/null || die "docker compose config failed for the $([ "$VO_HTTP_PURGE" -eq 1 ] && echo five || echo four)-file set"
        ok "compose set: base + lab + varnish + varnish-only$([ "$VO_HTTP_PURGE" -eq 1 ] && echo ' + varnish-only-purge'), image ${VARNISH_IMAGE:-varnish:fresh (compose default)}, ACL=$ACL_MODE, VCL=$VCL_VARIANT"
        ok "Varnish-only topology: Nginx has NO cache, NPP Nginx Cache Directory = $VO_SCRATCH (scratch)"
        [ "$VO_HTTP_PURGE" -eq 0 ] || ok "HTTP Purge stays ON, idle :8443 listener added (NPP must never call it in VO)"
    else
        compose config >/dev/null || die "docker compose config failed for the three-file set"
        ok "compose set: base + lab + varnish, image ${VARNISH_IMAGE:-varnish:fresh (compose default)}, ACL=$ACL_MODE, VCL=$VCL_VARIANT"
    fi
else
    ok "docker compose ready, lab dir $D"
    # Layer 1 asserts stock behaviour (an Nginx cache exists). On a running VO topology the plugin would sit in VO
    # as soon as layer 1 turns Varnish sync on, and every purge/preload assertion would test the wrong mode.
    if topo_active && [ "$(vhost_kind)" = varnish-only ]; then
        die "the Varnish-only topology is running: layer 1 (no --topology flag) assumes an Nginx cache. Run ./actionstart-varnish.sh --topology (stock) or --clean first"
    fi
    topo_active && ok "a varnish container is running: keeping the three-file compose set (topology untouched)"
fi

# --------------------------------------------------------------- 2. stack up ----
step "2/$TOTAL Bringing the stack up"
[ "$LAYER" = topology ] && warn "recreates nginx + wordpress when they do not run the $WANT_VHOST vhost yet (wp-post.sh runs again, takes a minute)"
up_stack
if running && ! lab_mounted; then
    warn "container runs without the npp_varnish_lab volume - recreating wordpress with the lab override"
    compose up -d --force-recreate wordpress
fi
wait_for "container $C running" running
wait_for "npp_varnish_lab mounted at $D" lab_mounted
if [ "$LAYER" = topology ]; then
    wait_for "container $VC running" running "$VC"
    wait_for "$VC answers varnishadm ping" vx varnishadm ping
    printf '    health: %s (the healthcheck is informational; nothing depends on it)\n' \
        "$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$VC")"
    [ "$(vhost_kind)" = "$WANT_VHOST" ] || die "nginx is not running the $WANT_VHOST vhost (it runs: $(vhost_kind)) - check 'docker inspect $NGX' mounts"
    ok "nginx runs nginx/default.$WANT_VHOST.conf"
fi

# ------------------------------------------------- 3. WordPress + plugin ----
step "3/$TOTAL Waiting for WordPress + NPP (wp-post.sh writes .npp-ready when the plugin deploy is done)"
wait_for "wp-post.sh finished" rx test -f "$WP_PATH/.npp-ready"
INC="$WP_PATH/wp-content/plugins/$PLUGIN_SLUG/includes"
rx test -f "$INC/compat-varnish.php" || die "compat-varnish.php not in $INC: the deployed plugin has no Varnish support (need the v2.1.9 branch, NPP_EDGE_=1)"
ok "plugin deployed, compat-varnish.php present"
if [ "$VARNISH_ONLY" -eq 1 ]; then
    rx grep -q 'function nppp_varnish_only_mode' "$INC/compat-varnish.php" || die "the deployed plugin has no Varnish-only mode (nppp_varnish_only_mode missing in compat-varnish.php): need the v2.1.9 branch"
    ok "plugin has Varnish-only mode"
fi

# ------------------------------------------------------------ 4. harness dir ----
step "4/$TOTAL Harness in $D"
if [ -n "$SRC" ]; then
    docker cp "$SRC/." "$C:$D/"
    rx sh -c "chmod 755 '$D'; chmod u+x '$D'/*.sh"
    ok "copied from $SRC"
fi
rx test -f "$D/run-varnish-tests.sh" || die "$D/run-varnish-tests.sh missing: commit varnish-test/ to the plugin branch (wp-post.sh installs it on the next deploy) or pass --src <checkout>/varnish-test"
ok "$D/run-varnish-tests.sh present"

# ============================================================== LAYER 1 ====
if [ "$LAYER" = harness ]; then
    step "5/$TOTAL Tooling inside $C"
    NEED_E2E=1; IN_ONLY=0
    for a in ${PASS[@]+"${PASS[@]}"}; do
        case "$a" in
            --only)   IN_ONLY=1; NEED_E2E=0 ;;
            --no-e2e) NEED_E2E=0 ;;
            -*)       IN_ONLY=0 ;;
            e2e|e2e:*) [ "$IN_ONLY" -eq 1 ] && NEED_E2E=1 ;;
        esac
    done
    PHP_MODULES="$(rx php -m 2>/dev/null || true)"     # no "| grep -q": pipefail + early exit = false SIGPIPE failure
    grep -qix curl <<<"$PHP_MODULES" || die "PHP curl extension missing in $C (the harness needs it)"
    if [ "$NEED_E2E" -eq 1 ]; then
        MISSING="$(rx sh -c 'for t in varnishd varnishadm python3 cc curl; do command -v $t >/dev/null || printf "%s " $t; done')"
        if [ -n "$MISSING" ]; then
            warn "e2e tooling missing ($MISSING) - installing Debian varnish + python3 + build-essential (lost on container recreate)"
            warn "this is the distribution's Varnish, not the official image: it says nothing about the image version"
            # No daemon must start from the package postinst inside the container.
            rx sh -c 'printf "#!/bin/sh\nexit 101\n" > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d
                      apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends varnish python3 build-essential curl procps >/dev/null
                      rm -f /usr/sbin/policy-rc.d'
        fi
        VV="$(rx varnishd -V 2>&1 || true)"
        ok "varnishd: ${VV%%$'\n'*}"
    else
        ok "this run needs only php (no varnishd)"
    fi

    [ "$MODE" = prepare ] && { step "Prepared. Run the tests with: ./actionstart-varnish.sh --only unit sanitize"; exit 0; }

    step "6/$TOTAL Running ${PASS[*]:-unit + sanitize + e2e}"
    set +e
    docker exec -u root -e "WP_PATH=$WP_PATH" -e "NPPP_INCLUDES=$INC" "$C" "$D/run-varnish-tests.sh" ${PASS[@]+"${PASS[@]}"}
    RC=$?
    set -e
    echo
    if [ "$RC" -eq 0 ]; then
        printf '%sALL CHECKS PASSED%s\n' "$G" "$N"
    else
        printf '%sTESTS FAILED (exit %s)%s\n' "$R" "$RC" "$N"
        echo "  keep the lab files : ./actionstart-varnish.sh --shell, then VT_KEEP_LAB=1 ./run-varnish-tests.sh -v --only <section>"
    fi
    echo "  topology tests     : ./actionstart-varnish.sh --topology"
    echo "  cleanup            : ./actionstart-varnish.sh --clean"
    exit "$RC"
fi

# ============================================================== LAYER 2 ====
step "5/8 Origin reachable (nginx:8080 from $C) and varnish version"
wait_for "origin answers http://$NGX:8080/wp-json/" rx curl -sf -o /dev/null -H "Host: $SITE_HOST" "http://$NGX:8080/wp-json/"
VV="$(varnish_version_line)"
VNUM="$(vnum_of "$VV")"
[ -n "$VNUM" ] || die "cannot read the Varnish version (varnishd -V said: $(varnishd_v | head -n1); CLI banner had no version line)"
LEGACY_BAN=0
if ! ver_ge "$VNUM" 6.5; then
    LEGACY_BAN=1
    warn "Varnish $VNUM has no std.ban(): the documented VCL is rewritten to the plain ban() statement (a deviation from the Help text)"
fi
ok "$VV"

step "6/8 Installing the VCL from the plugin's Help tab into $VC"
PHP_IP="$(docker inspect -f "{{with index .NetworkSettings.Networks \"$NET\"}}{{.IPAddress}}{{end}}" "$C")"
[ -n "$PHP_IP" ] || die "$C has no address on network $NET (set NET=<network>)"
SUBNET="$(docker network inspect "$NET" -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' | tr ' ' '\n' | grep -v ':' | head -n1 || true)"
if [ "$ACL_MODE" = subnet ]; then
    [ -n "$SUBNET" ] || die "cannot read the IPv4 subnet of network $NET"
    ACL_VCL="\"${SUBNET%/*}\"/${SUBNET#*/};"
else
    ACL_VCL="\"$PHP_IP\";"
fi
ok "PHP container $PHP_IP, network $NET $SUBNET -> acl purge { $ACL_VCL }"

TMPV="$(mktemp)"; trap 'rm -f "$TMPV"' EXIT
docker exec -i -u root \
    -e "HELP=$INC/help.php" -e "ACL_VCL=$ACL_VCL" -e "KEY=$KEY" -e "VARIANT=$VCL_VARIANT" -e "LEGACY_BAN=$LEGACY_BAN" \
    -e "BACKEND_HOST=$NGX" -e "BACKEND_PORT=8080" "$C" php <<'PHPEOF' > "$TMPV" || die "VCL generation failed (see above)"
<?php
// Cuts the "Example VCL" out of includes/help.php, exactly like varnish-test/lib/lab.php does, so the VCL under test
// is the text a site owner copies. Every change is a one-line substitution that must match, else we stop.
$help = (string) file_get_contents( getenv( 'HELP' ) );
if ( ! preg_match( '#<pre>(vcl 4\.1;.*?)</pre>#s', $help, $m ) ) { fwrite( STDERR, "Example VCL block (<pre>vcl 4.1; ...</pre>) not found in help.php\n" ); exit( 2 ); }
$v = html_entity_decode( strip_tags( $m[1] ), ENT_QUOTES | ENT_HTML5, 'UTF-8' );
$sub = static function ( string $v, string $from, string $to ): string {
    if ( strpos( $v, $from ) === false ) { fwrite( STDERR, "example VCL no longer contains " . json_encode( $from ) . " - update actionstart-varnish.sh\n" ); exit( 2 ); }
    return str_replace( $from, $to, $v );
};
$variant = getenv( 'VARIANT' );
$acl     = $variant === 'aclnone' ? '"203.0.113.7";' : getenv( 'ACL_VCL' );
$v = $sub( $v, 'acl purge { "127.0.0.1"; "::1"; }', 'acl purge { ' . $acl . ' }' );
$v = $sub( $v, 'change-me-long-random-secret', getenv( 'KEY' ) );
if ( $variant === 'noregex' ) { $v = $sub( $v, 'req.http.X-Purge-Method == "regex"', 'req.http.X-Purge-Method == "__never__"' ); }
if ( $variant === 'nopurge' ) { $v = $sub( $v, 'req.method == "PURGE"', 'req.method == "__never__"' ); }
if ( getenv( 'LEGACY_BAN' ) === '1' ) {
    $n = 0;
    $v = preg_replace( '#if \(std\.ban\((.*?)\)\) \{\s*return \(?synth\(200, "Banned"\)\)?;\s*\}\s*return \(?synth\(400, std\.ban_error\(\)\)\)?;#s',
                       "ban(\\1);\n            return (synth(200, \"Banned\"));", $v, 1, $n );
    if ( $n !== 1 ) { fwrite( STDERR, "cannot rewrite the std.ban() block for this Varnish - update actionstart-varnish.sh\n" ); exit( 2 ); }
}
echo $v . "\nbackend default { .host = \"" . getenv( 'BACKEND_HOST' ) . "\"; .port = \"" . getenv( 'BACKEND_PORT' ) . "\"; }\n";
PHPEOF
[ -s "$TMPV" ] || die "generated VCL is empty"
chmod 644 "$TMPV"
docker cp "$TMPV" "$VC:$VCL_REMOTE"
VCL_NAME="npp$(date +%s)"
LOAD_OUT="$(vx varnishadm vcl.load "$VCL_NAME" "$VCL_REMOTE" 2>&1)" || { printf '%s\n' "$LOAD_OUT" >&2; die "varnishadm vcl.load failed: the VCL does not compile on this Varnish (the previous VCL stays active)"; }
vx varnishadm vcl.use "$VCL_NAME" >/dev/null 2>&1 || die "varnishadm vcl.use $VCL_NAME failed"
ok "VCL '$VCL_NAME' compiled and active (variant $VCL_VARIANT, control key set); kept at $VC:$VCL_REMOTE"
[ "$VCL_VARIANT" = example ] || warn "variant '$VCL_VARIANT' is a deliberately BROKEN VCL: the wiring checks below are expected to fail"

step "7/8 Pointing NPP at the topology"
rx mkdir -p /tmp/wp-home; rx chown "$WP_USER" /tmp/wp-home
wait_for "WordPress installed (wp core is-installed)" wpc core is-installed
wait_for "NPP plugin active" wpc plugin is-active "$PLUGIN_SLUG"
rx mkdir -p "$D/run"
if ! rx test -f "$D/run/prev_custom_url"; then      # remember the value we replace, once
    PREV="$(wpc option pluck nginx_cache_settings nppp_http_purge_custom_url 2>/dev/null | tr -d '\r\n' || true)"
    rx sh -c "printf '%s' '${PREV:-$HOME_FALLBACK_URL}' > '$D/run/prev_custom_url'"
fi
if [ "$VARNISH_ONLY" -eq 1 ]; then
    # Varnish-only: nginx has no cache. By default HTTP Purge has nothing to talk to (no :8443 listener), so it is
    # switched OFF like on a real VO site (--vo-http-purge keeps it ON, see below). NPP itself never couples the two:
    # in VO it simply does not call HTTP Purge. "Nginx Cache Directory" becomes an empty scratch directory for the crawler.
    MOUNT_DIR_C="$(rx printenv MOUNT_DIR 2>/dev/null | tr -d '\r\n' || true)"; MOUNT_DIR_C="${MOUNT_DIR_C:-/var/cache/nginx-npp}"
    if ! rx test -f "$D/run/prev_http_purge"; then
        PREV_HP="$(wpc option pluck nginx_cache_settings nppp_http_purge_enabled 2>/dev/null | tr -d '\r\n' || true)"
        rx sh -c "printf '%s' '${PREV_HP:-yes}' > '$D/run/prev_http_purge'"
    fi
    if ! rx test -f "$D/run/prev_cache_path"; then
        PREV_CP="$(wpc option pluck nginx_cache_settings nginx_cache_path 2>/dev/null | tr -d '\r\n' || true)"
        { [ -z "$PREV_CP" ] || [ "$PREV_CP" = "$VO_SCRATCH" ]; } && PREV_CP="$MOUNT_DIR_C"
        rx sh -c "printf '%s' '$PREV_CP' > '$D/run/prev_cache_path'"
    fi
    if rx test -d "$VO_SCRATCH"; then
        ok "scratch directory $VO_SCRATCH exists, left as is"
    else
        rx mkdir -p "$VO_SCRATCH"
        rx chown "$WP_USER:$(rx id -gn "$WP_USER" | tr -d '\r\n')" "$VO_SCRATCH"
        rx chmod 750 "$VO_SCRATCH"
        ok "scratch directory $VO_SCRATCH created (owner $WP_USER, empty)"
    fi
    rx runuser -u "$WP_USER" -- test -w "$VO_SCRATCH" || die "$VO_SCRATCH is not writable by $WP_USER (NPP would show GLOBAL ERROR PERMISSION)"
    STRAY="$(rx sh -c "find '$VO_SCRATCH' -mindepth 1 -maxdepth 1 ! -name tmp | head -n 3" | tr -d '\r' || true)"
    if [ -n "$STRAY" ]; then
        warn "$VO_SCRATCH is not empty: the Advanced tab will list these files as cache entries (HIT). Expected only when you chose this directory on purpose (--vo-scratch):"
        sed 's/^/        /' <<<"$STRAY" >&2
    fi
    if [ "$VO_HTTP_PURGE" -eq 1 ]; then
        set_npp nppp_http_purge_enabled yes
        set_npp nppp_http_purge_custom_url "https://$NGX:8443"
        set_npp nppp_http_purge_queue_status_path npp_purge_status
    else
        set_npp nppp_http_purge_enabled no
    fi
    set_npp nppp_varnish_endpoints "http://$VC:80" lenient
    set_npp nppp_varnish_header "X-Control-Key: $KEY"
    set_npp nppp_varnish_sync_enabled yes
    set_npp nginx_cache_path "$VO_SCRATCH" lenient
    set_npp nppp_varnish_only_enabled yes     # last: VO only exists while sync is ON with a valid endpoint
    reset_varnish_state
    if [ "$VO_HTTP_PURGE" -eq 1 ]; then
        ok "HTTP Purge ON -> https://$NGX:8443 (idle listener, status endpoint npp_purge_status)"
    else
        ok "HTTP Purge OFF (no Nginx cache, no :8443 purge listener in this topology)"
    fi
    ok "Varnish sync ON -> http://$VC:80 with X-Control-Key"
    ok "Varnish-only mode ON, Nginx Cache Directory = $VO_SCRATCH"
else
    # A non-VO topology must never run with VO left ON by an earlier --varnish-only run: that is exactly the
    # "Varnish-only mode over a real Nginx cache" mismatch (Purge All reports success and leaves the Nginx cache).
    set_npp nppp_varnish_only_enabled no
    if rx test -f "$D/run/prev_cache_path"; then
        set_npp nginx_cache_path "$(rx cat "$D/run/prev_cache_path" | tr -d '\r\n')" lenient
        rx rm -f "$D/run/prev_cache_path" "$D/run/prev_http_purge"
        ok "left Varnish-only mode: Nginx Cache Directory restored"
    fi
    set_npp nppp_http_purge_enabled yes
    set_npp nppp_http_purge_custom_url "https://$NGX:8443"
    set_npp nppp_http_purge_queue_status_path npp_purge_status
    set_npp nppp_varnish_endpoints "http://$VC:80" lenient
    set_npp nppp_varnish_header "X-Control-Key: $KEY"
    set_npp nppp_varnish_sync_enabled yes
    reset_varnish_state
    ok "HTTP Purge -> https://$NGX:8443 (https on purpose: NPP only trusts a purge answer when the scheme equals the page scheme)"
    ok "Varnish sync ON -> http://$VC:80 with X-Control-Key, Varnish-only mode OFF"
fi

# ---------------------------------------------------------- 8. wiring checks ----
step "8/8 Wiring checks (not plugin tests: do the pieces see each other the way the VCL/vhost assume?)"
PASSED=0; FAILED=0
chk() {  # chk "<label>" <expected> <actual>
    if [ "$2" = "$3" ]; then ok "$1 -> $3"; PASSED=$((PASSED + 1)); else printf '    %s[FAIL]%s %s -> %s (expected %s)\n' "$R" "$N" "$1" "$3" "$2" >&2; FAILED=$((FAILED + 1)); fi
}
code() { rx curl -sk -o /dev/null -w '%{http_code}' --max-time 15 "$@" 2>/dev/null || true; }
nids() {  # number of ids in X-Varnish of a GET through the edge (1 = MISS, 2 = HIT, 0 = header absent)
    local h
    h="$(rx curl -sk -o /dev/null -D - --max-time 20 -H "Host: $SITE_HOST" "https://$NGX$1" 2>/dev/null | tr -d '\r' || true)"
    awk 'tolower($1)=="x-varnish:" {print NF-1; f=1} END{if(!f) print 0}' <<<"$h"
}
hdrs() { rx curl -sk -o /dev/null -D - --max-time 20 -H "Host: $SITE_HOST" "https://$NGX$1" 2>/dev/null | tr -d '\r' || true; }
P="/npp-wiring-$$"

chk "PURGE php->varnish with control key"               200 "$(code -X PURGE -H "Host: $SITE_HOST" -H "X-Control-Key: $KEY" "http://$VC:80$P")"
if [ "$VCL_VARIANT" = example ]; then
    chk "PURGE php->varnish WITHOUT control key"        403 "$(code -X PURGE -H "Host: $SITE_HOST" "http://$VC:80$P")"
    chk "PURGE php->varnish wrong control key"          403 "$(code -X PURGE -H "Host: $SITE_HOST" -H 'X-Control-Key: wrong' "http://$VC:80$P")"
fi
chk "PURGE from a visitor through the edge (:443)"      405 "$(code -X PURGE -H "Host: $SITE_HOST" -H "X-Control-Key: $KEY" "https://$NGX/")"
chk "/npp_purge_all through the edge"                   404 "$(code -H "Host: $SITE_HOST" "https://$NGX/npp_purge_all")"
chk "/npp_purge_all on the origin (:8080)"              404 "$(code -H "Host: $SITE_HOST" "http://$NGX:8080/npp_purge_all")"
if [ "$VO_HTTP_PURGE" -eq 1 ]; then
    chk "idle purge listener unknown path (:8443)"          404 "$(code -H "Host: $SITE_HOST" "https://$NGX:8443/nothing")"
    chk "idle purge listener status (:8443/npp_purge_status)" 200 "$(code -H "Host: $SITE_HOST" "https://$NGX:8443/npp_purge_status")"
elif [ "$VARNISH_ONLY" -eq 1 ]; then
    chk "no purge listener on :8443 (connection refused)" 000 "$(code -H "Host: $SITE_HOST" "https://$NGX:8443/npp_purge_status")"
else
    chk "purge listener unknown path (:8443)"               404 "$(code -H "Host: $SITE_HOST" "https://$NGX:8443/nothing")"
    chk "purge listener status (:8443/npp_purge_status)"    200 "$(code -H "Host: $SITE_HOST" "https://$NGX:8443/npp_purge_status")"
fi
VO_VIEW="$(wpc eval "$WP_BOOT"'echo function_exists("nppp_varnish_only_mode") ? (nppp_varnish_only_mode() ? "ACTIVE" : "off") : "n/a";' 2>/dev/null | tr -d '\r\n' || true)"
[ "$VARNISH_ONLY" -eq 1 ] || { [ "$VO_VIEW" != "n/a" ] || VO_VIEW=off; }   # a plugin build without VO is "off" by definition
chk "NPP sees Varnish-only mode as" "$([ "$VARNISH_ONLY" -eq 1 ] && echo ACTIVE || echo off)" "$VO_VIEW"

# Varnish-only: nginx must not write a single cache file. A unique path guarantees the request reaches the origin.
if [ "$VARNISH_ONLY" -eq 1 ]; then
    NGX_CACHE_DIR="$(env_val NPP_NGINX_CACHE_PATH_)"; NGX_CACHE_DIR="${NGX_CACHE_DIR:-/var/cache/nginx}"
    nginx_cache_files() { docker exec "$NGX" sh -c "find '$NGX_CACHE_DIR' -type f 2>/dev/null | wc -l" | tr -d ' \r\n'; }
    CF0="$(nginx_cache_files)"
    OH="$(hdrs "/npp-vo-origin-$$/")"
    grep -qi '^x-npp-origin:' <<<"$OH" && { ok "unique URL reached the Varnish-only origin (X-NPP-Origin present)"; PASSED=$((PASSED + 1)); } \
        || { printf '    %s[FAIL]%s unique URL: X-NPP-Origin missing, the response did not come from the Varnish-only vhost\n' "$R" "$N" >&2; FAILED=$((FAILED + 1)); }
    chk "nginx cache dir $NGX_CACHE_DIR gained no file (Nginx has no cache)" "$CF0" "$(nginx_cache_files)"
fi

# Both layers on a real page: Varnish in the path, nginx fastcgi_cache behind it, regex ban reaches the object.
PG="/"
hdrs "$PG" >/dev/null
SECOND="$(hdrs "$PG")"
IDS="$(awk 'tolower($1)=="x-varnish:" {print NF-1; f=1} END{if(!f) print 0}' <<<"$SECOND")"
if [ "$IDS" != 2 ]; then
    printf '    %s[FAIL]%s edge GET twice: second response is not a Varnish HIT (X-Varnish ids: %s). Response headers:\n' "$R" "$N" "$IDS" >&2
    sed 's/^/        /' <<<"$SECOND" >&2; FAILED=$((FAILED + 1))
else
    ok "edge GET twice: 2nd is a Varnish HIT (X-Varnish ids: $IDS)"; PASSED=$((PASSED + 1))
    if [ "$VARNISH_ONLY" -eq 1 ]; then
        if grep -qi '^npp-fastcgi-cache:' <<<"$SECOND"; then
            printf '    %s[FAIL]%s NPP-FastCGI-Cache header present: nginx still has a cache layer (wrong vhost?)\n' "$R" "$N" >&2; FAILED=$((FAILED + 1))
        else
            ok "no NPP-FastCGI-Cache header: Varnish is the only cache layer"; PASSED=$((PASSED + 1))
        fi
        grep -qi '^x-npp-origin:' <<<"$SECOND" && { ok "origin marker X-NPP-Origin present"; PASSED=$((PASSED + 1)); } \
            || { printf '    %s[FAIL]%s X-NPP-Origin missing: the response did not come from the Varnish-only vhost\n' "$R" "$N" >&2; FAILED=$((FAILED + 1)); }
    else
        grep -qi '^npp-fastcgi-cache:' <<<"$SECOND" && { ok "nginx layer header NPP-FastCGI-Cache present"; PASSED=$((PASSED + 1)); } \
            || { printf '    %s[FAIL]%s NPP-FastCGI-Cache header missing: the response did not come from the origin vhost\n' "$R" "$N" >&2; FAILED=$((FAILED + 1)); }
    fi
    if [ "$VCL_VARIANT" = example ]; then
        chk "regex ban (Purge All shape) accepted"      200 "$(code -X PURGE -H "Host: $SITE_HOST" -H "X-Control-Key: $KEY" -H 'X-Purge-Method: regex' "http://$VC:80/.*")"
        chk "page is a MISS in Varnish after the ban"   1   "$(nids "$PG")"
        if [ "$VARNISH_ONLY" -eq 1 ]; then
            # The plugin's own Purge All (the code path of the admin bar button), not a hand-made PURGE.
            hdrs "$PG" >/dev/null                                     # the check above left it cached again (MISS stores it)
            chk "page is a Varnish HIT again before NPP Purge All" 2 "$(nids "$PG")"
            purge_all_hits() { { docker logs "$NGX" 2>&1 || true; } | { grep -c '/npp_purge_all' || true; }; }
            PA0="$(purge_all_hits)"
            NPP_OUT="$(wpc npp purge 2>&1)" && NPP_RC=0 || NPP_RC=$?
            chk "wp npp purge (Purge All in VO) exit code"          0 "$NPP_RC"
            sed 's/^/        plugin: /' <<<"$NPP_OUT"
            if [ "$VO_HTTP_PURGE" -eq 1 ]; then
                # HTTP Purge is ON but VO must skip it: nginx must not have logged one /npp_purge_all request meanwhile.
                chk "HTTP Purge ON, VO active: NPP sent no /npp_purge_all to nginx" "$PA0" "$(purge_all_hits)"
            fi
            chk "page is a MISS in Varnish after wp npp purge"      1 "$(nids "$PG")"
        fi
    fi
fi

echo
if [ "$FAILED" -ne 0 ] && [ "$VCL_VARIANT" != example ]; then
    # A deliberately broken VCL fails some wiring checks by design: the topology tests classify it by behaviour.
    printf '%sBROKEN VCL (%s): %s wiring check(s) failed as expected, handing over to the topology tests%s\n' "$Y" "$VCL_VARIANT" "$FAILED" "$N"
elif [ "$FAILED" -ne 0 ]; then
    printf '%sWIRING CHECKS FAILED (%s ok, %s failed)%s\n' "$R" "$PASSED" "$FAILED" "$N"
    echo "  varnish log   : docker logs $VC | tail -n 30"
    echo "  active VCL    : docker exec $VC cat $VCL_REMOTE"
    echo "  nginx log     : docker logs $NGX | tail -n 30"
    echo "  state         : ./actionstart-varnish.sh --status"
    [ "$VCL_VARIANT" = example ] || echo "  (variant '$VCL_VARIANT' was installed on purpose)"
    exit 1
fi
if [ "$FAILED" -eq 0 ]; then printf '%sWIRING OK (%s checks)%s\n' "$G" "$PASSED" "$N"; fi

[ "$MODE" = prepare ] && { echo "  prepared: topology is up, VCL installed, NPP configured"; exit 0; }

# ------------------------------------------------------------- VO: hand over to the admin ----
if [ "$VARNISH_ONLY" -eq 1 ]; then
    ok "run-topology-tests.sh skipped: it asserts the Nginx layer (NPP-FastCGI-Cache, working :8443 purge), which VO does not have"
    [ "${#PASS[@]}" -eq 0 ] || warn "ignored arguments for the topology tests: ${PASS[*]}"
    echo
    echo "  Varnish-only lab is ready. NPP: Varnish-only mode ON, HTTP Purge $([ "$VO_HTTP_PURGE" -eq 1 ] && echo ON || echo OFF), Nginx Cache Directory = $VO_SCRATCH"
    echo "  by hand : curl -sk -I -H 'Host: $SITE_HOST' https://localhost/ | grep -iE 'x-varnish|^age|x-npp-origin|npp-fastcgi'"
    echo "            expect X-NPP-Origin, NO NPP-FastCGI-Cache; the 2nd request shows two ids in X-Varnish (HIT)"
    echo "  wp-admin: Purge All / Preload All (admin bar), then the Status and Advanced tabs"
    echo "  plugin  : ./actionstart-varnish.sh --shell   then: runuser -u $WP_USER -- wp --path=$WP_PATH npp log"
    echo "  state   : ./actionstart-varnish.sh --status"
    echo "  other   : ./actionstart-varnish.sh --topology   (back to Varnish in front of an Nginx cache, VO off)"
    echo "  cleanup : ./actionstart-varnish.sh --clean"
    exit 0
fi

# ------------------------------------------------------------ topology tests ----
if rx test -x "$D/run-topology-tests.sh"; then
    step "Running run-topology-tests.sh ${PASS[*]:-(happy faults)}"
    CACHE_DIR="$(env_val NPP_NGINX_CACHE_PATH_)"; CACHE_DIR="${CACHE_DIR:-/var/cache/nginx}"
    set +e
    docker exec -u root \
        -e "WP_PATH=$WP_PATH" -e "WP_USER=$WP_USER" -e "NPPP_INCLUDES=$INC" \
        -e "TOPO_SITE_HOST=$SITE_HOST" -e "TOPO_EDGE=https://$NGX" -e "TOPO_ORIGIN=http://$NGX:8080" \
        -e "TOPO_PURGE=https://$NGX:8443" -e "TOPO_VARNISH=http://$VC:80" -e "TOPO_KEY=$KEY" \
        -e "TOPO_VARNISH_CONTAINER=$VC" -e "TOPO_ACL_MODE=$ACL_MODE" -e "TOPO_PHP_IP=$PHP_IP" \
        -e "TOPO_VCL_VARIANT=$VCL_VARIANT" -e "NPP_NGINX_CACHE_PATH=$CACHE_DIR" \
        "$C" "$D/run-topology-tests.sh" ${PASS[@]+"${PASS[@]}"}
    RC=$?
    set -e
    echo
    case "$RC" in
        0)  printf '%sALL CHECKS PASSED%s\n' "$G" "$N" ;;
        77) printf '%sNOTHING RAN: every section was skipped (exit 77)%s\n' "$Y" "$N" ;;
        *)  printf '%sTESTS FAILED (exit %s)%s\n' "$R" "$RC" "$N" ;;
    esac
    echo "  cleanup : ./actionstart-varnish.sh --clean"
    exit "$RC"
fi
warn "$D/run-topology-tests.sh is missing in the deployed plugin: NO topology test ran (the wiring checks above are not the tests)"
echo "  try it by hand:  curl -sk -I -H 'Host: $SITE_HOST' https://localhost/   (X-Varnish ids + NPP-FastCGI-Cache = both layers)"
echo "                   ./actionstart-varnish.sh --shell   then: runuser -u $WP_USER -- wp --path=$WP_PATH npp purge   (Purge All)"
echo "  cleanup : ./actionstart-varnish.sh --clean"
exit 2
