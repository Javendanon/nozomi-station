#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

command -v ffmpeg >/dev/null
command -v ffprobe >/dev/null

work=tmp/railway-clips
rm -rf "$work"
mkdir -p "$work"

# Local fixtures only: these prove decoding, peak rejection and normalization.
# They are not contributed recordings and cannot satisfy catalog availability.
ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=660:duration=2" \
  -af "volume=-9dB" "$work/quiet.wav"
ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=660:duration=2" \
  -af "volume=20dB" -c:a aac -b:a 192k -ar 48000 -ac 2 "$work/clipped.m4a"
printf 'not an audio stream\n' >"$work/corrupt.m4a"

MIX_ENV=test mix run --no-start -e '
alias NozomiStation.Railway.Clips

work = Path.expand("tmp/railway-clips")

{:ok, prepared} =
  Clips.prepare(Path.join(work, "quiet.wav"), Path.join(work, "quiet.m4a"))

true = prepared.peak_db <= -1.0
true = prepared.codec == "aac"
true = prepared.sample_rate == 48_000
true = prepared.channels == 2
{:ok, ^prepared} = Clips.verify_file(Path.join(work, "quiet.m4a"))

# Damage an interior AAC packet, leaving the container and other packets readable.
{packets_json, 0} = System.cmd("ffprobe", [
  "-v", "error", "-select_streams", "a:0", "-show_packets",
  "-show_entries", "packet=pos,size", "-of", "json", Path.join(work, "quiet.m4a")
])
packets = Jason.decode!(packets_json)["packets"]
packet = Enum.at(packets, div(length(packets), 2))
position = String.to_integer(packet["pos"])
size = String.to_integer(packet["size"])
<<prefix::binary-size(position), _::binary-size(size), suffix::binary>> =
  File.read!(Path.join(work, "quiet.m4a"))
corrupt = Path.join(work, "partial-corrupt.m4a")
File.write!(corrupt, prefix <> :binary.copy(<<0>>, size) <> suffix)

{errors, 0} = System.cmd("ffmpeg", ["-v", "error", "-nostdin", "-i", corrupt, "-f", "null", "-"],
  stderr_to_stdout: true)
true = errors != ""

case Clips.verify_file(corrupt) do
  {:error, :undecodable} -> :ok
  other -> raise "expected partial corruption rejection, got #{inspect(other)}"
end

previous = File.read!(Path.join(work, "quiet.m4a"))
{:error, :normalization_failed} = Clips.prepare(corrupt, Path.join(work, "quiet.m4a"))
^previous = File.read!(Path.join(work, "quiet.m4a"))

case Clips.verify_file(Path.join(work, "clipped.m4a")) do
  {:error, {:peak_too_high, _peak}} -> :ok
  other -> raise "expected clipped clip rejection, got #{inspect(other)}"
end

case Clips.verify_file(Path.join(work, "corrupt.m4a")) do
  {:error, :undecodable} -> :ok
  other -> raise "expected corrupt clip rejection, got #{inspect(other)}"
end

{:ok, catalog} = Clips.load_catalog()
{:ok, verified} = Clips.verify_catalog(catalog)
pending = Enum.count(catalog.clips, &(&1.status == "pending"))

IO.puts(
  "railway-clips: fixture checks passed; prepared_peak=#{prepared.peak_db}dB"
)

if pending > 0 or verified == [] do
  IO.puts("catalog: BLOCKED (#{length(verified)} available, #{pending} pending); NS11 must not close")
  System.halt(2)
end

IO.puts("catalog: verified #{length(verified)} available clips")
'
