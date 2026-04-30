#!/usr/bin/env bash
# Bring up the virtual FPP + mock RF API and wait until both are healthy.
# Idempotent: safe to run repeatedly; prior containers are removed first.

set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"

# Reset state directory used by the mock RF API for route config + recordings.
rm -rf "$HERE/.state"
mkdir -p "$HERE/.state"
echo '{}' > "$HERE/.state/config.json"
echo '[]' > "$HERE/.state/recordings.json"

# Tear down any stale containers from a previous run, then bring up fresh.
docker compose down -v --remove-orphans >/dev/null 2>&1 || true
docker compose up -d

echo "Waiting for FPP API to respond..."
for i in $(seq 1 60); do
    if curl -sf -o /dev/null http://127.0.0.1:18080/api/system/status; then
        echo "FPP ready after ${i}s"
        break
    fi
    if [ "$i" = "60" ]; then
        echo "FPP failed to come up in 60s; container logs:" >&2
        docker compose logs fpp >&2
        exit 1
    fi
    sleep 1
done

echo "Waiting for mock RF API..."
for i in $(seq 1 30); do
    if curl -sf -o /dev/null http://127.0.0.1:18081/q/health; then
        echo "Mock RF API ready after ${i}s"
        break
    fi
    if [ "$i" = "30" ]; then
        echo "Mock RF API failed to come up in 30s; container logs:" >&2
        docker compose logs mock-rf-api >&2
        exit 1
    fi
    sleep 1
done

echo ""
echo "Environment ready:"
echo "  FPP web UI / API:    http://127.0.0.1:18080"
echo "  Mock RF API:         http://127.0.0.1:18081"
echo "  State directory:     $HERE/.state/"
