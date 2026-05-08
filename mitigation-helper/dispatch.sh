#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-/opt/live-defense/scripts}"
ALLOWED_GROUP_PORTS="${ALLOWED_GROUP_PORTS:-1:5001 2:5002 3:5003 4:5004}"

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

is_allowed_group_port() {
    local group_id="$1"
    local web_port="$2"
    local pair

    for pair in $ALLOWED_GROUP_PORTS; do
        if [[ "$pair" == "${group_id}:${web_port}" ]]; then
            return 0
        fi
    done

    return 1
}

read -r action group_id web_port arg extra || {
    echo "ERROR: missing command" >&2
    exit 2
}

if [[ -n "${extra:-}" ]]; then
    echo "ERROR: too many arguments" >&2
    exit 2
fi

if [[ ! "${group_id:-}" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: invalid group ID: ${group_id:-}" >&2
    exit 2
fi

if ! validate_port "${web_port:-}"; then
    echo "ERROR: invalid web port: ${web_port:-}" >&2
    exit 2
fi

if ! is_allowed_group_port "$group_id" "$web_port"; then
    echo "ERROR: group $group_id is not allowed to manage web port $web_port" >&2
    exit 2
fi

case "$action" in
    block)
        if ! validate_ipv4 "${arg:-}"; then
            echo "ERROR: invalid IPv4 address: ${arg:-}" >&2
            exit 2
        fi
        WEB_PORT="$web_port" "$SCRIPT_DIR/block-ip.sh" "$arg" 2>&1
        ;;
    unblock)
        if ! validate_ipv4 "${arg:-}"; then
            echo "ERROR: invalid IPv4 address: ${arg:-}" >&2
            exit 2
        fi
        WEB_PORT="$web_port" "$SCRIPT_DIR/unblock-ip.sh" "$arg" 2>&1
        ;;
    list)
        if [[ -n "${arg:-}" ]]; then
            echo "ERROR: list does not accept an IP argument" >&2
            exit 2
        fi
        WEB_PORT="$web_port" "$SCRIPT_DIR/list-blocked.sh" 2>&1
        ;;
    *)
        echo "ERROR: unknown command: $action" >&2
        exit 2
        ;;
esac
