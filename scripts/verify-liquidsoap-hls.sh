#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

cleanup() {
  docker compose down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

config=$(docker compose config --format json)
python3 -c '
import json, sys
service = json.load(sys.stdin)["services"]["liquidsoap"]
assert not service.get("ports"), "Liquidsoap must not publish ports"
assert service.get("user") not in ("0", "root"), "Liquidsoap must not run as root"
' <<<"$config"

rm -rf priv/static/hls
docker compose up -d liquidsoap

for _ in {1..30}; do
  test -f priv/static/hls/live.m3u8 && break
  sleep 1
done

test -f priv/static/hls/live.m3u8 || {
  docker compose logs liquidsoap
  echo "HLS manifest was not created" >&2
  exit 1
}

grep -q '^#EXTM3U' priv/static/hls/live.m3u8
media_playlist=$(find priv/static/hls -name '*.m3u8' ! -name live.m3u8 -print -quit)
test -n "$media_playlist"
grep -q '^#EXTINF:' "$media_playlist"
segment=$(find priv/static/hls -type f \( -name '*.ts' -o -name '*.m4s' \) -print -quit)
test -n "$segment"
ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$segment" |
  grep -qx 'aac'

echo "liquidsoap-hls: OK"
