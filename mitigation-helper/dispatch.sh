#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-/opt/live-defense/scripts}"
WEB_PORT="${WEB_PORT:-5000}"

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

read -r action arg extra || {
    echo "ERROR: missing command" >&2
    exit 2
}

if [[ -n "${extra:-}" ]]; then
    echo "ERROR: too many arguments" >&2
    exit 2
fi

if ! validate_port "$WEB_PORT"; then
    echo "ERROR: invalid WEB_PORT: $WEB_PORT" >&2
    exit 2
fi

case "$action" in
    block)
        if ! validate_ipv4 "${arg:-}"; then
            echo "ERROR: invalid IPv4 address: ${arg:-}" >&2
            exit 2
        fi
        WEB_PORT="$WEB_PORT" "$SCRIPT_DIR/block-ip.sh" "$arg" 2>&1
        ;;
    unblock)
        if ! validate_ipv4 "${arg:-}"; then
            echo "ERROR: invalid IPv4 address: ${arg:-}" >&2
            exit 2
        fi
        WEB_PORT="$WEB_PORT" "$SCRIPT_DIR/unblock-ip.sh" "$arg" 2>&1
        ;;
    list)
        if [[ -n "${arg:-}" ]]; then
            echo "ERROR: list does not accept an IP argument" >&2
            exit 2
        fi
        WEB_PORT="$WEB_PORT" "$SCRIPT_DIR/list-blocked.sh" 2>&1
        ;;
    *)
        echo "ERROR: unknown command: $action" >&2
        exit 2
        ;;
esac
