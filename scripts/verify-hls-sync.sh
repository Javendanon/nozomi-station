#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
port=4101
server_pid=""

cleanup() {
  test -z "$server_pid" || kill "$server_pid" >/dev/null 2>&1 || true
  docker compose down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

rm -rf priv/static/hls
docker compose up -d liquidsoap

for _ in {1..30}; do
  test -f priv/static/hls/aac.m3u8 && grep -q '^#EXTINF:' priv/static/hls/aac.m3u8 && break
  sleep 1
done

test -f priv/static/hls/aac.m3u8

PORT=$port PHX_SERVER=true MIX_ENV=test mix phx.server >tmp/sync-phoenix.log 2>&1 &
server_pid=$!

for _ in {1..30}; do
  curl -fsS "http://127.0.0.1:$port/hls/aac.m3u8" >/dev/null 2>&1 && break
  sleep 1
done

# ponytail: shared live-window check; add browser clock sampling if real clients exceed the target.
curl -fsS "http://127.0.0.1:$port/hls/aac.m3u8" >tmp/client-one.m3u8 &
first_client=$!
curl -fsS "http://127.0.0.1:$port/hls/aac.m3u8" >tmp/client-two.m3u8 &
second_client=$!
wait "$first_client" "$second_client"
cmp tmp/client-one.m3u8 tmp/client-two.m3u8

target_duration=$(awk -F: '/^#EXT-X-TARGETDURATION:/{print $2}' tmp/client-one.m3u8 | tr -d '\r')
test "$target_duration" -le 2

first_segments=$(grep -c '^#EXTINF:' tmp/client-one.m3u8)
first_sequence=$(awk -F: '/^#EXT-X-MEDIA-SEQUENCE:/{print $2}' tmp/client-one.m3u8 | tr -d '\r')
sleep 3
curl -fsS "http://127.0.0.1:$port/hls/aac.m3u8" >tmp/client-later.m3u8
later_segments=$(grep -c '^#EXTINF:' tmp/client-later.m3u8)
later_sequence=$(awk -F: '/^#EXT-X-MEDIA-SEQUENCE:/{print $2}' tmp/client-later.m3u8 | tr -d '\r')
test "$later_segments" -gt "$first_segments" || test "$later_sequence" -gt "$first_sequence"

npm --prefix assets test -- js/radio_player.test.mjs
echo "hls-sync: OK"
