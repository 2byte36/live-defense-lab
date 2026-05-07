#!/usr/bin/env bash
set -euo pipefail

MITIGATION_SOCKET="${MITIGATION_SOCKET:-/run/workshop-mitigation/mitigation.sock}"
socket_dir="$(dirname "$MITIGATION_SOCKET")"

install -d -m 0755 -o root -g root "$socket_dir"
rm -f "$MITIGATION_SOCKET"

echo "workshop mitigation helper listening on $MITIGATION_SOCKET for web port ${WEB_PORT:-5000}"

exec socat \
    "UNIX-LISTEN:${MITIGATION_SOCKET},fork,mode=0600,user=root,group=root" \
    EXEC:/usr/local/bin/workshop-mitigation-dispatch
