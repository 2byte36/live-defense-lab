#!/usr/bin/env bash
set -euo pipefail

INTERVAL="${INTERVAL:-5}"
SSH_PORT_PATTERN="${SSH_PORT_PATTERN:-:(22|2201|2202|2203|2204)$}"

while true; do
    if [[ "${NO_CLEAR:-0}" != "1" ]]; then
        clear || true
    fi

    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo

    echo "Uptime:"
    uptime
    echo

    echo "Memory:"
    free -h
    echo

    echo "Disk:"
    df -h .
    echo

    echo "Docker containers:"
    if running_ids="$(docker ps -q 2>/dev/null)" && total_ids="$(docker ps -aq 2>/dev/null)"; then
        running_count="$(printf '%s\n' "$running_ids" | sed '/^$/d' | wc -l | awk '{print $1}')"
        total_count="$(printf '%s\n' "$total_ids" | sed '/^$/d' | wc -l | awk '{print $1}')"
    else
        running_count="unavailable"
        total_count="unavailable"
    fi
    echo "running=$running_count total=$total_count"
    echo

    echo "Docker stats:"
    docker stats --no-stream || true
    echo

    echo "Active SSH sessions from who:"
    who || true
    echo

    echo "Established SSH connections on host/workshop ports:"
    if command -v ss >/dev/null 2>&1; then
        ss -tn state established | awk -v pattern="$SSH_PORT_PATTERN" '$4 ~ pattern {print}'
    else
        echo "ss command not available"
    fi
    echo

    sleep "$INTERVAL"
done
