#!/usr/bin/env bash
set -euo pipefail

MITIGATION_SOCKET="${MITIGATION_SOCKET:-/run/workshop-mitigation/mitigation.sock}"
ACTION="$(basename "$0")"

case "$ACTION" in
    workshop-block-ip)
        COMMAND="block"
        EXPECT_IP=1
        ;;
    workshop-unblock-ip)
        COMMAND="unblock"
        EXPECT_IP=1
        ;;
    workshop-list-blocked)
        COMMAND="list"
        EXPECT_IP=0
        ;;
    *)
        echo "Unsupported workshop mitigation command: $ACTION" >&2
        exit 2
        ;;
esac

usage() {
    case "$EXPECT_IP" in
        1) echo "Usage: sudo /usr/local/bin/$ACTION <ipv4-address>" >&2 ;;
        0) echo "Usage: sudo /usr/local/bin/$ACTION" >&2 ;;
    esac
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

if [[ "$EUID" -ne 0 ]]; then
    usage
    echo "Run this command with sudo." >&2
    exit 1
fi

if [[ "$EXPECT_IP" -eq 1 ]]; then
    if [[ "$#" -ne 1 ]]; then
        usage
        exit 2
    fi

    ip="$1"
    if ! validate_ipv4 "$ip"; then
        echo "Invalid IPv4 address: $ip" >&2
        exit 2
    fi

    request="$COMMAND $ip"
else
    if [[ "$#" -ne 0 ]]; then
        usage
        exit 2
    fi

    request="$COMMAND"
fi

if [[ ! -S "$MITIGATION_SOCKET" ]]; then
    echo "Workshop mitigation helper is not available." >&2
    exit 1
fi

printf '%s\n' "$request" | socat -T 10 - "UNIX-CONNECT:${MITIGATION_SOCKET}"
