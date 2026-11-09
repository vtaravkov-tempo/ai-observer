# AI Observer sandbox runner

Runs AI Observer in a locked-down Docker container so you can try it without
trusting it with your machine. The app has **no internet access and no access
to your files**; it only receives OTLP telemetry from Claude Code and serves
the dashboard.

## Requirements

Docker (Desktop or Engine) and `openssl`. First start builds two images
(the app and a tiny forwarder); the build needs internet, running does not.

## Use

```bash
cd sandbox
./run.sh up      # builds on first run, prints the UI URL and OTLP settings
./run.sh logs    # app logs (./run.sh logs aiobs-fwd for the forwarder)
./run.sh down    # stop and remove containers (data stays in the volume)
./run.sh nuke    # also delete networks and the data volume
```

Ports (host loopback only): UI `8080` (`UI_PORT=...`), OTLP `4319`
(`OTLP_PORT=...`, 4319 rather than 4318 to avoid clashing with a local collector).

Open the UI URL that `up` prints (`http://localhost:8080/?token=...`). The token
is generated into `sandbox/.token` (git-ignored, mode 600).

## Send Claude Code telemetry

```bash
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4319
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Bearer $(cat sandbox/.token)"
```

## What the isolation gives you

| Piece | Setup |
|-------|-------|
| `aiobs` (the app) | Docker `--internal` network (no route out), read-only root FS, all capabilities dropped, `no-new-privileges`, non-root, 1 GB / 2 CPU / 256 PIDs, no published ports, no host mounts (only the named volume `aiobs-data`) |
| `aiobs-fwd` | ~50-line Go TCP forwarder in a `scratch` image. Docker cannot publish ports from an internal network, so this bridges `127.0.0.1:8080/4319` to the app. It forwards bytes to two fixed targets only |
| Extras | Bearer token on API and OTLP, `AI_OBSERVER_REDACT=all` (secrets and personal data removed before storage), 30-day retention |

Not mounted on purpose: `~/.claude`, so import and watch are not used; data
arrives only over OTLP.

## Honest limits

- The forwarder container sits on a network with internet access, but it has no
  code path to use it.
- The image build runs with network (apt, nodesource, npm, go mod). It happens
  inside Docker, not on your host, and the finished image downloads nothing.
- DuckDB comes as prebuilt binaries that cannot be audited here.
- Your prompts and replies from Claude Code end up in the volume and UI
  (after redaction). `./run.sh nuke` removes them.
- Only outbound request found in the code: `ai-observer pricing update`
  (models.dev), manual and not used here.
