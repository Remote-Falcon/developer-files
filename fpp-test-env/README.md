# fpp-test-env

A virtual FPP environment for plugin development. Spins up a real FPP
container alongside a configurable mock Remote Falcon API so plugins can
be installed, exercised, and asserted against without touching real
hardware or hitting the production RF backend.

## What's in the box

- **`falconchristmas/fpp:9.5.3`** — the official FPP Docker image
  ([source](https://github.com/FalconChristmas/fpp/blob/master/Docker/Dockerfile)).
  Real FPPD daemon, real apache + php-fpm, real plugin manager.
- **Mock RF API** (`mock-rf-api/router.php`) — a tiny `php -S` server that
  returns canned responses for `/remotePreferences`, `/highestVotedPlaylist`,
  `/nextPlaylistInQueue`, `/updateWhatsPlaying`, `/updateNextScheduledSequence`,
  `/q/health`, `/syncPlaylists`, `/purgeQueue`, etc. Defaults are no-op
  successful responses; tests override per-route via JSON config.
- **Orchestration scripts** — bring the env up, install a plugin, seed
  plugin config, run a plugin-specific smoke script, tear down.

## Requirements

- Docker (tested with Docker 29+).
- `bash`, `curl`, `python3` (for sanity checks).
- The plugin you want to test, checked out somewhere on your host.

## Quickstart

```bash
cd developer-files/fpp-test-env

# Bring up FPP + mock RF API. ~5s on cached image, ~90s first run.
./scripts/spin-up.sh

# Install a plugin from a host source directory.
./scripts/install-plugin.sh ~/rf-build/remote-falcon-plugin remote-falcon

# Seed plugin settings. The values are urlencoded and written to
# /home/fpp/media/config/plugin.<name> inside the container, mimicking
# what FPP's WriteSettingToFile would do.
./scripts/seed-config.sh remote-falcon \
    remoteToken=test-token-xyz \
    pluginsApiPath=http://mock-rf-api \
    remotePlaylist=TestPlaylist \
    remoteFalconListenerEnabled=true \
    remoteFalconListenerRestarting=false \
    interruptSchedule=false \
    requestFetchTime=3 \
    additionalWaitTime=0 \
    fppStatusCheckTime=1 \
    verboseLogging=true

# Start the listener. (Plugin-specific; the harness doesn't assume
# every plugin has a long-running listener.)
docker exec rf-test-fpp /home/fpp/media/plugins/remote-falcon/scripts/postStart.sh

# Run a plugin-specific smoke script.
./scripts/smoke-test.sh ~/rf-build/remote-falcon-plugin/tests/virtual-fpp/smoke.sh

# When done.
./scripts/tear-down.sh
```

## What the harness exposes

| URL / path | Purpose |
|---|---|
| `http://127.0.0.1:18080` | FPP web UI and API on the host |
| `http://127.0.0.1:18081` | Mock RF API on the host (for sanity checks) |
| `http://mock-rf-api` | Mock RF API as the listener sees it (in-network) |
| `.state/config.json` | Mock RF route config; smoke scripts write this |
| `.state/recordings.json` | Every request the mock received; smoke scripts read this |

The state directory is recreated on each `spin-up.sh` and removed by
`tear-down.sh`.

## Configuring mock RF responses from a smoke script

The mock reads route config from `.state/config.json` on every request, so
smoke scripts can change responses mid-run by rewriting that file. Example:

```bash
STATE="$MOCK_RF_STATE_DIR"

# Make the mock return a specific winning sequence.
cat > "$STATE/config.json" <<EOF
{
  "/highestVotedPlaylist": {
    "body": {"winningPlaylist": "happy.fseq", "playlistIndex": 7}
  }
}
EOF

# Trigger the listener... (e.g., create a playlist with seconds_remaining<3)

# Read what the listener sent back.
cat "$STATE/recordings.json" | python3 -m json.tool
```

Route config supports:
- `body` — string, array, or object. Arrays/objects are JSON-encoded.
- `status` — HTTP status code (default 200).
- `contentType` — Content-Type header (default `application/json`).
- `delayMs` — sleep before responding (for timeout testing).
- Path patterns ending in `*` match prefix.

Endpoints not in the config get sensible defaults (see `mock-rf-api/router.php`).

## Smoke script conventions

Smoke scripts are owned by the plugin repo, not the harness. They receive
these env vars from `smoke-test.sh`:

| Variable | Value |
|---|---|
| `FPP_BASE_URL` | `http://127.0.0.1:18080` |
| `FPP_CONTAINER` | `rf-test-fpp` |
| `MOCK_RF_BASE_URL` | `http://127.0.0.1:18081` (host-side) |
| `MOCK_RF_INTERNAL_URL` | `http://mock-rf-api` (in-container, for the listener) |
| `MOCK_RF_STATE_DIR` | absolute path to the harness's `.state/` |

A smoke script should `set -e`, exit 0 on success, and any non-zero on
failure. The harness is intentionally agnostic about test framework;
plain bash + `curl` + `jq` works fine.

## Caveats

- The Docker image is community-maintained by FPP itself but is explicitly
  marked as developer-only by upstream — "only a subset of FPP features
  work under docker." Hardware-dependent features (GPIO, USB pixel
  drivers, real audio output) won't work in this environment. For our
  use case (plugin install + listener startup + API integration testing)
  that subset is sufficient.
- The harness intentionally does NOT install the plugin via FPP's plugin
  manager API (which would clone from GitHub). Instead it `docker cp`s
  the local source tree into `/home/fpp/media/plugins/<name>/` so you
  can iterate on uncommitted local changes.
- `seed-config.sh` writes the INI directly. If your plugin's listener
  runs setup logic that depends on FPP's `WriteSettingToFile` having
  populated the config, that will run on first listener start.
- First-run pulls the FPP image (~830 MB). Cached runs reuse the
  pulled layers; spin-up drops to ~5–15 s.

## Troubleshooting

**FPP won't start.** Run `docker compose logs fpp` from this directory.
The image's `runDocker.sh` builds FPP source on first start; if the
container is killed mid-build it can leave a half-baked state. Tear
down with `./scripts/tear-down.sh -v` and try again.

**`WriteSettingToFile` fails with `flock()` error.** The plugin config
file is owned by root (because we copied it in via `docker cp` as root).
`install-plugin.sh` chowns the plugin tree to `fpp:fpp` after copy, but
if you wrote files via `docker exec ... > file` they may end up
root-owned. Re-run `chown -R fpp:fpp` on the plugin dir.

**Port 18080 or 18081 already in use.** Either free the port or edit
the host-port mappings in `docker-compose.yaml`.
