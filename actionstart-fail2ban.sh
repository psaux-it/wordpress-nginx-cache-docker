#!/usr/bin/env bash
# one-command bootstrap for the NPP Fail2ban-test e2e lab
# inside the wordpress-nginx-cache-docker stack.
#
# Run it on the DOCKER HOST, from the stack directory (where docker-compose.yml is).
#
#   ./actionstart.sh                       prepare everything, run all phases
#   ./actionstart.sh --only happy,faults   prepare + run selected phases
#   ./actionstart.sh --with-ratelimit      also run the ratelimit phase
#   ./actionstart.sh --count 100           more IPs in the happy phase
#   ./actionstart.sh --build               rebuild images while bringing the stack up
#   ./actionstart.sh --no-run              prepare only (stack, python3, lab wiring)
#   ./actionstart.sh --clean               stop fake RIPEstat, remove mu-plugin + lab CA
#   ./actionstart.sh --purge               --clean + delete pki/ run/ + drop the lab hosts override
#   ./actionstart.sh --shell               root shell in the fail2ban-test directory
#
# Everything the lab needs (driver, fake RIPEstat, plugin PHP worker) must share
# one /etc/hosts and one loopback, so all test steps run INSIDE the wordpress-fpm
# container via `docker exec`. Pass-through args (--only/--count/--timeout/
# --with-ratelimit) go straight to run-e2e.sh.
#
# Overridable environment:
#   C          wordpress container name     (default: wordpress-fpm)
#   WP_USER    PHP-FPM pool user            (default: NPP_USER_ from .env, else npp)
#   SITE_URL   URL the driver calls         (default: https://nginx, compose network)
#   WP_PATH    WordPress root in container  (default: /var/www/html)
#   MIN_NPP    minimum plugin version       (default: 2.1.8)
#   WAIT       seconds to wait for stack    (default: 300)
set -euo pipefail

# ---------------------------------------------------------------- config ----
STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$STACK_DIR"

C="${C:-wordpress-fpm}"
WP_PATH="${WP_PATH:-/var/www/html}"
SITE_URL="${SITE_URL:-https://nginx}"
MIN_NPP="${MIN_NPP:-2.1.8}"
WAIT="${WAIT:-300}"
PLUGIN_SLUG="fastcgi-cache-purge-and-preload-nginx"
D="$WP_PATH/wp-content/plugins/$PLUGIN_SLUG/fail2ban-test"
COMPOSE=(docker compose -f docker-compose.yml -f docker-compose.lab.yml)
COMPOSE_BASE=(docker compose -f docker-compose.yml)

if [ -z "${WP_USER:-}" ]; then
    WP_USER="$(sed -nE 's/^(export )?NPP_USER_=//p' .env 2>/dev/null | tail -n1 | tr -d "\"' \r" || true)"
    WP_USER="${WP_USER:-npp}"
fi

# ---------------------------------------------------------------- output ----
if [ -t 1 ]; then R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[36m'; N=$'\033[0m'; else R=; G=; Y=; B=; N=; fi
step() { printf '%s==>%s %s\n' "$B" "$N" "$*"; }
ok()   { printf '    %s[ok]%s %s\n' "$G" "$N" "$*"; }
warn() { printf '    %s[!!]%s %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '%s[xx] %s%s\n' "$R" "$*" "$N" >&2; exit 1; }

dx()   { docker exec "$@"; }                       # docker exec shorthand
rx()   { docker exec -u root "$C" "$@"; }          # as root in the container

# ------------------------------------------------------------- arg parse ----
MODE=run; BUILD=0; PASS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --build)   BUILD=1 ;;
        --no-run)  MODE=prepare ;;
        --clean)   MODE=clean ;;
        --purge)   MODE=purge ;;
        --shell)   MODE=shell ;;
        -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d;s/^# \{0,1\}//'; exit 0 ;;
        *)         PASS+=("$1") ;;
    esac
    shift
done

# --------------------------------------------------------------- helpers ----
need_docker() {
    command -v docker >/dev/null 2>&1 || die "docker not found"
    docker compose version >/dev/null 2>&1 || die "'docker compose' plugin (v2) not found"
    [ -f docker-compose.lab.yml ] || die "docker-compose.lab.yml missing - run this from the stack repo"
}

running() { [ "$(docker inspect -f '{{.State.Running}}' "$C" 2>/dev/null || echo false)" = true ]; }

hosts_ok() { rx sh -c "getent ahosts stat.ripe.net | head -n1 | grep -q '^127\.0\.0\.2'" 2>/dev/null; }

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

ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }   # ver_ge have need

# ----------------------------------------------------------------- modes ----
mode_clean() {
    need_docker
    running || die "container $C is not running"
    step "Stopping fake RIPEstat"
    rx sh -c "pkill -f 'fake_ripestat[.]py' || true; rm -f '$D/run/fake_ripestat.pid'"
    ok "stopped"
    step "Removing f2b-lab mu-plugin and lab CA (LAB_IN_DOCKER=1)"
    rx env LAB_IN_DOCKER=1 "$D/setup-lab.sh" --remove "$WP_PATH" || warn "setup-lab.sh --remove failed (already clean?)"
    if [ "$MODE" = purge ]; then
        step "Deleting pki/ and run/"
        rx rm -rf "$D/pki" "$D/run"
        step "Recreating wordpress without the lab hosts override"
        "${COMPOSE_BASE[@]}" up -d --force-recreate wordpress
        warn "container recreated: python3 is gone, it will be reinstalled on the next run"
    fi
    step "Verify"
    rx sh -c "pgrep -fl 'fake_ripestat[.]py' || echo 'fake RIPEstat: stopped'"
    rx sh -c "ls '$WP_PATH/wp-content/mu-plugins/f2b-lab.php' 2>&1 || true"
    exit 0
}

mode_shell() {
    need_docker; running || die "container $C is not running"
    exec docker exec -it -u root -w "$D" -e WP_USER="$WP_USER" -e SITE_URL="$SITE_URL" -e WP_PATH="$WP_PATH" "$C" bash
}

[ "$MODE" = clean ] || [ "$MODE" = purge ] && mode_clean
[ "$MODE" = shell ] && mode_shell

# ------------------------------------------------------------ 1. stack up ----
need_docker
step "1/7 Preflight"
if [ ! -f .env ]; then
    cp .env.example .env
    warn ".env was missing - copied from .env.example (placeholder passwords, fine for a local lab)"
fi
grep -Eq '^(export )?NPP_EDGE_=1' .env || warn "NPP_EDGE_ is not 1 in .env: the plugin would come from wordpress.org and may lack fail2ban-test/"
ok "docker compose ready, WP_USER=$WP_USER SITE_URL=$SITE_URL"

step "2/7 Bringing the stack up with the lab override (stat.ripe.net -> 127.0.0.2)"
UP=(up -d); [ "$BUILD" -eq 1 ] && UP+=(--build)
"${COMPOSE[@]}" "${UP[@]}"
if running && ! hosts_ok; then
    warn "container runs without the stat.ripe.net hosts entry - recreating wordpress with the lab override"
    "${COMPOSE[@]}" up -d --force-recreate wordpress
fi
wait_for "container $C running" running
wait_for "stat.ripe.net resolves to 127.0.0.2 inside $C" hosts_ok

step "3/7 Waiting for WordPress + NPP (wp-post.sh finishes the plugin deploy)"
wait_for "WordPress installed" rx sh -c "[ -f '$WP_PATH/wp-load.php' ]"
rx mkdir -p /tmp/wp-home && rx chown "$WP_USER" /tmp/wp-home
wait_for "wp core is-installed" wpc core is-installed
wait_for "NPP plugin active" wpc plugin is-active "$PLUGIN_SLUG"
wait_for "nginx answers $SITE_URL" rx curl -ksf -o /dev/null "$SITE_URL/wp-json/"

step "4/7 Checking plugin version and fail2ban-test/"
NPP_VER="$(wpc plugin get "$PLUGIN_SLUG" --field=version 2>/dev/null | tr -d '\r\n')"
[ -n "$NPP_VER" ] || die "could not read NPP version via WP-CLI"
ver_ge "$NPP_VER" "$MIN_NPP" || die "NPP $NPP_VER < $MIN_NPP (no Fail2Ban subsystem). Set NPP_EDGE_=1 in .env and recreate wordpress."
ok "NPP $NPP_VER (>= $MIN_NPP)"
[ "$NPP_VER" = "$MIN_NPP" ] || warn "stack deploys the LATEST v* branch, deployed is $NPP_VER (tests of $MIN_NPP may differ slightly)"
rx sh -c "[ -x '$D/run-e2e.sh' ] || chmod +x '$D'/*.sh" || true
rx sh -c "[ -f '$D/e2e.py' ]" || die "fail2ban-test/ missing in the deployed plugin ($D). Is NPP_EDGE_=1?"
ok "$D present"

step "5/7 Tooling inside $C"
if ! rx sh -c 'command -v python3 >/dev/null'; then
    warn "python3 missing - installing (lost on container recreate, add it to wordpress/Dockerfile to keep)"
    rx sh -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends python3 >/dev/null'
fi
MISSING="$(rx sh -c 'for t in python3 openssl curl wp pkill runuser update-ca-certificates getent; do command -v $t >/dev/null || printf "%s " $t; done')"
[ -z "$MISSING" ] || die "missing tools in $C: $MISSING"
ok "python3 openssl curl wp pkill runuser update-ca-certificates getent"

step "6/7 Wiring the lab (CA, trust store, f2b-lab mu-plugin)"
rx env LAB_IN_DOCKER=1 "$D/setup-lab.sh" "$WP_PATH"

# The webhook token is generated lazily on first use; e2e.py reads it with
# `wp option get nppp_f2b_token`, which errors if it was never created.
if ! wpc option get nppp_f2b_token >/dev/null 2>&1; then
    wpc eval 'nppp_load_bootstrap(); nppp_f2b_get_token();' >/dev/null
    ok "webhook token created"
else
    ok "webhook token present"
fi

[ "$MODE" = prepare ] && { step "Prepared. Run tests with: ./actionstart.sh --only happy,faults"; exit 0; }

# ---------------------------------------------------------------- 7. run ----
step "7/7 Running e2e (${PASS[*]:-all phases except ratelimit})"
set +e
docker exec -u root -e WP_USER="$WP_USER" -e SITE_URL="$SITE_URL" -e WP_PATH="$WP_PATH" \
    "$C" "$D/run-e2e.sh" "${PASS[@]}"
RC=$?
set -e

echo
if [ "$RC" -eq 0 ]; then
    printf '%sALL CHECKS PASSED%s\n' "$G" "$N"
else
    printf '%sTESTS FAILED (exit %s)%s\n' "$R" "$RC" "$N"
    echo "  fake RIPEstat log : docker exec $C tail -n 50 $D/run/fake_ripestat.log"
    echo "  plugin log        : docker exec -u root $C sh -c 'cat \$(find $WP_PATH -name fastcgi_ops.log | head -1)'"
    echo "  shell in lab dir  : ./actionstart.sh --shell"
fi
echo "  cleanup           : ./actionstart.sh --clean   (or --purge)"
exit "$RC"
