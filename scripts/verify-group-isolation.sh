#!/usr/bin/env bash
set -euo pipefail

CHECK_HOST_NODE="${CHECK_HOST_NODE:-fi1.node.check-host.net}"
VPS_IP="${VPS_IP:-}"
ATTACKER_IP="${ATTACKER_IP:-}"
SSH_PORTS="${SSH_PORTS:-2201}"
GROUP1_ANALYST_SERVICE="${GROUP1_ANALYST_SERVICE:-group1-analyst}"
GROUP1_WEB_PORT="${GROUP1_WEB_PORT:-5001}"
WEB_PORTS=(
    "${GROUP1_WEB_PORT}"
    "${GROUP2_WEB_PORT:-5002}"
    "${GROUP3_WEB_PORT:-5003}"
    "${GROUP4_WEB_PORT:-5004}"
)

die() {
    echo "ERROR: $*" >&2
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

discover_vps_ip() {
    if [[ -n "$VPS_IP" ]]; then
        return 0
    fi

    VPS_IP="$(curl -4 -fsS https://ifconfig.me 2>/dev/null || true)"
    [[ -n "$VPS_IP" ]] || die "set VPS_IP=<public-vps-ip>"
}

discover_attacker_ip() {
    if [[ -n "$ATTACKER_IP" ]]; then
        return 0
    fi

    ATTACKER_IP="$(getent ahostsv4 "$CHECK_HOST_NODE" | awk 'NR == 1 {print $1}')"
    [[ -n "$ATTACKER_IP" ]] || die "set ATTACKER_IP=<external-check-source-ip>"
}

request_http_check() {
    local port="$1"
    local response request_id

    response="$(
        curl -fsS -H 'Accept: application/json' --get \
            --data-urlencode "host=http://${VPS_IP}:${port}/health" \
            --data-urlencode "node=${CHECK_HOST_NODE}" \
            https://check-host.net/check-http
    )"
    request_id="$(printf '%s' "$response" | sed -n 's/.*"request_id":"\([^"]*\)".*/\1/p')"
    [[ -n "$request_id" ]] || die "could not start HTTP check for port $port: $response"
    printf '%s\n' "$request_id"
}

request_tcp_check() {
    local port="$1"
    local response request_id

    response="$(
        curl -fsS -H 'Accept: application/json' --get \
            --data-urlencode "host=${VPS_IP}:${port}" \
            --data-urlencode "node=${CHECK_HOST_NODE}" \
            https://check-host.net/check-tcp
    )"
    request_id="$(printf '%s' "$response" | sed -n 's/.*"request_id":"\([^"]*\)".*/\1/p')"
    [[ -n "$request_id" ]] || die "could not start TCP check for port $port: $response"
    printf '%s\n' "$request_id"
}

poll_result() {
    local request_id="$1"
    local result=""

    for _ in $(seq 1 12); do
        result="$(curl -fsS -H 'Accept: application/json' "https://check-host.net/check-result/${request_id}")"
        if [[ "$result" != *":null"* ]]; then
            printf '%s\n' "$result"
            return 0
        fi
        sleep 2
    done

    printf '%s\n' "$result"
}

expect_http_ok() {
    local port="$1"
    local request_id result

    request_id="$(request_http_check "$port")"
    result="$(poll_result "$request_id")"
    if [[ "$result" == *'"OK",200'* ]]; then
        echo "[OK] external HTTP to ${port} succeeded: $result"
        return 0
    fi

    die "expected external HTTP to ${port} to succeed, got: $result"
}

expect_http_blocked() {
    local port="$1"
    local request_id result

    request_id="$(request_http_check "$port")"
    result="$(poll_result "$request_id")"
    if [[ "$result" != *'"OK",200'* ]] && [[ "$result" =~ (timed\ out|Connection\ refused|Failed|No\ route|reset) ]]; then
        echo "[OK] external HTTP to ${port} was blocked: $result"
        return 0
    fi

    die "expected external HTTP to ${port} to fail, got: $result"
}

expect_tcp_ok() {
    local port="$1"
    local request_id result

    request_id="$(request_tcp_check "$port")"
    result="$(poll_result "$request_id")"
    if [[ "$result" == *'"address"'* ]]; then
        echo "[OK] external TCP to ${port} succeeded: $result"
        return 0
    fi

    die "expected external TCP to ${port} to succeed, got: $result"
}

cleanup() {
    if [[ "${BLOCKED:-0}" -eq 1 ]]; then
        docker compose exec -T -u analyst "$GROUP1_ANALYST_SERVICE" \
            sudo -n /usr/local/bin/workshop-unblock-ip "$ATTACKER_IP" >/dev/null 2>&1 || true
    fi
}

trap cleanup EXIT

need_cmd curl
need_cmd docker
need_cmd getent
discover_vps_ip
discover_attacker_ip

echo "Using VPS_IP=${VPS_IP}"
echo "Using external attacker node ${CHECK_HOST_NODE} (${ATTACKER_IP})"

for port in "${WEB_PORTS[@]}"; do
    expect_http_ok "$port"
done

docker compose exec -T -u analyst "$GROUP1_ANALYST_SERVICE" \
    sudo -n /usr/local/bin/workshop-block-ip "$ATTACKER_IP"
BLOCKED=1

docker compose exec -T mitigation-helper iptables -L DOCKER-USER -n -v --line-numbers

expect_http_blocked "$GROUP1_WEB_PORT"

for port in "${WEB_PORTS[@]:1}"; do
    expect_http_ok "$port"
done

for port in $SSH_PORTS; do
    expect_tcp_ok "$port"
done

docker compose exec -T -u analyst "$GROUP1_ANALYST_SERVICE" \
    sudo -n /usr/local/bin/workshop-unblock-ip "$ATTACKER_IP"
BLOCKED=0

expect_http_ok "$GROUP1_WEB_PORT"

echo "[OK] Group 1 block affected only ${GROUP1_WEB_PORT}; other groups and SSH remained reachable."
