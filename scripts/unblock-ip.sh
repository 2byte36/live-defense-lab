#!/usr/bin/env bash
set -euo pipefail

DOCKER_USER_CHAIN="${DOCKER_USER_CHAIN:-DOCKER-USER}"
RULE_COMMENT="${RULE_COMMENT:-live-defense-workshop-web}"
WEB_PORT="${WEB_PORT:-5000}"
LEGACY_CHAIN="${LEGACY_CHAIN:-LIVE_DEFENSE_BLOCK}"
LEGACY_RULE_COMMENT="${LEGACY_RULE_COMMENT:-live-defense-workshop}"

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

removed=0
if iptables -L "$DOCKER_USER_CHAIN" -n >/dev/null 2>&1; then
    while iptables -D "$DOCKER_USER_CHAIN" -s "$ip" -p tcp --dport "$WEB_PORT" -m comment --comment "$RULE_COMMENT" -j DROP 2>/dev/null; do
        removed=$((removed + 1))
    done
fi

# Clean up legacy rules created by older versions of this workshop helper.
if iptables -L "$LEGACY_CHAIN" -n >/dev/null 2>&1; then
    while iptables -D "$LEGACY_CHAIN" -s "$ip" -m comment --comment "$LEGACY_RULE_COMMENT" -j DROP 2>/dev/null; do
        removed=$((removed + 1))
    done
fi

if [[ "$removed" -eq 0 ]]; then
    echo "No matching web block rule found for $ip on port $WEB_PORT"
else
    echo "Removed $removed block rule(s) for $ip"
fi
