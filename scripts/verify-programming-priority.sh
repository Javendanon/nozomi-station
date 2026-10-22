#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

cleanup() {
  docker compose logs liquidsoap >tmp/priority-verification/liquidsoap.log 2>&1 || true
  docker compose rm -sf liquidsoap >/dev/null 2>&1 || true
  rm -f tmp/media/priority-{c1,c2,c3,r1,r2}.wav
}
trap cleanup EXIT

mkdir -p tmp/media tmp/priority-verification
# Do not reuse persisted segments or queues from a previous run.
docker compose rm -sf liquidsoap >/dev/null 2>&1 || true
rm -rf priv/static/hls
mkdir -p priv/static/hls
for tone in c1:220 c2:330 c3:880 r1:660 r2:990; do
  ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=${tone#*:}:duration=12" \
    "tmp/media/priority-${tone%:*}.wav"
done

LIQUIDSOAP_UID="$(id -u)" LIQUIDSOAP_GID="$(id -g)" docker compose up -d liquidsoap
for _ in $(seq 1 60); do
  if printf 'radio.current_path\nquit\n' | nc -w 1 127.0.0.1 1234 2>/dev/null | grep -q 'END'; then
    break
  fi
  sleep 0.2
done

test "$(docker compose port liquidsoap 1234)" = "127.0.0.1:1234"
python3 scripts/verify-programming-priority.py
