set("log.stdout", true)

source = sine(440.0, amplitude=0.08)
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
  source
)
