#!/usr/bin/env bash
set -euo pipefail

ANALYST_USER="${ANALYST_USER:-analyst}"
ANALYST_PASSWORD="${ANALYST_PASSWORD:-analyst123}"
SSH_KEY="${SSH_KEY:-}"
SESSIONS_PER_GROUP="${SESSIONS_PER_GROUP:-4}"
SSH_HOST="${SSH_HOST:-127.0.0.1}"
SSH_PORTS=(
    "${GROUP1_SSH_PORT:-2201}"
    "${GROUP2_SSH_PORT:-2202}"
    "${GROUP3_SSH_PORT:-2203}"
    "${GROUP4_SSH_PORT:-2204}"
)
REMOTE_COMMAND="${REMOTE_COMMAND:-hostname; whoami; uptime; sleep 5}"

if [[ -z "$SSH_KEY" ]] && ! command -v sshpass >/dev/null 2>&1; then
    cat >&2 <<'MSG'
sshpass is required for password-based SSH stress tests.

Install examples:
  sudo apt-get update && sudo apt-get install -y sshpass
  sudo yum install -y sshpass

Key-based alternative:
  SSH_KEY=/path/to/test_key ./scripts/ssh-stress-test.sh

Manual alternative:
  Open several terminals and SSH to ports 2201-2204 with password analyst123.
MSG
    exit 1
fi

if [[ -n "$SSH_KEY" && ! -r "$SSH_KEY" ]]; then
    echo "SSH_KEY is not readable: $SSH_KEY" >&2
    exit 1
fi

echo "Starting SSH stress test against ${#SSH_PORTS[@]} analyst containers."
echo "Sessions per group: $SESSIONS_PER_GROUP"
echo "Total sessions: $((${#SSH_PORTS[@]} * SESSIONS_PER_GROUP))"
echo
echo "Observe the VPS in another terminal with:"
echo "  htop"
echo "  free -h"
echo "  docker stats"
echo "  w"
echo

failures=0
pids=()

for port in "${SSH_PORTS[@]}"; do
    for session in $(seq 1 "$SESSIONS_PER_GROUP"); do
        (
            label="port=${port} session=${session}"
            ssh_args=(
                -o StrictHostKeyChecking=no
                -o UserKnownHostsFile=/dev/null
                -p "$port"
            )

            if [[ -n "$SSH_KEY" ]]; then
                ssh_args+=(
                    -i "$SSH_KEY"
                    -o IdentitiesOnly=yes
                    -o PreferredAuthentications=publickey
                    -o PasswordAuthentication=no
                )
                ssh_command=(ssh "${ssh_args[@]}" "${ANALYST_USER}@${SSH_HOST}" "$REMOTE_COMMAND")
            else
                ssh_args+=(
                    -o PreferredAuthentications=password
                    -o PubkeyAuthentication=no
                )
                ssh_command=(sshpass -p "$ANALYST_PASSWORD" ssh "${ssh_args[@]}" "${ANALYST_USER}@${SSH_HOST}" "$REMOTE_COMMAND")
            fi

            if "${ssh_command[@]}" >/dev/null 2>&1; then
                echo "[OK] $label"
            else
                echo "[FAIL] $label"
                exit 1
            fi
        ) &
        pids+=("$!")
    done
done

for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
        failures=$((failures + 1))
    fi
done

if [[ "$failures" -gt 0 ]]; then
    echo "SSH stress test finished with $failures failed session(s)."
    exit 1
fi

echo "SSH stress test finished successfully."
