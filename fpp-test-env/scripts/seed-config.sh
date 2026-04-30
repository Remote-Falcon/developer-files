#!/usr/bin/env bash
# Write a plugin's INI config file directly inside the running FPP container,
# bypassing the FPP web API. Used to seed test configuration with values like
# the mock RF API URL and a fake show token before starting the listener.
#
# Usage: seed-config.sh PLUGIN_NAME KEY=VALUE [KEY=VALUE ...]
#
# Values may include URL-unsafe characters; they will be urlencoded before
# being written, matching what WriteSettingToFile does in FPP's common.php.

set -euo pipefail

if [ "${1-}" = "" ] || [ "${2-}" = "" ]; then
    cat >&2 <<EOF
usage: $0 PLUGIN_NAME KEY=VALUE [KEY=VALUE ...]

example:
  $0 remote-falcon \\
     remoteToken=test-token-123 \\
     pluginsApiPath=http://mock-rf-api/ \\
     remotePlaylist=TestPlaylist \\
     remoteFalconListenerEnabled=true
EOF
    exit 1
fi

PLUGIN_NAME="$1"
shift
CONTAINER="rf-test-fpp"
CONFIG_PATH="/home/fpp/media/config/plugin.${PLUGIN_NAME}"

if ! docker ps --filter "name=^${CONTAINER}$" --format '{{.Names}}' | grep -q "$CONTAINER"; then
    echo "Container $CONTAINER is not running. Run scripts/spin-up.sh first." >&2
    exit 1
fi

# Generate the INI inside the container so urlencoding uses the same PHP
# semantics as WriteSettingToFile would.
PHP_PROG='
$path = $_SERVER["argv"][1];
array_shift($_SERVER["argv"]); array_shift($_SERVER["argv"]);
$existing = is_file($path) ? (parse_ini_file($path) ?: []) : [];
foreach ($_SERVER["argv"] as $kv) {
    [$k, $v] = explode("=", $kv, 2) + [null, null];
    if ($k === null) continue;
    $existing[$k] = urlencode($v);
}
$out = "";
foreach ($existing as $k => $v) {
    $out .= sprintf("%s = \"%s\"\n", $k, $v);
}
file_put_contents($path, $out);
chown($path, "fpp");
chgrp($path, "fpp");
chmod($path, 0664);
'

docker exec "$CONTAINER" mkdir -p /home/fpp/media/config
docker exec "$CONTAINER" php -r "$PHP_PROG" "$CONFIG_PATH" "$@"

echo "Seeded $CONFIG_PATH with $#  setting(s)."
echo "---"
docker exec "$CONTAINER" cat "$CONFIG_PATH"
