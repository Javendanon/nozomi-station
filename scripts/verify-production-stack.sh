#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Provision images before running this test; it never builds or pulls images.
export PHOENIX_IMAGE="${PHOENIX_IMAGE:-nozomi-station:local}"
export PHX_HOST=station.test ACME_EMAIL=operator@example.invalid
export SLACK_CHANNEL_ID=smoke-channel SPOTIFY_CLIENT_ID=smoke-client
mkdir -p tmp
umask 077
fixture=$(mktemp -d "$PWD/tmp/production-smoke.XXXXXX")
export SECRETS_DIR="$fixture/secrets"
mkdir "$SECRETS_DIR"
project="ns19-smoke-$(basename "$fixture" | tr '[:upper:].' '[:lower:]-')"
compose=(docker compose -p "$project" -f compose.production.yaml -f config/compose.smoke.yaml)
dc() { "${compose[@]}" "$@"; }
cleanup() {
  result=$?
  trap - EXIT
  if (( result != 0 )); then
    dc ps -a >&2 || true
    dc logs --tail 80 >&2 || true
  fi
  dc down --volumes --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$fixture"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf '%s\n' smoke-password > "$SECRETS_DIR/postgres_password"
printf '%s\n' 'ecto://nozomi:smoke-password@postgres/nozomi_station' > "$SECRETS_DIR/database_url"
printf '%080d\n' 1 > "$SECRETS_DIR/secret_key_base"
for secret in slack_signing_secret slack_bot_token spotify_client_secret lastfm_api_key; do
  printf '%s\n' smoke-only > "$SECRETS_DIR/$secret"
done
# Compose file secrets are bind mounts; their contents must be readable by UID 1000.
chmod 444 "$SECRETS_DIR"/*

docker compose -p "$project" -f compose.production.yaml config --format json > "$fixture/production.json"
dc config --format json > "$fixture/config.json"
python3 - "$fixture/config.json" "$fixture/production.json" <<'PY'
import json, sys
config = json.load(open(sys.argv[1]))
production = json.load(open(sys.argv[2]))
services = config['services']
for name, service in services.items():
    assert not service.get('privileged'), name
    assert not service.get('ports'), f'{name} publishes a port during smoke tests'
for name in ('postgres', 'liquidsoap', 'phoenix', 'proxy'):
    assert services[name]['healthcheck']['test'], name
    assert services[name]['restart'] == 'unless-stopped', name
assert services['liquidsoap']['user'] == '100:101'
assert services['migrate']['restart'] == 'no'
assert services['phoenix']['depends_on']['migrate']['condition'] == 'service_completed_successfully'
assert services['proxy']['environment']['TLS_POLICY'] == 'internal'
ports = production['services']['proxy']['ports']
assert len(ports) == 2 and {p['target'] for p in ports} == {80, 443}
assert all(str(p['published']) == str(p['target']) for p in ports)
assert all(not s.get('ports') for n, s in production['services'].items() if n != 'proxy')
assert all(n.get('internal') for n in config['networks'].values()), 'External traffic must be blocked'
assert all(production['networks'][n]['internal'] for n in ('database', 'control', 'web'))
for name, networks in {'postgres': {'database'}, 'migrate': {'database'},
                       'liquidsoap': {'control'}, 'proxy': {'web', 'edge'},
                       'phoenix': {'web', 'database', 'control', 'egress'}}.items():
    assert set(production['services'][name]['networks']) == networks, name
assert services['volume-init']['network_mode'] == 'none'
for name, target in (('liquidsoap', '/media'), ('proxy', '/srv/hls')):
    mount = next(v for v in services[name]['volumes'] if v['target'] == target)
    assert mount['read_only'], (name, target)
for secret in ('DATABASE_URL', 'SECRET_KEY_BASE', 'SLACK_SIGNING_SECRET', 'SLACK_BOT_TOKEN',
               'SPOTIFY_CLIENT_SECRET', 'LASTFM_API_KEY'):
    assert secret not in services['phoenix']['environment'], secret
    assert services['phoenix']['environment'][secret + '_FILE'].startswith('/run/secrets/')
PY

# Fail before starting anything if images have not been provisioned.
while IFS= read -r image; do docker image inspect "$image" >/dev/null; done < <(dc config --images | sort -u)
dc up -d --wait --wait-timeout 180 --no-build --pull never

for service in phoenix liquidsoap; do
  test "$(dc exec -T "$service" id -u)" != 0
done
docker inspect $(dc ps -aq) > "$fixture/containers.json"
python3 - "$fixture/containers.json" <<'PY'
import json, sys
for container in json.load(open(sys.argv[1])):
    assert not any((container['NetworkSettings']['Ports'] or {}).values()), container['Name']
PY
dc exec -T phoenix sh -ec 'command -v yt-dlp; command -v ffmpeg'
dc exec -T phoenix bin/nozomi_station eval \
  '{:ok, s} = :gen_tcp.connect(~c"liquidsoap", 1234, [:binary, active: false], 2_000); :ok = :gen_tcp.send(s, "help\n"); {:ok, _} = :gen_tcp.recv(s, 0, 2_000); :gen_tcp.close(s)'

dc cp proxy:/data/caddy/pki/authorities/local/root.crt "$fixture/root.crt"
chmod 644 "$fixture/root.crt"
dc cp "$fixture/root.crt" phoenix:/tmp/smoke-root.crt
request() {
  dc exec -T phoenix curl --noproxy '*' --silent --show-error --max-time 10 \
    --cacert /tmp/smoke-root.crt --connect-to "$PHX_HOST:443:proxy:443" \
    "https://$PHX_HOST$1" "${@:2}"
}
check_http() {
  test "$(dc exec -T phoenix curl --noproxy '*' --silent --max-time 10 --output /dev/null --write-out '%{http_code}' \
    --connect-to "$PHX_HOST:80:proxy:80" "http://$PHX_HOST/health")" = 308
  request /health --fail | grep -q '"status":"ok"'
  request / --fail > "$fixture/index.html"
  asset=$(python3 - "$fixture/index.html" <<'PY'
from html.parser import HTMLParser
import sys
class Assets(HTMLParser):
    def handle_starttag(self, tag, attrs):
        src = dict(attrs).get('src', '')
        if tag == 'script' and src.startswith('/assets/'):
            print(src)
Assets().feed(open(sys.argv[1]).read())
PY
)
  test -n "$asset"
  request "$asset" --fail --output /dev/null
  request /hls/live.m3u8 --fail | grep -q '^#EXTM3U'
  request /hls/live.m3u8 --fail --head | grep -qi '^cache-control: no-store'
  request /hls/aac.m3u8 --fail > "$fixture/aac.m3u8"
  segment=$(grep -v '^#' "$fixture/aac.m3u8" | head -1 | tr -d '\r')
  test -n "$segment"
  request "/hls/$segment" --fail --output /dev/null
  test "$(request /hls/state.config --output /dev/null --write-out '%{http_code}')" = 404
}
check_http

# Migrations are repeatable and do not start application workers.
dc run --rm --no-deps --pull never migrate
sql() { dc exec -T postgres psql -U nozomi -d nozomi_station -v ON_ERROR_STOP=1 -Atc "$1"; }
test "$(sql 'SELECT count(*) FROM schema_migrations')" -ge 5
sql "CREATE TABLE deployment_smoke (value text); INSERT INTO deployment_smoke VALUES ('persisted');"
dc exec -T phoenix sh -ec 'echo persisted > /media/deployment-smoke'
dc exec -T liquidsoap sh -ec 'echo persisted > /hls/deployment-smoke'
dc exec -T proxy sh -ec 'echo persisted > /config/deployment-smoke'
root_before=$(shasum -a 256 "$fixture/root.crt" | awk '{print $1}')

# Readiness must fail closed on a database outage, without disclosing details.
dc stop postgres
test "$(request /health --output /tmp/unavailable.json --write-out '%{http_code}')" = 503
dc exec -T phoenix grep -q '"status":"unavailable"' /tmp/unavailable.json
dc up -d --wait --wait-timeout 60 --no-build --pull never postgres

# Recreate containers without deleting volumes; this is not a playback-recovery test.
dc down
dc up -d --wait --wait-timeout 180 --no-build --pull never
dc cp proxy:/data/caddy/pki/authorities/local/root.crt "$fixture/root.crt"
chmod 644 "$fixture/root.crt"
dc cp "$fixture/root.crt" phoenix:/tmp/smoke-root.crt
test "$(shasum -a 256 "$fixture/root.crt" | awk '{print $1}')" = "$root_before"
test "$(sql 'SELECT value FROM deployment_smoke')" = persisted
dc exec -T liquidsoap grep -qx persisted /media/deployment-smoke
dc exec -T liquidsoap grep -qx persisted /hls/deployment-smoke
dc exec -T proxy grep -qx persisted /config/deployment-smoke
check_http
echo 'production-stack: OK (TLS, health, migrations, isolation, ownership, persistence)'
