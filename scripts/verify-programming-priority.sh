#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

complementary="tmp/media/priority-complementary.m4a"
requested="tmp/media/priority-request.m4a"
liquidsoap_was_running=$(docker compose ps --status running --services | grep -qx liquidsoap && echo yes || true)

cleanup() {
  rm -f "$complementary" "$requested"
  test "$liquidsoap_was_running" = yes || docker compose rm -sf liquidsoap >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p tmp/media priv/static/hls
ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=220:duration=6" "$complementary"
ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=660:duration=3" "$requested"

LIQUIDSOAP_UID="$(id -u)" LIQUIDSOAP_GID="$(id -g)" docker compose up -d --force-recreate liquidsoap

for _ in $(seq 1 30); do
  printf 'help\nquit\n' | nc -w 1 127.0.0.1 1234 2>/dev/null | grep -q 'END' && break
  sleep 0.5
done

MIX_ENV=test mix run -e '
:ok = NozomiStation.Programming.LiquidsoapClient.push(
  :complementary,
  "tmp/media/priority-complementary.m4a"
)
'

for _ in $(seq 1 30); do
  docker compose logs liquidsoap 2>&1 | grep 'Switch to complementary' >/dev/null && break
  sleep 0.2
done
docker compose logs liquidsoap 2>&1 | grep 'Switch to complementary' >/dev/null

started=$(date +%s)
MIX_ENV=test mix run -e '
:ok = NozomiStation.Programming.LiquidsoapClient.push(
  :requested,
  "tmp/media/priority-request.m4a"
)
'

for _ in $(seq 1 50); do
  docker compose logs liquidsoap 2>&1 | grep 'Switch to requested' >/dev/null && break
  sleep 0.2
done
docker compose logs liquidsoap 2>&1 | grep 'Switch to requested' >/dev/null
test $(($(date +%s) - started)) -ge 4

test "$(docker compose port liquidsoap 1234)" = "127.0.0.1:1234"
echo "programming-priority: OK"
