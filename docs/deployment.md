# Portable production deployment

Status: review artifacts only. No provider, domain, CDN, or live deployment is
selected or authorized. This covers NS19, the first part of e08s01 task 1.

## Stack contract

Use `compose.production.yaml` **alone**, not as an override of `compose.yaml`.
The latter remains the development stack with loopback database/control ports.

| Service | Role | Network access | Persistent storage |
| --- | --- | --- | --- |
| proxy | Caddy, TLS termination, HLS files, HTTP/WebSocket proxy | Public TCP 80/443; private web network | `caddy-data`, `caddy-config`, HLS read-only |
| phoenix | Non-root OTP release, Oban, API clients | Private web, database and control; outbound API access | `media` read/write |
| postgres | PostgreSQL 17 | Private database network only | `postgres-data` |
| liquidsoap | Non-root UID 100, AAC/HLS generation | Private control network only | `hls` read/write; `media` read-only |
| migrate | One-shot release migration, no application workers | Private database network only | Database schema |
| volume-init | One-shot ownership setup, root only for named volumes | No network | Sets media UID 1000 and HLS UID 100 |

The database and telnet control port have **no host bindings**. Only Phoenix can
reach both. Caddy cannot reach PostgreSQL or Liquidsoap control. The Caddy admin
API stays on its own loopback interface. Never publish ports 4000, 5432, or 1234.

Caddy handles HTTPS redirects and certificate renewal. It forwards WebSockets and
sets the forwarded scheme for Phoenix's existing SSL enforcement. The hostname
also controls Phoenix origin checks. Do not bypass the proxy with a public app
port or trust arbitrary forwarded headers from a future CDN.

HLS stays at `/hls/live.m3u8`. The proxy serves only manifests and MPEG-TS segments
from the shared volume, with `Cache-Control: no-store`. Internal HLS state files
are not public. Assets remain in the Phoenix release image, not a volume.

## Build and review locally

Requirements: Docker with Compose **2.24.4 or newer** (including `!reset`), Bash,
Python 3, and `shasum`. Build for the eventual host architecture; native ARM64 was
tested. Cross-architecture deployment requires a separate build and smoke run.

Provision dependencies and images explicitly. These steps use registry/package
networks and are **not automated tests**:

```bash
docker build -t nozomi-station:review .
docker pull postgres:17-alpine
docker pull savonet/liquidsoap:v2.4.5
docker pull caddy:2.10.2-alpine
```

The multi-stage build includes digested assets and the OTP runtime, plus FFmpeg and
yt-dlp for media preparation. It excludes host dependencies, generated HLS, and
credentials. The builder and runner use Debian trixie. No Mix or source checkout is
needed in the running container. Rebuild to update OS packages and yt-dlp; verify
provider compatibility separately without adding real API calls to automated tests.

Run the production smoke test with already-provisioned images:

```bash
PHOENIX_IMAGE=nozomi-station:review bash scripts/verify-production-stack.sh
```

The script renders production and smoke Compose configurations. It uses fake
credentials, a `.test` hostname, and Caddy's internal CA. Every test network is
`internal: true`; no ports are published, builds/pulls are disabled, and HTTP/TLS
requests run inside containers. No public DNS, ACME, Slack, Last.fm, Spotify, or
YouTube connection is possible. TLS is checked against the generated CA, not with
an insecure certificate bypass. The script creates a unique project and removes
**only its own** containers, volumes, and fixture directory on exit.

The script checks:

- Startup health and database migration ordering/idempotence.
- Non-root users, private control connectivity, and read-only mounts.
- Production port declarations and actual smoke port bindings.
- HTTPS redirect, trusted TLS, and the Phoenix page/assets.
- HLS manifest/segment access and private HLS state rejection.
- A 503 readiness response during a database outage.
- Database, media, HLS, and Caddy persistence across container recreation.
- An unchanged TLS CA fingerprint after recreation.

This does not verify playback-position recovery or production capacity.

## External settings and secrets

Copy `config/production.env.example` to an absolute path outside the checkout,
for example `/etc/nozomi/production.env`. Replace every placeholder. It contains
only non-secret identifiers, hostname, contact email, image tag, and secret paths.
The deployment account must be able to read this file and use Docker.

Create `SECRETS_DIR` outside the checkout, owned by the deployment account, with
mode **0700**. Create the following files without shell quotes around their contents:

| File | Contents |
| --- | --- |
| `postgres_password` | A strong database password, for example `openssl rand -hex 32` |
| `database_url` | `ecto://nozomi:PASSWORD@postgres/nozomi_station`, matching that password; URL-encode special characters |
| `secret_key_base` | A unique value, for example `openssl rand -base64 64` |
| `slack_signing_secret` | Slack signing secret |
| `slack_bot_token` | Slack bot token |
| `spotify_client_secret` | Spotify client secret |
| `lastfm_api_key` | Last.fm API key |

Set these files to **0444**, inside the protected 0700 directory. Local Compose
secrets are read-only file bind mounts, not an encrypted secret store, and do not
remap file ownership. UID 1000 must be able to read the mounted files. The protected
parent prevents other host users from reading them. Restrict Docker access too:
Docker administrators can read all mounted credentials. Do not put secrets in
images, tracked env files, command arguments, logs, or Compose `environment` values.
Use provider-managed secret provisioning once the provider is selected.

Runtime accepts `NAME_FILE` for every required secret and still accepts `NAME` for
non-Compose environments. A configured file takes precedence and missing/empty
files fail startup rather than falling back. `PHX_HOST`, `SLACK_CHANNEL_ID`, and
`SPOTIFY_CLIENT_ID` are mandatory non-secret settings. The image already sets
`PHX_SERVER=true`; media and Liquidsoap paths match at `/media`.

Optional yt-dlp cookies are not part of the base stack. If required, supply a
read-only external secret mount to Phoenix and set `YTDLP_COOKIES_FILE` to its
container path in a reviewed operator override. Never bake browser cookies into
the image or expose the media volume through the proxy.

## Pending operator decisions before any real deployment

- **Provider:** select CPU architecture, disk size, backups, region and egress
  allowance. Pin reviewed image digests, including the Phoenix release artifact.
  Keep its source revision and previous image for rollback.
- **Domain:** select a hostname and set `PHX_HOST`. Configure DNS A/AAAA only for
  available interfaces. Set `ACME_EMAIL`; permit inbound TCP 80/443 and outbound
  HTTPS/DNS for Caddy renewal. Public ACME must not be tested in automated checks.
- **Host:** approve Docker installation/start-on-boot, firewall, restricted SSH,
  log rotation, disk monitoring and backup destination. Docker publishing can
  bypass host firewall rules; check provider firewall rules as well.
- **CDN:** direct origin access is the initial configuration, not a provider
  selection. Before enabling a CDN, approve origin TLS, WebSocket support,
  forwarded-header trust, allowed origin access and cache policy. Never cache
  `/hls/*.m3u8`, `/slack/events`, LiveView or health responses. Segment caching is
  also disabled until a retention/cache policy is reviewed.
- **Integrations:** validate credentials and Slack's `POST /slack/events` URL only
  during an authorized live check. Live Slack/media resolution is not covered by
  the offline smoke test.

## Operator commands after approval

These commands are a runbook, **not evidence of an actual deployment**. Run from
the checkout. Use a stable project name so volumes survive updates:

```bash
dc() {
  docker compose --env-file /etc/nozomi/production.env \
    -p nozomi -f compose.production.yaml "$@"
}
dc config --quiet
dc build phoenix
dc up -d --wait --wait-timeout 180 --no-build
dc ps -a
```

`postgres` must be healthy before `migrate` runs. Migration failure blocks Phoenix
and the proxy. `volume-init` must succeed before Liquidsoap/Phoenix start.
Liquidsoap's healthcheck requires a manifest and a recent segment; Phoenix queries
the database at `/health`; the proxy checks its loopback admin API. The smoke test
separately checks end-to-end HTTPS and HLS. An unhealthy status **does not itself
restart a container**. `unless-stopped` restarts exited long-running services;
external monitoring and recovery automation remain follow-up work.

Before an image update, back up PostgreSQL and confirm schema compatibility. For
this single-host setup, accept an outage while stopping the app and migrating:

```bash
dc stop proxy phoenix
dc run --rm --no-deps migrate
dc up -d --wait --wait-timeout 180 --no-build
```

Do not proceed after a failed migration. Inspect logs without sharing credentials.
For an image rollback, restore the previous `PHOENIX_IMAGE` and recreate Phoenix
only if it supports the current schema. No automatic destructive schema rollback
is provided. Restore a tested database backup if schema compatibility requires it.

`dc down` keeps named volumes. **Never use `down --volumes` on production**.
Back up PostgreSQL and Caddy data/config outside the host. Media is a staging
volume, not a permanent library; retention cleanup and playback recovery belong
to the remaining e08s01 work. Preserved HLS state is not a guarantee that an
in-flight song or an in-memory Liquidsoap queue resumes at the same position.
