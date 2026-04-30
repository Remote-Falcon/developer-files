#!/usr/bin/env bash
# Run a plugin-specific smoke script with the harness environment populated.
# The harness owns FPP + mock RF; the smoke script owns plugin-specific
# assertions about how the plugin behaves once installed.
#
# Usage: smoke-test.sh PATH_TO_SMOKE_SCRIPT
#
# The smoke script receives these env vars:
#   FPP_BASE_URL          http://127.0.0.1:18080
#   FPP_CONTAINER         rf-test-fpp
#   MOCK_RF_BASE_URL      http://127.0.0.1:18081  (host-side)
#   MOCK_RF_INTERNAL_URL  http://mock-rf-api      (in-container, for the listener)
#   MOCK_RF_STATE_DIR     absolute path to .state on the host

set -euo pipefail

if [ "${1-}" = "" ]; then
    echo "usage: $0 PATH_TO_SMOKE_SCRIPT" >&2
    exit 1
fi

SMOKE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -x "$SMOKE" ]; then
    echo "$SMOKE is not executable" >&2
    exit 1
fi

export FPP_BASE_URL="http://127.0.0.1:18080"
export FPP_CONTAINER="rf-test-fpp"
export MOCK_RF_BASE_URL="http://127.0.0.1:18081"
export MOCK_RF_INTERNAL_URL="http://mock-rf-api"
export MOCK_RF_STATE_DIR="$HARNESS_DIR/.state"

echo "Running smoke: $SMOKE"
echo "  FPP:           $FPP_BASE_URL"
echo "  Mock RF (host):$MOCK_RF_BASE_URL"
echo "  Mock RF (FPP): $MOCK_RF_INTERNAL_URL"
echo ""

"$SMOKE"
