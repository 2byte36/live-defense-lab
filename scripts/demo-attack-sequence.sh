#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ATTACK_DELAY="${ATTACK_DELAY:-3}"

"$SCRIPT_DIR/run-sqli-demo.sh"
sleep "$ATTACK_DELAY"
"$SCRIPT_DIR/run-cmdi-demo.sh"
sleep "$ATTACK_DELAY"
"$SCRIPT_DIR/run-traversal-demo.sh"

echo "Full demo attack sequence complete."
