#!/usr/bin/env bash
# Records the manual player checklist in a real Chrome: desktop and mobile
# rendering, two consistent windows, a natural track boundary without a
# reload, reduced motion, and Last.fm enrichment when LASTFM_API_KEY is set.
# Writes specs/verifications/e05s01-manual.json plus screenshots in
# specs/verifications/evidence/.
set -euo pipefail

cd "$(dirname "$0")/.."

port=4103
postgres_port=5434
server_pid=""
postgres_was_running=$(docker compose ps --status running --services | grep -qx postgres && echo yes || true)

cleanup() {
  test -z "$server_pid" || kill "$server_pid" >/dev/null 2>&1 || true
  docker compose rm -sf liquidsoap >/dev/null 2>&1 || true
  test "$postgres_was_running" = yes || docker compose rm -sf postgres >/dev/null 2>&1 || true
}
trap cleanup EXIT

if test -f .env; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

export POSTGRES_PORT="$postgres_port"
export LIQUIDSOAP_UID="$(id -u)"
export LIQUIDSOAP_GID="$(id -g)"

mkdir -p tmp tmp/media specs/verifications/evidence
rm -rf priv/static/hls
mkdir -p priv/static/hls

# Two local tracks; a natural boundary happens without any user interaction.
ffmpeg -v error -y -f lavfi -i "sine=frequency=440:duration=25" -c:a aac -b:a 96k tmp/media/manual-train-a.m4a
ffmpeg -v error -y -f lavfi -i "sine=frequency=523:duration=25" -c:a aac -b:a 96k tmp/media/manual-train-b.m4a

docker compose rm -sf liquidsoap >/dev/null 2>&1 || true
docker compose up -d --wait postgres liquidsoap

MIX_ENV=dev mix ecto.create >/dev/null 2>&1 || true
MIX_ENV=dev mix ecto.migrate >/dev/null
MIX_ENV=dev mix assets.build >/dev/null

cat >tmp/seed-player-manual.exs <<'SEED'
import Ecto.Query

alias NozomiStation.Repo
alias NozomiStation.Requests.Request

tracks = [
  {"tmp/media/manual-train-a.m4a", "Manual Train A", "Verification A"},
  {"tmp/media/manual-train-b.m4a", "Manual Train B", "Verification B"}
]

for {path, title, artist} <- tracks do
  Repo.delete_all(from(request in Request, where: request.file_path == ^path))

  %Request{}
  |> Request.changeset(%{
    youtube_id: "manual-#{title}",
    title: title,
    artist: artist,
    duration_seconds: 25,
    slack_user: "U_MANUAL",
    slack_channel: "C_MANUAL",
    thread_ts: "manual",
    listener_message: "Manual player verification",
    status: "queued",
    file_path: path
  })
  |> Repo.insert!()
end
SEED

MIX_ENV=dev mix run tmp/seed-player-manual.exs

PORT="$port" PHX_SERVER=true MIX_ENV=dev mix phx.server >tmp/player-manual-phoenix.log 2>&1 &
server_pid=$!

for _ in {1..60}; do
  curl -fsS "http://127.0.0.1:$port/" >/dev/null 2>&1 && break
  sleep 1
done

if ! curl -fsS "http://127.0.0.1:$port/" >/dev/null 2>&1; then
  tail -40 tmp/player-manual-phoenix.log
  echo "Phoenix did not answer on port $port" >&2
  exit 1
fi

for _ in {1..30}; do
  test -f priv/static/hls/live.m3u8 && break
  sleep 1
done
test -f priv/static/hls/live.m3u8

cat >tmp/queue-player-manual.exs <<'QUEUE'
alias NozomiStation.Programming.LiquidsoapClient

for path <- ["tmp/media/manual-train-a.m4a", "tmp/media/manual-train-b.m4a"] do
  :ok = LiquidsoapClient.push(:requested, path)
end
QUEUE

MIX_ENV=dev mix run tmp/queue-player-manual.exs

node scripts/verify-player-browser.mjs \
  --url "http://127.0.0.1:$port/" \
  --out specs/verifications/e05s01-manual.json \
  --evidence specs/verifications/evidence
