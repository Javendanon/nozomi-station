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
end
