#!/usr/bin/env bash
# Day 1: Traffic Generator for OBI Trace-Log Correlation
# Sends HTTP traffic to frontend service to produce distributed traces and correlated logs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

TARGET_URL="${1:-http://localhost:8080/checkout}"
REQUEST_COUNT="${2:-10}"
DELAY_SECONDS="${3:-0.5}"

log_info "Sending ${REQUEST_COUNT} requests to: ${TARGET_URL}"

SUCCESS_COUNT=0
FAILURE_COUNT=0

for ((i = 1; i <= REQUEST_COUNT; i++)); do
    printf "[Request %03d/%03d] " "$i" "$REQUEST_COUNT"
    HTTP_CODE=$(curl -s -o /tmp/resp.json -w "%{http_code}" "$TARGET_URL" 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "200" ]]; then
        printf "${GREEN}HTTP 200 OK${RESET} -> %s\n" "$(cat /tmp/resp.json 2>/dev/null)"
        ((SUCCESS_COUNT++))
    else
        printf "${RED}HTTP %s Error${RESET}\n" "$HTTP_CODE"
        ((FAILURE_COUNT++))
    fi
    sleep "$DELAY_SECONDS"
done

echo ""
log_success "Traffic generation complete! Successful: $SUCCESS_COUNT, Failed: $FAILURE_COUNT"
echo "Inspect correlated logs with: ${SCRIPT_DIR}/day2-verify-correlation.sh"
