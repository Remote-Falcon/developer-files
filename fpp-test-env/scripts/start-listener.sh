#!/usr/bin/env bash
# Convenience wrapper: run the plugin's postStart.sh inside the FPP container.
# Useful for interactive sessions where you don't want to remember the
# full `docker exec` invocation.
#
# Usage: start-listener.sh [PLUGIN_NAME]
#   PLUGIN_NAME defaults to "remote-falcon".

set -euo pipefail

PLUGIN_NAME="${1:-remote-falcon}"
CONTAINER="rf-test-fpp"

if ! docker ps --filter "name=^${CONTAINER}$" --format '{{.Names}}' | grep -q "$CONTAINER"; then
    echo "Container $CONTAINER is not running. Run scripts/spin-up.sh first." >&2
    exit 1
fi

POSTSTART="/home/fpp/media/plugins/${PLUGIN_NAME}/scripts/postStart.sh"
if ! docker exec "$CONTAINER" test -x "$POSTSTART"; then
    echo "$POSTSTART not found or not executable inside the container." >&2
    echo "(Did you run scripts/install-plugin.sh first?)" >&2
    exit 1
fi

docker exec "$CONTAINER" "$POSTSTART"
sleep 1

PIDFILE="/home/fpp/media/plugins/${PLUGIN_NAME}/remote_falcon_listener.pid"
if docker exec "$CONTAINER" test -f "$PIDFILE"; then
    PID=$(docker exec "$CONTAINER" cat "$PIDFILE")
    echo "Listener started (pid $PID). Tail log with:"
    echo "  docker exec rf-test-fpp tail -f /home/fpp/media/logs/${PLUGIN_NAME}-listener.log"
else
    echo "postStart.sh ran but no PID file appeared. Check container logs." >&2
    exit 1
fi
