#!/usr/bin/env bash
set -euo pipefail

DOCKER_USER_CHAIN="${DOCKER_USER_CHAIN:-DOCKER-USER}"
RULE_COMMENT="${RULE_COMMENT:-live-defense-workshop-web}"
LEGACY_CHAIN="${LEGACY_CHAIN:-LIVE_DEFENSE_BLOCK}"
LEGACY_RULE_COMMENT="${LEGACY_RULE_COMMENT:-live-defense-workshop}"
RESET_LOG_MODE="${RESET_LOG_MODE:-truncate}"
RUN_CHECKS="${RUN_CHECKS:-1}"

run_iptables() {
    if [[ "${EUID}" -eq 0 ]]; then
        iptables "$@"
        return
    fi

    if command -v sudo >/dev/null 2>&1; then
        if [[ "${ALLOW_SUDO_PROMPT:-0}" == "1" ]]; then
            sudo iptables "$@"
            return
        fi

        sudo -n iptables "$@"
        return
    fi

    echo "sudo is not available; cannot manage iptables rules" >&2
    return 1
}

flush_workshop_firewall_rules() {
    echo "Flushing workshop iptables rules..."

    if ! run_iptables -S >/dev/null 2>&1; then
        echo "Skipping iptables flush; run this script with sudo to clear workshop firewall rules."
        return 0
    fi

    if run_iptables -L "$DOCKER_USER_CHAIN" -n >/dev/null 2>&1; then
        while IFS= read -r rule; do
            [[ -n "$rule" ]] || continue
            read -r -a parts <<< "$rule"
            parts[0]="-D"
            run_iptables "${parts[@]}"
        done < <(run_iptables -S "$DOCKER_USER_CHAIN" 2>/dev/null | grep -- "--comment $RULE_COMMENT" || true)
    fi

    # Remove dangerous legacy workshop rules from older script versions.
    if run_iptables -L "$LEGACY_CHAIN" -n >/dev/null 2>&1; then
        while run_iptables -C INPUT -j "$LEGACY_CHAIN" 2>/dev/null; do
            run_iptables -D INPUT -j "$LEGACY_CHAIN"
        done
        run_iptables -F "$LEGACY_CHAIN"
        run_iptables -X "$LEGACY_CHAIN"
    fi

    while IFS= read -r rule; do
        [[ -n "$rule" ]] || continue
        read -r -a parts <<< "$rule"
        parts[0]="-D"
        run_iptables "${parts[@]}"
    done < <(run_iptables -S INPUT 2>/dev/null | grep -- "--comment $LEGACY_RULE_COMMENT" || true)
}

reset_logs() {
    echo "Resetting workshop logs with mode: $RESET_LOG_MODE"
    mkdir -p workshop-logs/web workshop-logs/suricata

    for log_path in \
        workshop-logs/web/access.log \
        workshop-logs/web/app.log \
        workshop-logs/suricata/fast.log \
        workshop-logs/suricata/eve.json; do
        touch "$log_path"
        if [[ "$RESET_LOG_MODE" == "rotate" && -s "$log_path" ]]; then
            mv "$log_path" "${log_path}.$(date -u +%Y%m%dT%H%M%SZ)"
            touch "$log_path"
        else
            : > "$log_path"
        fi
    done
}

restart_stack() {
    echo "Recreating containers and SQLite database volume..."
    docker compose down -v --remove-orphans
    reset_logs
    docker compose up --build -d
}

flush_workshop_firewall_rules
restart_stack

if [[ "$RUN_CHECKS" == "1" ]]; then
    ./scripts/check-lab.sh
fi

echo "Lab reset complete."
