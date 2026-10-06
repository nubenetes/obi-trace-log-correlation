#!/usr/bin/env bash
# Benchmark Overhead: Measure Latency & Throughput with OBI Trace-Log Correlation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

TARGET_URL="${1:-http://localhost:8080/checkout}"
CONCURRENCY="${2:-5}"
TOTAL_REQUESTS="${3:-100}"

log_info "Benchmarking OBI Trace-Log Correlation overhead against: $TARGET_URL"
log_info "Total Requests: $TOTAL_REQUESTS, Concurrency: $CONCURRENCY"

START_TIME=$(date +%s%N)

# Perform benchmark using curl in parallel or hey/ab if available
if command -v hey >/dev/null 2>&1; then
    hey -n "$TOTAL_REQUESTS" -c "$CONCURRENCY" "$TARGET_URL"
elif command -v ab >/dev/null 2>&1; then
    ab -n "$TOTAL_REQUESTS" -c "$CONCURRENCY" "$TARGET_URL"
else
    log_info "Running benchmark loop via curl..."
    for ((i=1; i<=TOTAL_REQUESTS; i++)); do
        curl -s -o /dev/null -w "%{time_total}\n" "$TARGET_URL" >> /tmp/curl_bench.txt
    done
    AVG_TIME=$(awk '{ sum += $1; n++ } END { if (n > 0) print (sum / n) * 1000; }' /tmp/curl_bench.txt)
    MAX_TIME=$(sort -n /tmp/curl_bench.txt | tail -n 1 | awk '{ print $1 * 1000 }')
    MIN_TIME=$(sort -n /tmp/curl_bench.txt | head -n 1 | awk '{ print $1 * 1000 }')
    rm -f /tmp/curl_bench.txt

    END_TIME=$(date +%s%N)
    DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 ))

    echo "======================================================================"
    log_success "Benchmark Results (curl):"
    echo "  Total Requests : $TOTAL_REQUESTS"
    echo "  Total Duration : ${DURATION_MS} ms"
    echo "  Avg Latency    : ${AVG_TIME} ms"
    echo "  Min Latency    : ${MIN_TIME} ms"
    echo "  Max Latency    : ${MAX_TIME} ms"
    echo "======================================================================"
fi

log_success "Overhead benchmark completed successfully."
