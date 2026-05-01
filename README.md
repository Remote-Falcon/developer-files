# developer-files

Tooling and reference configurations for Remote Falcon developers and
operators. Stuff that doesn't belong in any single service repo lives
here: docker-compose stacks, deployment scripts, test environments,
and standalone utilities.

## Contents

| Directory / file | Purpose |
|---|---|
| [`fpp-test-env/`](./fpp-test-env) | Virtual FPP environment for plugin development. Boots the official `falconchristmas/fpp` Docker image alongside a configurable mock Remote Falcon API so plugin authors can install, exercise, and assert against a plugin without touching hardware or hitting the production RF backend. |
| [`local-docker-compose/`](./local-docker-compose) | Single docker-compose stack that runs the entire Remote Falcon platform locally (Mongo, plugins-api, control-panel, viewer, gateway, UI, etc.). For end-to-end backend development. See the [Local Development guide](https://docs.remotefalcon.com/docs/developer-docs/welcome) on the docs site for setup. |
| [`do-ubuntu-droplet/`](./do-ubuntu-droplet) | Scripts and configs for spinning up the full RF stack on a DigitalOcean Ubuntu droplet: `docker-install.sh`, `nginx-config.sh`, `start-rf.sh`, `stop-rf.sh`, `restart-rf.sh`, plus the corresponding `docker-compose.yaml` and nginx `default.conf`. See the docs site for the full walkthrough. |
| [`rf-volume-control.php`](./rf-volume-control.php) | Standalone helper that watches FPP playback and toggles audio volume between a "request playing" level and a "normal scheduled" level. Drop it on an FPP host and run it as a long-lived process if your show needs different volumes for viewer-driven sequences. |

For most of the above (other than `fpp-test-env`, which is new), the
authoritative usage docs live at the [Remote Falcon Developer Docs](https://docs.remotefalcon.com/docs/developer-docs/welcome).

---

## fpp-test-env — virtual FPP for plugin testing

A complete plugin development environment that runs entirely in Docker.
Pairs the official FPP image with a mock Remote Falcon plugins API so
plugin code can be installed, started, and asserted against without
real hardware and without a real RF account.

**See [`fpp-test-env/README.md`](./fpp-test-env/README.md) for full
documentation.** What follows is a quick orientation.

### What you get

- **Real FPP** — the upstream `falconchristmas/fpp:9.5.3` image.
  Real FPPD daemon, real apache + php-fpm, real plugin manager.
  Hardware-dependent features (GPIO, USB pixel drivers, real audio
  output) don't work; everything else does.
- **Mock Remote Falcon API** — a small `php -S` server with sensible
  no-op success defaults for every plugin-API endpoint, configurable
  per-route via JSON, with full request recording so smoke tests can
  assert on what the plugin called.
- **First-run wizard pre-bypassed** — every spin-up sets the
  `initialSetup` flags so you land directly on the FPP main page
  instead of clicking through the onboarding interstitial.
- **Orchestration scripts** — bring the env up, install a plugin,
  seed plugin config, start the listener, run a smoke script, tear
  down.

### Requirements

- Docker (29+ tested)
- `bash`, `curl`, `python3`

### Quickstart

```bash
cd fpp-test-env

# Bring up FPP + mock RF. ~5s on cached image, ~90s first run.
./scripts/spin-up.sh

# Install the plugin you want to test from a host source dir.
./scripts/install-plugin.sh ~/path/to/your-plugin your-plugin-name

# Seed plugin settings. Values are urlencoded into
# /home/fpp/media/config/plugin.<name> inside the container.
./scripts/seed-config.sh your-plugin-name \
    remoteToken=test-token \
    pluginsApiPath=http://mock-rf-api \
    remoteFalconListenerEnabled=true

# Start the plugin's listener (if it has one).
./scripts/start-listener.sh your-plugin-name

# Browser at http://127.0.0.1:18080 — full FPP web UI is now
# clickable. Plugin appears in the FPP plugin manager.

# Run a plugin-side smoke script (optional, plugin-defined).
./scripts/smoke-test.sh ~/path/to/your-plugin/tests/virtual-fpp/smoke.sh

# When done.
./scripts/tear-down.sh
```

### URLs the harness exposes

| URL | What it is |
|---|---|
| `http://127.0.0.1:18080` | FPP web UI and API on the host |
| `http://127.0.0.1:18081` | Mock RF API on the host (for sanity checks) |
| `http://mock-rf-api` (in-container) | Mock RF API as the listener sees it |

### Configuring mock RF responses

The mock reads route config from `fpp-test-env/.state/config.json`
on every request and appends every received request to
`fpp-test-env/.state/recordings.json`. Smoke scripts (and you, when
exploring interactively) can rewrite the config to simulate any
backend response:

```bash
# Make the mock return a "winning vote" so the plugin queues a sequence.
cat > fpp-test-env/.state/config.json <<EOF
{
  "/highestVotedPlaylist": {
    "body": {"winningPlaylist": "happy.fseq", "playlistIndex": 1}
  }
}
EOF

# Watch the listener pick it up.
docker exec rf-test-fpp tail -f /home/fpp/media/logs/your-plugin-listener.log
```

Route config supports `body` (string/array/object), `status` (HTTP
code, default 200), `contentType` (default `application/json`),
`delayMs` (for testing timeout behavior), and `*`-suffix path
patterns for prefix matching. Endpoints not in the config get
sensible defaults — see [`fpp-test-env/mock-rf-api/router.php`](./fpp-test-env/mock-rf-api/router.php).

### Smoke script contract

Plugin-side smoke scripts are owned by the plugin repo, not this
harness. `scripts/smoke-test.sh` invokes the script with these env
vars populated:

| Variable | Value |
|---|---|
| `FPP_BASE_URL` | `http://127.0.0.1:18080` |
| `FPP_CONTAINER` | `rf-test-fpp` |
| `MOCK_RF_BASE_URL` | `http://127.0.0.1:18081` (host-side) |
| `MOCK_RF_INTERNAL_URL` | `http://mock-rf-api` (in-container) |
| `MOCK_RF_STATE_DIR` | absolute path to `.state/` |

Smoke scripts should `set -e`, exit 0 on success, and return a
non-zero status on failure. Plain bash + `curl` + `jq` is a fine
toolchain; no test framework required.

### Caveats

- The upstream FPP project explicitly marks the Docker image as
  developer-only ("only a subset of FPP features work under docker").
  For our use case (plugin install, listener startup, FPP web API
  integration testing) that subset is sufficient; for hardware-driven
  features it is not.
- The harness intentionally does **not** install plugins via FPP's
  plugin manager API (which would clone from GitHub). Instead it
  `docker cp`s the local source tree into the container so you can
  iterate on uncommitted local changes.
- First-run pulls the FPP image (~830 MB). Cached spin-ups drop to
  ~5–15 s.
- Each spin-up boots a fresh FPP. State (settings, playlists, plugin
  data) does not persist across `tear-down.sh` → `spin-up.sh` cycles.
  If you want it to, mount a host directory to `/home/fpp/media`
  in `fpp-test-env/docker-compose.yaml`.

### Troubleshooting

- **Port 18080 or 18081 already in use** — free the port or edit the
  host-port mappings in `fpp-test-env/docker-compose.yaml`.
- **`WriteSettingToFile` flock errors** — usually means a config file
  ended up root-owned. Re-run `chown -R fpp:fpp` on the plugin dir
  inside the container, or just `tear-down.sh && spin-up.sh` for a
  clean state.
- **FPP won't start** — check `docker compose logs fpp` from
  `fpp-test-env/`. Mid-build kills can leave a half-baked container;
  tear down and retry.

---

## License

See [`LICENSE`](./LICENSE).
