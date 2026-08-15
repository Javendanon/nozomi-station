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

  test "pairs a Spotify track with a playable YouTube result" do
    fetch = fn
      :spotify, "spotify_789" ->
        {:ok, %{title: "Shinkansen", artist: "Hikari"}}

      :youtube_search, "Hikari Shinkansen" ->
        {:ok, "youtube_match"}

      :youtube, "youtube_match" ->
        {:ok,
         %{
           youtube_id: "youtube_match",
           title: "Shinkansen",
           artist: "Hikari",
           duration: "PT5M1S",
           live?: false
         }}
    end

    assert {:ok, track} =
             Resolver.resolve("https://open.spotify.com/track/spotify_789?si=share", fetch)

    assert track.youtube_id == "youtube_match"
    assert track.duration_seconds == 301
  end
end
