#!/usr/bin/env bash
set -euo pipefail

DOCKER_USER_CHAIN="${DOCKER_USER_CHAIN:-DOCKER-USER}"
RULE_COMMENT="${RULE_COMMENT:-live-defense-workshop-web}"

if [[ "${EUID}" -ne 0 ]]; then
    echo "This script must be run as root, for example: sudo $0" >&2
    exit 1
fi

echo "Current workshop web source IP blocks:"
if ! iptables -L "$DOCKER_USER_CHAIN" -n >/dev/null 2>&1; then
    echo "$DOCKER_USER_CHAIN chain was not found."
    exit 0
fi

rules="$(iptables -S "$DOCKER_USER_CHAIN" | grep -- "--comment $RULE_COMMENT" || true)"
if [[ -z "$rules" ]]; then
    echo "No matching DROP rules found."
else
    printf '%s\n' "$rules"
fi
