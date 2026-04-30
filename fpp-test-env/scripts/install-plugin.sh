#!/usr/bin/env bash
# Copy a plugin source directory into the running FPP container as if FPP
# had cloned it from GitHub, then run the plugin's fpp_install.sh.
#
# Usage: install-plugin.sh PLUGIN_SOURCE_DIR [PLUGIN_NAME]
#   PLUGIN_SOURCE_DIR   Path to the plugin's repo on the host
#   PLUGIN_NAME         Optional; defaults to the basename of PLUGIN_SOURCE_DIR

set -euo pipefail

if [ "${1-}" = "" ]; then
    echo "usage: $0 PLUGIN_SOURCE_DIR [PLUGIN_NAME]" >&2
    exit 1
fi

PLUGIN_SOURCE="$(cd "$1" && pwd)"
PLUGIN_NAME="${2:-$(basename "$PLUGIN_SOURCE")}"
CONTAINER="rf-test-fpp"
DEST="/home/fpp/media/plugins/${PLUGIN_NAME}"

if ! docker ps --filter "name=^${CONTAINER}$" --format '{{.Names}}' | grep -q "$CONTAINER"; then
    echo "Container $CONTAINER is not running. Run scripts/spin-up.sh first." >&2
    exit 1
fi

echo "Installing $PLUGIN_NAME from $PLUGIN_SOURCE into $CONTAINER:$DEST"

# Make sure the plugins parent dir exists.
docker exec "$CONTAINER" mkdir -p /home/fpp/media/plugins

# Wipe any prior copy so this is a clean install.
docker exec "$CONTAINER" rm -rf "$DEST"

# Copy the source tree in. docker cp on a directory creates the dest dir.
docker cp "$PLUGIN_SOURCE/." "$CONTAINER:$DEST"

# Files copied via `docker cp` end up owned by root. FPP's web API expects
# fpp:fpp ownership for the plugin config file (otherwise WriteSettingToFile
# fails an flock check). Chown the whole tree.
docker exec "$CONTAINER" chown -R fpp:fpp "$DEST"

# Run the plugin's fpp_install.sh if present. This mirrors what FPP does
# after a real `git clone` of the plugin.
if docker exec "$CONTAINER" test -x "$DEST/scripts/fpp_install.sh"; then
    echo "Running $PLUGIN_NAME/scripts/fpp_install.sh..."
    docker exec -e FPPDIR=/opt/fpp "$CONTAINER" "$DEST/scripts/fpp_install.sh"
fi

# Confirm FPP's plugin manager sees it.
echo ""
echo "Installed plugins:"
curl -sf http://127.0.0.1:18080/api/plugin
echo ""
