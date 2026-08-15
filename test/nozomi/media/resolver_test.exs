defmodule NozomiStation.Media.ResolverTest do
  use ExUnit.Case, async: true

  alias NozomiStation.Media.Resolver

  test "resolves an allowed YouTube URL through a provider identifier" do
    fetch = fn :youtube, "video_123" ->
      {:ok,
       %{
         youtube_id: "video_123",
         title: "Night Train",
         artist: "Nozomi",
         duration: "PT3M20S",
         live?: false
       }}
    end

    assert {:ok, track} = Resolver.resolve("https://youtu.be/video_123", fetch)
    assert track.duration_seconds == 200
    assert track.youtube_id == "video_123"
  end

  test "accepts a canonical YouTube watch URL without forwarding its host" do
    fetch = fn :youtube, "canonical_456" ->
      {:ok,
       %{
         youtube_id: "canonical_456",
         title: "Railway",
         artist: "Express",
         duration: "PT4M",
         live?: false
       }}
    end

    assert {:ok, track} =
             Resolver.resolve(
               "https://www.youtube.com/watch?v=canonical_456&feature=share",
               fetch
             )

    assert track.youtube_id == "canonical_456"
  end
end
