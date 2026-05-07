#!/usr/bin/env bash
set -euo pipefail

DOCKER_USER_CHAIN="${DOCKER_USER_CHAIN:-DOCKER-USER}"
RULE_COMMENT="${RULE_COMMENT:-live-defense-workshop-web}"
WEB_PORT="${WEB_PORT:-5000}"

usage() {
    echo "Usage: sudo $0 <ipv4-address>" >&2
}

validate_ipv4() {
    local ip="${1:-}"
    local o1 o2 o3 o4 octet

    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS=. read -r o1 o2 o3 o4 <<< "$ip"
    for octet in "$o1" "$o2" "$o3" "$o4"; do
        [[ "$octet" =~ ^[0-9]+$ ]] || return 1
        ((10#$octet >= 0 && 10#$octet <= 255)) || return 1
    done
}

validate_port() {
    local port="${1:-}"

    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    ((10#$port >= 1 && 10#$port <= 65535)) || return 1
}

if [[ $# -ne 1 ]]; then
    usage
    exit 2
fi

ip="$1"
if ! validate_ipv4 "$ip"; then
    echo "Invalid IPv4 address: $ip" >&2
    exit 2
fi

if ! validate_port "$WEB_PORT"; then
    echo "Invalid WEB_PORT: $WEB_PORT" >&2
    exit 2
fi

if [[ "${EUID}" -ne 0 ]]; then
    echo "This script must be run as root, for example: sudo $0 $ip" >&2
    exit 1
fi

if ! iptables -L "$DOCKER_USER_CHAIN" -n >/dev/null 2>&1; then
    echo "$DOCKER_USER_CHAIN chain was not found. Start Docker before applying workshop web blocks." >&2
    exit 1
fi

if iptables -C "$DOCKER_USER_CHAIN" -s "$ip" -p tcp --dport "$WEB_PORT" -m comment --comment "$RULE_COMMENT" -j DROP 2>/dev/null; then
    echo "Already blocked from web port $WEB_PORT: $ip"
    exit 0
fi

iptables -I "$DOCKER_USER_CHAIN" 1 -s "$ip" -p tcp --dport "$WEB_PORT" -m comment --comment "$RULE_COMMENT" -j DROP
echo "Blocked $ip from Docker-published web port $WEB_PORT"
