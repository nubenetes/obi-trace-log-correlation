#!/usr/bin/env bash
# Common utility functions for OBI Trace-Log Correlation automation scripts
set -euo pipefail

# ANSI Color Codes
BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
RESET="\033[0m"

log_info() {
    printf "${BLUE}${BOLD}[INFO]${RESET} %s\n" "$*"
}

log_success() {
    printf "${GREEN}${BOLD}[SUCCESS]${RESET} %s\n" "$*"
}

log_warn() {
    printf "${YELLOW}${BOLD}[WARN]${RESET} %s\n" "$*"
}

log_error() {
    printf "${RED}${BOLD}[ERROR]${RESET} %s\n" "$*" >&2
}

log_fatal() {
    printf "${RED}${BOLD}[FATAL]${RESET} %s\n" "$*" >&2
    exit 1
}

check_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_fatal "Required command '$cmd' is not installed or not in PATH."
    fi
}
