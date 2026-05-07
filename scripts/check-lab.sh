#!/usr/bin/env bash
set -uo pipefail

TARGET_PORT="${TARGET_PORT:-${HELPDESK_PORT:-5000}}"
ANALYST_USER="${ANALYST_USER:-analyst}"
ANALYST_PASSWORD="${ANALYST_PASSWORD:-analyst123}"
SERVICES=(helpdesk benign-traffic mitigation-helper group1-analyst group2-analyst group3-analyst group4-analyst)
ANALYST_SERVICES=(group1-analyst group2-analyst group3-analyst group4-analyst)
SSH_PORTS=(
    "${GROUP1_SSH_PORT:-2201}"
    "${GROUP2_SSH_PORT:-2202}"
    "${GROUP3_SSH_PORT:-2203}"
    "${GROUP4_SSH_PORT:-2204}"
)

failures=0
warnings=0

ok() {
    echo "[OK] $*"
}

warn() {
    warnings=$((warnings + 1))
    echo "[WARN] $*"
}

fail() {
    failures=$((failures + 1))
    echo "[FAIL] $*"
}

is_port_listening() {
    local port="$1"

    if command -v ss >/dev/null 2>&1; then
        ss -ltn | awk '{print $4}' | grep -Eq "[:.]${port}$"
        return
    fi

    timeout 2 bash -c ":</dev/tcp/127.0.0.1/${port}" >/dev/null 2>&1
}

echo "Checking Docker Compose configuration..."
if docker compose config >/dev/null; then
    ok "docker compose config is valid"
else
    fail "docker compose config failed"
fi

running_services="$(docker compose ps --status running --services 2>/dev/null || true)"
for service in "${SERVICES[@]}"; do
    if grep -qx "$service" <<< "$running_services"; then
        ok "$service is running"
    else
        fail "$service is not running"
    fi
done

for port in "${SSH_PORTS[@]}"; do
    if is_port_listening "$port"; then
        ok "SSH port $port is listening"
    else
        fail "SSH port $port is not listening"
    fi
done

for path in \
    workshop-logs/web/access.log \
    workshop-logs/web/app.log \
    workshop-logs/suricata/fast.log \
    workshop-logs/suricata/eve.json; do
    if [[ -e "$path" ]]; then
        ok "$path exists"
    else
        fail "$path is missing"
    fi
done

for service in "${ANALYST_SERVICES[@]}"; do
    container_id="$(docker compose ps -q "$service" 2>/dev/null || true)"
    if [[ -z "$container_id" ]]; then
        fail "Could not find container for $service"
        continue
    fi

    mount_rw="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/logs"}}{{.RW}}{{end}}{{end}}' "$container_id" 2>/dev/null || true)"
    case "$mount_rw" in
        false)
            ok "$service has /logs mounted read-only"
            ;;
        true)
            fail "$service has /logs mounted read-write"
            ;;
        *)
            fail "$service does not appear to have /logs mounted"
            ;;
    esac
done

if docker compose exec -T -u "$ANALYST_USER" group1-analyst sudo -n /usr/local/bin/workshop-list-blocked >/dev/null 2>&1; then
    ok "group1-analyst can run the controlled mitigation list command with sudo"
else
    fail "group1-analyst cannot run the controlled mitigation list command with sudo"
fi

if docker compose exec -T -u "$ANALYST_USER" group1-analyst sudo -n id >/dev/null 2>&1; then
    fail "group1-analyst can run arbitrary sudo commands"
else
    ok "group1-analyst cannot run arbitrary sudo commands"
fi

if curl -fsS "http://127.0.0.1:${TARGET_PORT}/health" >/dev/null; then
    ok "target app is reachable from host on port $TARGET_PORT"
else
    fail "target app is not reachable from host on port $TARGET_PORT"
fi

if docker compose exec -T group1-analyst curl -fsS http://helpdesk:5000/health >/dev/null 2>&1; then
    ok "target app is reachable from group1-analyst over Compose network"
else
    fail "target app is not reachable from group1-analyst over Compose network"
fi

if command -v sshpass >/dev/null 2>&1; then
    if sshpass -p "$ANALYST_PASSWORD" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PreferredAuthentications=password \
        -o PubkeyAuthentication=no \
        -p "${GROUP1_SSH_PORT:-2201}" \
        "${ANALYST_USER}@127.0.0.1" \
        'whoami; test -r /logs/web/access.log' >/dev/null 2>&1; then
        ok "SSH login check succeeded for group1-analyst"
    else
        fail "SSH login check failed for group1-analyst"
    fi
else
    warn "sshpass is not installed; skipped SSH password login check"
fi

echo
echo "Checks complete: $failures failure(s), $warnings warning(s)"
if [[ "$failures" -gt 0 ]]; then
    exit 1
fi
