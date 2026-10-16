#!/usr/bin/env bash
#
# NPP HTTP Purge test suit runner for Docker stack.
#
# Brings the stack up with the lab override, makes sure the test is in the wordpress-fpm
# container (outside the web root, volume npp_purge_lab), installs the build tooling once and
# runs http-purge-test/run-purge-tests.sh against the plugin deployed in the stack.
#
# Usage (on the Docker host, from the directory containing docker-compose.yml):
#   ./actionstart-purge.sh                                       mock harness + real-nginx matrix (ngx_cache_purge v4 build)
#   ./actionstart-purge.sh --only mock                           mock harness only (seconds, no nginx build)
#   ./actionstart-purge.sh --only matrix sync ambig              just those real-nginx scenarios
#   ./actionstart-purge.sh --ng v30 --only matrix sync ambig     other module build (v4 | v30 | v25)
#   ./actionstart-purge.sh --src ../plugin/http-purge-test       copy the test from a local checkout first
#   ./actionstart-purge.sh --file ./includes/purge-http.php      test this file instead of the deployed one
#   ./actionstart-purge.sh --build                               rebuild images while bringing the stack up
#   ./actionstart-purge.sh --no-run                              prepare only, do not run the tests
#   ./actionstart-purge.sh --shell                               root shell in the lab directory
#   ./actionstart-purge.sh --clean                               stop harness nginx/php-fpm/delay proxy, keep nginx builds
#   ./actionstart-purge.sh --purge                               --clean + delete the nginx builds (ng/, build/)
# Overrides: C, WP_PATH, LAB_DIR, WAIT
# The first matrix run compiles nginx + ngx_cache_purge inside the container.
set -euo pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$STACK_DIR"

C="${C:-wordpress-fpm}"
WP_PATH="${WP_PATH:-/var/www/html}"
WAIT="${WAIT:-300}"
PLUGIN_SLUG="fastcgi-cache-purge-and-preload-nginx"
D="${LAB_DIR:-/opt/npp-http-purge-test}"
COMPOSE=(docker compose -f docker-compose.yml -f docker-compose.lab.yml)

if [ -t 1 ]; then R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[36m'; N=$'\033[0m'; else R=; G=; Y=; B=; N=; fi
step() { printf '%s==>%s %s\n' "$B" "$N" "$*"; }
ok()   { printf '    %s[ok]%s %s\n' "$G" "$N" "$*"; }
warn() { printf '    %s[!!]%s %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '%s[xx] %s%s\n' "$R" "$*" "$N" >&2; exit 1; }
rx()   { docker exec -u root "$C" "$@"; }

MODE=run; BUILD=0; SRC=""; FILE=""; PASS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --build)   BUILD=1 ;;
        --no-run)  MODE=prepare ;;
        --clean)   MODE=clean ;;
        --purge)   MODE=purge ;;
        --shell)   MODE=shell ;;
        --src)     SRC="${2:?--src DIR}"; shift ;;
        --file)    FILE="${2:?--file FILE}"; shift ;;
        -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d;s/^# \{0,1\}//'; exit 0 ;;
        *)         PASS+=("$1") ;;
    esac
    shift
done

need_docker() {
    command -v docker >/dev/null 2>&1 || die "docker not found"
    docker compose version >/dev/null 2>&1 || die "'docker compose' plugin (v2) not found"
    [ -f docker-compose.lab.yml ] || die "docker-compose.lab.yml missing - run this from the stack repo"
}
running()     { [ "$(docker inspect -f '{{.State.Running}}' "$C" 2>/dev/null || echo false)" = true ]; }
lab_mounted() { rx sh -c "grep -qs ' $D ' /proc/self/mounts" 2>/dev/null; }
wait_for() {  # wait_for "<label>" <cmd...>
    local label="$1"; shift
    local t0=$SECONDS
    until "$@" >/dev/null 2>&1; do
        [ $((SECONDS - t0)) -ge "$WAIT" ] && die "timeout (${WAIT}s) waiting for: $label"
        sleep 3
    done
    ok "$label ($((SECONDS - t0))s)"
}

mode_clean() {
    need_docker
    running || die "container $C is not running"
    step "Stopping harness nginx, php-fpm and delay proxy"
    rx sh -c "pkill -f 'delayproxy[.]py' || true
              for pf in $D/ng/*/logs/nginx.pid; do [ -f \"\$pf\" ] && kill \"\$(cat \"\$pf\")\" 2>/dev/null || true; done
              [ -f /tmp/fpm.pid ] && kill \"\$(cat /tmp/fpm.pid)\" 2>/dev/null || true
              rm -rf /tmp/npp-cache /tmp/npp-other /tmp/npp-temp /tmp/fpm.sock /tmp/fpm.pid /tmp/fpm.log"
    ok "stopped"
    if [ "$MODE" = purge ]; then
        step "Deleting nginx builds (ng/, build/) and run/"
        rx rm -rf "$D/ng" "$D/build" "$D/run"
    fi
    exit 0
}
mode_shell() {
    need_docker; running || die "container $C is not running"
    exec docker exec -it -u root -w "$D" -e WP_PATH="$WP_PATH" "$C" bash
}
[ "$MODE" = clean ] || [ "$MODE" = purge ] && mode_clean
[ "$MODE" = shell ] && mode_shell

need_docker
step "1/6 Preflight"
if [ ! -f .env ]; then
    cp .env.example .env
    warn ".env was missing - copied from .env.example (placeholder passwords, fine for a local lab)"
fi
grep -Eq '^(export )?NPP_EDGE_=1' .env || warn "NPP_EDGE_ is not 1 in .env: the plugin would come from wordpress.org and has no http-purge-test/"
[ -z "$SRC" ] || [ -f "$SRC/run-purge-tests.sh" ] || die "--src $SRC has no run-purge-tests.sh"
[ -z "$FILE" ] || [ -f "$FILE" ] || die "--file $FILE not found"
ok "docker compose ready, lab dir $D"

step "2/6 Bringing the stack up with the lab override"
UP=(up -d); [ "$BUILD" -eq 1 ] && UP+=(--build)
"${COMPOSE[@]}" "${UP[@]}"
if running && ! lab_mounted; then
    warn "container runs without the npp_purge_lab volume - recreating wordpress with the lab override"
    "${COMPOSE[@]}" up -d --force-recreate wordpress
fi
wait_for "container $C running" running
wait_for "npp_purge_lab mounted at $D" lab_mounted

step "3/6 Waiting for WordPress + NPP (wp-post.sh writes .npp-ready when the plugin deploy is done)"
wait_for "wp-post.sh finished" rx test -f "$WP_PATH/.npp-ready"
rx test -f "$WP_PATH/wp-content/plugins/$PLUGIN_SLUG/includes/purge-http.php" || die "plugin not deployed in $WP_PATH"
ok "plugin deployed"

step "4/6 Harness in $D"
if [ -n "$SRC" ]; then
    docker cp "$SRC/." "$C:$D/"
    rx sh -c "chmod 755 '$D'; chmod u+x '$D'/*.sh '$D'/*.py"
    ok "copied from $SRC"
fi
rx test -f "$D/run-purge-tests.sh" || die "$D/run-purge-tests.sh missing: commit http-purge-test/ to the plugin branch (wp-post.sh installs it on the next deploy) or pass --src <checkout>/http-purge-test"
ok "$D/run-purge-tests.sh present"
if [ -n "$FILE" ]; then
    rx mkdir -p "$D/run"
    docker cp "$FILE" "$C:$D/run/candidate-purge-http.php"
    ok "testing $FILE (copied to $D/run/candidate-purge-http.php)"
fi

step "5/6 Tooling inside $C"
NEED_MATRIX=1
for a in ${PASS[@]+"${PASS[@]}"}; do [ "$a" = mock ] && NEED_MATRIX=0; done
if [ "$NEED_MATRIX" -eq 1 ]; then
    MISSING="$(rx sh -c 'for t in python3 gcc make git curl pgrep seq xargs chattr lsattr; do command -v $t >/dev/null || printf "%s " $t; done')"
    if [ -n "$MISSING" ] || ! rx sh -c 'dpkg -s libpcre2-dev zlib1g-dev libssl-dev >/dev/null 2>&1'; then
        warn "build tooling missing (${MISSING:-dev libs}) - installing (lost on container recreate; the nginx builds stay in the volume)"
        rx sh -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends python3 build-essential libpcre2-dev zlib1g-dev libssl-dev git curl procps e2fsprogs >/dev/null'
    fi
    ok "python3 gcc make git curl libpcre2/zlib/openssl dev"
else
    ok "mock harness needs only php"
fi

[ "$MODE" = prepare ] && { step "Prepared. Run the tests with: ./actionstart-purge.sh --only mock"; exit 0; }

step "6/6 Running ${PASS[*]:-mock + matrix (v4)}"
ENVS=(-e "WP_PATH=$WP_PATH")
[ -n "$FILE" ] && ENVS+=(-e "PLUGIN_FILE=$D/run/candidate-purge-http.php")
RUNARGS=(--build); [ "$NEED_MATRIX" -eq 0 ] && RUNARGS=()
set +e
docker exec -u root "${ENVS[@]}" "$C" "$D/run-purge-tests.sh" ${RUNARGS[@]+"${RUNARGS[@]}"} ${PASS[@]+"${PASS[@]}"}
RC=$?
set -e
echo
if [ "$RC" -eq 0 ]; then
    printf '%sALL CHECKS PASSED%s\n' "$G" "$N"
else
    printf '%sTESTS FAILED (exit %s)%s\n' "$R" "$RC" "$N"
    echo "  nginx error log  : docker exec $C sh -c 'tail -n 50 $D/ng/*/logs/error.log'"
    echo "  shell in lab dir : ./actionstart-purge.sh --shell"
fi
echo "  cleanup          : ./actionstart-purge.sh --clean   (or --purge to drop the nginx builds)"
exit "$RC"
