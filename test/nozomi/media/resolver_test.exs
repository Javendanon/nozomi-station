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

  test "fetches YouTube metadata from a fixed API host" do
    request = fn options ->
      send(self(), {:request, options})

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "items" => [
             %{
               "id" => "video_123",
               "contentDetails" => %{"duration" => "PT3M"},
               "snippet" => %{
                 "title" => "Night Train",
                 "channelTitle" => "Nozomi",
                 "liveBroadcastContent" => "none"
               }
             }
           ]
         }
       }}
    end

    assert {:ok, %{youtube_id: "video_123", duration: "PT3M"}} =
             ProviderClient.fetch(:youtube, "video_123", request)

    assert_receive {:request, options}
    assert options[:url] == "https://www.googleapis.com/youtube/v3/videos"
    assert options[:redirect] == false
    assert options[:params][:id] == "video_123"

    assert {:error, :provider_unavailable} =
             ProviderClient.fetch(:youtube_search, "missing", fn _options ->
               {:ok, %Req.Response{status: 200, body: %{"items" => []}}}
             end)
  end

  test "uses fixed Spotify and YouTube endpoints to pair a track" do
    request = fn options ->
      send(self(), {:provider_url, options[:url]})

      response =
        case options[:url] do
          "https://accounts.spotify.com/api/token" ->
            %{"access_token" => "access-token"}

          "https://api.spotify.com/v1/tracks/spotify789" ->
            %{"name" => "Shinkansen", "artists" => [%{"name" => "Hikari"}]}

          "https://www.googleapis.com/youtube/v3/search" ->
            %{"items" => [%{"id" => %{"videoId" => "youtube_match"}}]}

          "https://www.googleapis.com/youtube/v3/videos" ->
            %{
              "items" => [
                %{
                  "id" => "youtube_match",
                  "contentDetails" => %{"duration" => "PT5M1S"},
                  "snippet" => %{
                    "title" => "Shinkansen",
                    "channelTitle" => "Hikari",
                    "liveBroadcastContent" => "none"
                  }
                }
              ]
            }
        end

      {:ok, %Req.Response{status: 200, body: response}}
    end

    fetch = fn provider, value -> ProviderClient.fetch(provider, value, request) end

    assert {:ok, %{youtube_id: "youtube_match"}} =
             Resolver.resolve("https://open.spotify.com/track/spotify789", fetch)

    assert_received {:provider_url, "https://accounts.spotify.com/api/token"}
    assert_received {:provider_url, "https://api.spotify.com/v1/tracks/spotify789"}
    assert_received {:provider_url, "https://www.googleapis.com/youtube/v3/search"}
    assert_received {:provider_url, "https://www.googleapis.com/youtube/v3/videos"}
  end
end
