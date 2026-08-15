defmodule NozomiStation.Media.ResolverTest do
  use ExUnit.Case, async: true

  alias NozomiStation.Media.{ProviderClient, Resolver}

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

  test "resolves a search candidate through the same playback checks" do
    fetch = fn
      :youtube_search, "New Order Blue Monday" ->
        {:ok, "candidate_1"}

      :youtube, "candidate_1" ->
        {:ok,
         %{
           youtube_id: "candidate_1",
           title: "Blue Monday",
           artist: "New Order",
           duration: "PT7M29S",
           live?: false
         }}
    end

    assert {:ok, %{youtube_id: "candidate_1", duration_seconds: 449}} =
             Resolver.resolve_search("New Order Blue Monday", fetch)
  end

  test "pairs a Spotify track with a playable YouTube result" do
    fetch = fn
      :spotify, "spotify789" ->
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
             Resolver.resolve("https://open.spotify.com/track/spotify789?si=share", fetch)

    assert track.youtube_id == "youtube_match"
    assert track.duration_seconds == 301
  end

  test "rejects untrusted hosts, live streams, and tracks over fifteen minutes" do
    refute_fetch = fn _, _ -> flunk("untrusted URL reached provider client") end

    assert {:error, :unsupported_url} =
             Resolver.resolve("https://youtube.com.evil.test/watch?v=x", refute_fetch)

    assert {:error, :unsupported_url} = Resolver.resolve("http://youtu.be/video", refute_fetch)

    assert {:error, :invalid_url} =
             Resolver.resolve("https://www.youtube.com/watch?feature=share", refute_fetch)

    assert {:error, :not_playable} =
             Resolver.resolve("https://youtu.be/live", fn _, _ ->
               {:ok, %{duration: "PT1M", live?: true}}
             end)

    assert {:error, :not_playable} =
             Resolver.resolve("https://youtu.be/long", fn _, _ ->
               {:ok, %{duration: "PT15M1S", live?: false}}
             end)

    assert {:error, :invalid_duration} =
             Resolver.resolve("https://youtu.be/malformed", fn _, _ ->
               {:ok, %{duration: "three minutes", live?: false}}
             end)
  end

  test "fetches Spotify metadata only from fixed endpoints" do
    request = fn options ->
      send(self(), {:provider_url, options[:url]})

      body =
        case options[:url] do
          "https://accounts.spotify.com/api/token" ->
            %{"access_token" => "access-token"}

          "https://api.spotify.com/v1/tracks/spotify789" ->
            %{"name" => "Shinkansen", "artists" => [%{"name" => "Hikari"}]}
        end

      {:ok, %Req.Response{status: 200, body: body}}
    end

    assert {:ok, %{title: "Shinkansen", artist: "Hikari"}} =
             ProviderClient.fetch(:spotify, "spotify789", request)

    assert_received {:provider_url, "https://accounts.spotify.com/api/token"}
    assert_received {:provider_url, "https://api.spotify.com/v1/tracks/spotify789"}

    unavailable = fn _options -> {:ok, %Req.Response{status: 503, body: %{}}} end

    assert {:error, :provider_unavailable} =
             ProviderClient.fetch(:spotify, "missing", unavailable)
  end
end
