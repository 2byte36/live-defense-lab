#!/usr/bin/env bash
set -euo pipefail

TARGET_URL="${TARGET_URL:-http://127.0.0.1:${HELPDESK_PORT:-5000}}"
TARGET_URL="${TARGET_URL%/}"
APP_USERNAME="${APP_USERNAME:-alice}"
APP_PASSWORD="${APP_PASSWORD:-password123}"
DEMO_USER_AGENT="${DEMO_USER_AGENT:-InstructorDemo/1.0}"
if [[ -n "${COOKIE_JAR:-}" ]]; then
    DEMO_CREATED_COOKIE_JAR=0
else
    COOKIE_JAR="$(mktemp)"
    DEMO_CREATED_COOKIE_JAR=1
fi

cleanup_demo_cookie() {
    if [[ "$DEMO_CREATED_COOKIE_JAR" == "1" ]]; then
        rm -f "$COOKIE_JAR"
    fi
}

require_curl() {
    if ! command -v curl >/dev/null 2>&1; then
        echo "curl is required for demo attack scripts" >&2
        exit 1
    fi
}

login_to_helpdesk() {
    local status

    status="$(
        curl -sS -o /dev/null -w '%{http_code}' \
            -c "$COOKIE_JAR" \
            -b "$COOKIE_JAR" \
            -A "$DEMO_USER_AGENT" \
            -d "username=${APP_USERNAME}&password=${APP_PASSWORD}" \
            "$TARGET_URL/login"
    )"

    case "$status" in
        200|302)
            echo "login status=$status user=$APP_USERNAME target=$TARGET_URL"
            ;;
        *)
            echo "login failed status=$status target=$TARGET_URL" >&2
            exit 1
            ;;
    esac
}

demo_get() {
    local label="$1"
    local path="$2"
    local status

    status="$(
        curl -sS -o /dev/null -w '%{http_code}' \
            -b "$COOKIE_JAR" \
            -A "$DEMO_USER_AGENT" \
            "$TARGET_URL$path"
    )"
    echo "$label status=$status path=$path"
}

demo_post_form() {
    local label="$1"
    local path="$2"
    local field="$3"
    local status

    status="$(
        curl -sS -o /dev/null -w '%{http_code}' \
            -b "$COOKIE_JAR" \
            -A "$DEMO_USER_AGENT" \
            -X POST \
            --data-urlencode "$field" \
            "$TARGET_URL$path"
    )"
    echo "$label status=$status path=$path"
}
