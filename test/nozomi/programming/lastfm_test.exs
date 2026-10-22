defmodule NozomiStation.Programming.LastfmTest do
  use ExUnit.Case, async: false

  alias NozomiStation.Programming.Lastfm

  test "parses optional track information from the fixed Last.fm endpoint" do
    request = fn options ->
      send(self(), {:request, options})

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "track" => %{
             "album" => %{
               "title" => "Substance",
               "image" => [
                 %{"#text" => "", "size" => "small"},
                 %{
                   "#text" => "https://lastfm-img.freetls.fastly.net/i/u/300x300/cover.jpg",
                   "size" => "large"
                 }
               ]
             },
             "toptags" => %{"tag" => [%{"name" => "new wave"}, %{"name" => "80s"}]},
             "wiki" => %{
               "summary" =>
                 "A classic. <a href=\"https://www.last.fm/music/New+Order\">Read more</a>"
             }
           }
         }
       }}
    end

    assert {:ok,
            %{
              album: "Substance",
              cover_url: "https://lastfm-img.freetls.fastly.net/i/u/300x300/cover.jpg",
              tags: ["new wave", "80s"],
              summary: "A classic."
            }} = Lastfm.track_info("New Order", "Blue Monday", request)

    assert_received {:request, options}
    assert options[:url] == "https://ws.audioscrobbler.com/2.0/"
    assert options[:params][:method] == "track.getInfo"
    assert options[:params][:artist] == "New Order"
    assert options[:params][:track] == "Blue Monday"
  end

  test "drops untrusted image hosts and malformed optional fields" do
    request = fn _options ->
      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "track" => %{
             "album" => %{
               "title" => "Album",
               "image" => [
                 %{"unexpected" => true},
                 %{"#text" => "https://example.com/tracker.png", "size" => "large"}
               ]
             },
             "toptags" => %{"tag" => [%{"unexpected" => true}]},
             "wiki" => %{"summary" => 123}
           }
         }
       }}
    end

    assert {:ok, %{album: "Album"}} = Lastfm.track_info("Artist", "Track", request)

    malformed = fn _options ->
      {:ok,
       %Req.Response{
         status: 200,
         body: %{"track" => %{"album" => %{"image" => %{}}, "toptags" => %{}, "wiki" => %{}}}
       }}
    end

    assert {:ok, %{}} = Lastfm.track_info("Artist", "Track", malformed)
  end

  test "fills short similarity results from mood genre and decade tags" do
    request = fn options ->
      send(self(), {:request, options})
      params = options[:params]

      body =
        case params[:method] do
          "track.getsimilar" ->
            %{
              "similartracks" => %{
                "track" => [%{"name" => "Related", "artist" => %{"name" => "Related Artist"}}]
              }
            }

          "tag.gettoptracks" ->
            %{
              "tracks" => %{
                "track" => [
                  %{"name" => "#{params[:tag]} hit", "artist" => %{"name" => "Tag Artist"}}
                ]
              }
            }
        end

      {:ok, %Req.Response{status: 200, body: body}}
    end

    profile = %{tracks: [%{title: "Blue Monday", artist: "New Order"}], tags: ["new wave", "80s"]}

    assert {:ok, candidates} = Lastfm.candidates(profile, 3, request)
    assert Enum.map(candidates, & &1.title) == ["Related", "new wave hit", "80s hit"]

    assert_received {:request, similar}
    assert similar[:params][:method] == "track.getsimilar"
    assert_received {:request, first_tag}
    assert first_tag[:params][:tag] == "new wave"
    assert_received {:request, second_tag}
    assert second_tag[:params][:tag] == "80s"
  end

  test "skips the provider when no API key is configured" do
    key = Application.get_env(:nozomi_station, :lastfm_api_key)
    Application.put_env(:nozomi_station, :lastfm_api_key, nil)
    on_exit(fn -> Application.put_env(:nozomi_station, :lastfm_api_key, key) end)

    assert {:ok, %{}} =
             Lastfm.track_info("Artist", "Track", fn _ -> flunk("unexpected network request") end)
  end

  test "fails softly when Last.fm is unavailable" do
    assert {:error, :provider_unavailable} =
             Lastfm.track_info("Artist", "Track", fn _ -> {:error, :timeout} end)
  end
end
