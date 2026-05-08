#!/usr/bin/env bash
set -uo pipefail

ANALYST_USER="${ANALYST_USER:-analyst}"
ANALYST_PASSWORD="${ANALYST_PASSWORD:-analyst123}"
GROUP_IDS=(1 2 3 4)
WEB_PORTS=(
    "${GROUP1_WEB_PORT:-5001}"
    "${GROUP2_WEB_PORT:-5002}"
    "${GROUP3_WEB_PORT:-5003}"
    "${GROUP4_WEB_PORT:-5004}"
)
SERVICES=(
    helpdesk-group1 helpdesk-group2 helpdesk-group3 helpdesk-group4
    benign-traffic-group1 benign-traffic-group2 benign-traffic-group3 benign-traffic-group4
    mitigation-helper
    group1-analyst group2-analyst group3-analyst group4-analyst
)
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

for group_id in "${GROUP_IDS[@]}"; do
    for path in \
        "workshop-logs/group${group_id}/web/access.log" \
        "workshop-logs/group${group_id}/web/app.log" \
        "workshop-logs/group${group_id}/suricata/fast.log" \
        "workshop-logs/group${group_id}/suricata/eve.json"; do
        if [[ -e "$path" ]]; then
            ok "$path exists"
        else
            fail "$path is missing"
        fi
    done
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

for index in "${!GROUP_IDS[@]}"; do
    group_id="${GROUP_IDS[$index]}"
    service="group${group_id}-analyst"
    expected_port="${WEB_PORTS[$index]}"

    if docker compose exec -T -u "$ANALYST_USER" "$service" sudo -n /usr/local/bin/workshop-list-blocked >/dev/null 2>&1; then
        ok "$service can run the controlled mitigation list command with sudo"
    else
        fail "$service cannot run the controlled mitigation list command with sudo"
    fi

    config_line="$(docker compose exec -T "$service" sh -c '. /etc/workshop-mitigation.conf && printf "%s:%s\n" "$GROUP_ID" "$WEB_PORT"' 2>/dev/null || true)"
    if [[ "$config_line" == "${group_id}:${expected_port}" ]]; then
        ok "$service has GROUP_ID=$group_id and WEB_PORT=$expected_port"
    else
        fail "$service mitigation config mismatch: expected ${group_id}:${expected_port}, got ${config_line:-empty}"
    fi
done

if docker compose exec -T -u "$ANALYST_USER" group1-analyst sudo -n id >/dev/null 2>&1; then
    fail "group1-analyst can run arbitrary sudo commands"
else
    ok "group1-analyst cannot run arbitrary sudo commands"
fi

for index in "${!GROUP_IDS[@]}"; do
    group_id="${GROUP_IDS[$index]}"
    web_port="${WEB_PORTS[$index]}"
    web_service="helpdesk-group${group_id}"
    analyst_service="group${group_id}-analyst"

    if curl -fsS "http://127.0.0.1:${web_port}/health" >/dev/null; then
        ok "group $group_id target app is reachable from host on port $web_port"
    else
        fail "group $group_id target app is not reachable from host on port $web_port"
    fi

    if docker compose exec -T "$analyst_service" curl -fsS "http://${web_service}:5000/health" >/dev/null 2>&1; then
        ok "$web_service is reachable from $analyst_service over Compose network"
    else
        fail "$web_service is not reachable from $analyst_service over Compose network"
    fi
done

if command -v sshpass >/dev/null 2>&1; then
    if sshpass -p "$ANALYST_PASSWORD" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PreferredAuthentications=password \
        -o PubkeyAuthentication=no \
        -p "${GROUP1_SSH_PORT:-2201}" \
        "${ANALYST_USER}@127.0.0.1" \
        'whoami; test -r /logs/web/access.log; test -r /logs/web/app.log' >/dev/null 2>&1; then
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
