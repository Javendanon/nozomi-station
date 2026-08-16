defmodule NozomiStation.Programming.LastfmTest do
  use ExUnit.Case, async: true

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
                   "#text" => "https://lastfm.freetls.fastly.net/i/u/300x300/cover.jpg",
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
              cover_url: "https://lastfm.freetls.fastly.net/i/u/300x300/cover.jpg",
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
               "image" => [%{"#text" => "https://example.com/tracker.png", "size" => "large"}]
             },
             "toptags" => %{"tag" => [%{"unexpected" => true}]},
             "wiki" => %{"summary" => 123}
           }
         }
       }}
    end

    assert {:ok, %{album: "Album"}} = Lastfm.track_info("Artist", "Track", request)
  end

  test "fails softly when Last.fm is unavailable" do
    assert {:error, :provider_unavailable} =
             Lastfm.track_info("Artist", "Track", fn _ -> {:error, :timeout} end)
  end
end
