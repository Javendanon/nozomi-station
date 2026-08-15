set("log.stdout", true)
set("server.telnet", true)
set("server.telnet.bind_addr", "0.0.0.0")
set("server.telnet.port", 1234)

requested = request.queue(id="requested", prefetch=1)
complementary = request.queue(id="complementary", prefetch=1)
music = fallback(track_sensitive=true, [requested, complementary])
radio = fallback(track_sensitive=false, [music, sine(440.0, amplitude=0.08)])

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
