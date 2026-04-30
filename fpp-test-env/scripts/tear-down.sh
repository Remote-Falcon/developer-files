#!/usr/bin/env bash
# Stop the virtual FPP + mock RF API and clean up state.

set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"

docker compose down -v --remove-orphans
rm -rf "$HERE/.state"
echo "Torn down."
