set("log.stdout", true)
set("server.telnet", true)
set("server.telnet.bind_addr", "0.0.0.0")
set("server.telnet.port", 1234)

requested = request.queue(id="requested", prefetch=1)
complementary = request.queue(id="complementary", prefetch=1)

# Songs cross-fade for four seconds, keeping request priority at track boundaries.
music = fallback(track_sensitive=true, [requested, complementary])
music = crossfade(id="music", duration=4.0, fade_in=4.0, fade_out=4.0, music)
radio = fallback(track_sensitive=false, [music, sine(440.0, amplitude=0.08)])

# The card and votes switch to the incoming track at the start of the output
# overlap (observed on the next application poll). HLS retains its delivery delay.
# Read after crossfade: queue removal and allocation IDs do not imply play order.
def current_path(_) =
  metadata = radio.last_metadata() ?? []
  metadata["filename"]
end
server.register(namespace="radio", description="Current output track path", "current_path", current_path)

encoder = %ffmpeg(
  format="mpegts",
  %audio(codec="aac", channels=2, ar=44100, b="192k")
)

output.file.hls(
  playlist="live.m3u8",
  segment_duration=2.0,
  segments=6,
  segments_overhead=3,
  persist_at="/hls/state.config",
  "/hls",
  [("aac", encoder)],
  radio
)
