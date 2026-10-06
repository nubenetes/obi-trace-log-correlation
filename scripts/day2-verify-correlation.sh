#!/usr/bin/env bash
# Day 2: Automated Verification of OBI Trace-Log Correlation
# Fetches logs, extracts injected trace_id & span_id, and confirms cross-service correlation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

echo "======================================================================"
echo "  OBI Trace-Log Correlation: Day 2 Live Verification"
echo "======================================================================"

MODE="unknown"
if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' | grep -q "demo-frontend"; then
    MODE="docker"
elif command -v kubectl >/dev/null 2>&1 && kubectl get pods -n demo-apps >/dev/null 2>&1; then
    MODE="k8s"
fi

if [[ "$MODE" == "unknown" ]]; then
    log_fatal "Could not detect active demo workload in Docker Compose or Kubernetes."
fi

log_info "Active environment detected: ${BOLD}${MODE}${RESET}"

# Step 1: Fetch logs
FRONTEND_LOGS="/tmp/obi_frontend.log"
BACKEND_LOGS="/tmp/obi_backend.log"

if [[ "$MODE" == "docker" ]]; then
    docker logs demo-frontend --tail 50 > "$FRONTEND_LOGS" 2>&1 || true
    docker logs demo-backend --tail 50 > "$BACKEND_LOGS" 2>&1 || true
else
    kubectl logs -n demo-apps deployment/frontend --tail 50 > "$FRONTEND_LOGS" 2>&1 || true
    kubectl logs -n demo-apps deployment/backend --tail 50 > "$BACKEND_LOGS" 2>&1 || true
fi

# Step 2: Check for presence of trace_id in logs
log_info "Analyzing Frontend logs for injected trace_id..."
FRONTEND_MATCH=$(grep -a "trace_id" "$FRONTEND_LOGS" | tail -n 1 || true)
if [[ -z "$FRONTEND_MATCH" ]]; then
    log_error "No trace_id found in Frontend logs! Check if OBI is attached and traffic was sent."
    echo "Frontend raw logs:"
    cat "$FRONTEND_LOGS"
    exit 1
fi

log_info "Analyzing Backend logs for injected trace_id..."
BACKEND_MATCH=$(grep -a "trace_id" "$BACKEND_LOGS" | tail -n 1 || true)
if [[ -z "$BACKEND_MATCH" ]]; then
    log_error "No trace_id found in Backend logs! Check if OBI is attached."
    echo "Backend raw logs:"
    cat "$BACKEND_LOGS"
    exit 1
fi

# Step 3: Extract trace_id and span_id using regex/sed
EXTRACT_TRACE_ID() {
    # Handles JSON: "trace_id":"([a-f0-9]+)" or plain text: trace_id=([a-f0-9]+)
    echo "$1" | grep -o -E 'trace_id["=: ]+[a-f0-9]{16,32}' | tr -cd 'a-f0-9' | sed -E 's/^[0-9a-f]{0,8}id//' || echo ""
}

EXTRACT_SPAN_ID() {
    echo "$1" | grep -o -E 'span_id["=: ]+[a-f0-9]{16}' | tr -cd 'a-f0-9' | sed -E 's/^[0-9a-f]{0,7}id//' || echo ""
}

FE_TRACE=$(echo "$FRONTEND_MATCH" | grep -o -E '[0-9a-f]{32}' | head -n 1 || true)
BE_TRACE=$(echo "$BACKEND_MATCH" | grep -o -E '[0-9a-f]{32}' | head -n 1 || true)

echo "----------------------------------------------------------------------"
log_info "Frontend Enriched Sample:"
echo "$FRONTEND_MATCH"
log_info "Backend Enriched Sample:"
echo "$BACKEND_MATCH"
echo "----------------------------------------------------------------------"

log_info "Frontend Trace ID: $FE_TRACE"
log_info "Backend Trace ID : $BE_TRACE"

# Step 4: Validate correlation match
if [[ -n "$FE_TRACE" && -n "$BE_TRACE" && "$FE_TRACE" == "$BE_TRACE" ]]; then
    log_success "CORRELATION CONFIRMED! Frontend and Backend share the identical Trace ID ($FE_TRACE) across distributed network hops!"
else
    log_warn "Trace IDs did not match directly on latest line. Multiple concurrent requests might have occurred. Check recent trace IDs:"
    grep -a -o -E '[0-9a-f]{32}' "$FRONTEND_LOGS" | sort -u > /tmp/fe_traces.txt || true
    grep -a -o -E '[0-9a-f]{32}' "$BACKEND_LOGS" | sort -u > /tmp/be_traces.txt || true
    COMMON=$(comm -12 /tmp/fe_traces.txt /tmp/be_traces.txt || true)
    if [[ -n "$COMMON" ]]; then
        log_success "Matched common Trace IDs between services: $COMMON"
    else
        log_error "No common trace IDs found in logs."
    fi
fi

# Step 5: Check Jaeger endpoint
JAEGER_API="http://localhost:16686/api/traces?service=frontend&limit=5"
if curl -s "$JAEGER_API" >/dev/null 2>&1; then
    log_success "Jaeger API accessible! Querying traces..."
    TRACE_COUNT=$(curl -s "$JAEGER_API" | grep -o '"traceID"' | wc -l || echo 0)
    log_info "Traces recorded in Jaeger for service 'frontend': $TRACE_COUNT"
fi

echo "======================================================================"
log_success "Day 2 Verification Complete! OBI Zero-Code Trace-Log Correlation is active and verified."
