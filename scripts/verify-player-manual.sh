#!/usr/bin/env bash
# Browser evidence only; human listening and real-provider evidence are required
# before manual closure. Real Last.fm access is explicit, never part of tests.
set -euo pipefail
cd "$(dirname "$0")/.."

run_id="player-manual-$$"
port="${PLAYER_PORT:-4103}"
server_pid=""
export PLAYER_HLS_DIR="$PWD/priv/static/hls/$run_id"
export PLAYER_MEDIA_DIR="$PWD/tmp/$run_id/media"
export PLAYER_READY_FILE="$PWD/tmp/$run_id/ready"
export LIQUIDSOAP_UID="$(id -u)"
export LIQUIDSOAP_GID="$(id -g)"
export PLAYER_FIRST_TITLE="${PLAYER_FIRST_TITLE:-Blue Monday}"
export PLAYER_FIRST_ARTIST="${PLAYER_FIRST_ARTIST:-New Order}"
export PLAYER_SECOND_TITLE="${PLAYER_SECOND_TITLE:-Bizarre Love Triangle}"
export PLAYER_SECOND_ARTIST="${PLAYER_SECOND_ARTIST:-New Order}"
export PLAYER_REAL_LASTFM="${PLAYER_REAL_LASTFM:-0}"

if test "$PLAYER_REAL_LASTFM" = 1; then
  : "${LASTFM_API_KEY:?Set LASTFM_API_KEY for the explicitly enabled real-provider check}"
fi

compose=(docker compose --project-directory "$PWD" -f scripts/compose.player.yaml -p "$run_id")
cleanup() {
  if test -n "$server_pid"; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" 2>/dev/null || true
  fi
  "${compose[@]}" down --volumes >/dev/null 2>&1 || true
  rm -rf "$PLAYER_HLS_DIR"
}
trap cleanup EXIT

mkdir -p "$PLAYER_MEDIA_DIR" "$PLAYER_HLS_DIR" specs/verifications/evidence
ffmpeg -v error -y -f lavfi -i "sine=frequency=440:duration=60" -c:a aac -b:a 96k "$PLAYER_MEDIA_DIR/first.m4a"
ffmpeg -v error -y -f lavfi -i "sine=frequency=523:duration=60" -c:a aac -b:a 96k "$PLAYER_MEDIA_DIR/second.m4a"

"${compose[@]}" up -d --wait postgres liquidsoap
export POSTGRES_HOST=127.0.0.1
export POSTGRES_PORT="$("${compose[@]}" port postgres 5432 | awk -F: '{print $NF}')"
export LIQUIDSOAP_HOST=127.0.0.1
export LIQUIDSOAP_PORT="$("${compose[@]}" port liquidsoap 1234 | awk -F: '{print $NF}')"

MIX_ENV=dev mix assets.build
# No normal dev server or seed invocation: workers are disabled before app start.
PORT="$port" MIX_ENV=dev mix run --no-start --no-halt scripts/player-manual-server.exs >"tmp/$run_id/phoenix.log" 2>&1 &
server_pid=$!

for _ in {1..90}; do
  if test -f "$PLAYER_READY_FILE" && test -f "$PLAYER_HLS_DIR/live.m3u8"; then
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    tail -40 "tmp/$run_id/phoenix.log"
    exit 1
  fi
  sleep 1
done

test -f "$PLAYER_READY_FILE"
test -f "$PLAYER_HLS_DIR/live.m3u8"

node scripts/verify-player-browser.mjs \
  --url "http://127.0.0.1:$port/" \
  --stream-url "/hls/$run_id/live.m3u8" \
  --first-title "$PLAYER_FIRST_TITLE" \
  --second-title "$PLAYER_SECOND_TITLE" \
  --out specs/verifications/e05s01-manual.json \
  --evidence specs/verifications/evidence
