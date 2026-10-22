defmodule NozomiStation.Programming.LastfmTest do
  use ExUnit.Case, async: false

  alias NozomiStation.Programming.Lastfm

  test "parses optional track information from the fixed Last.fm endpoint" do
    request =
      stub(fn
        "track.getInfo" ->
          {200,
           %{
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
           }}

        "album.getInfo" ->
          {200, %{"album" => %{"releasedate" => "7 Mar 1987, 00:00"}}}

        "artist.getSimilar" ->
          {200,
           %{
             "similarartists" => %{
               "artist" => [
                 %{"name" => "Joy Division"},
                 %{"name" => "Depeche Mode"},
                 %{"name" => "New Order"}
               ]
             }
           }}
      end)

    assert {:ok, details} = Lastfm.track_info("New Order", "Blue Monday", request)

    assert details == %{
             album: "Substance",
             cover_url: "https://lastfm-img.freetls.fastly.net/i/u/300x300/cover.jpg",
             tags: ["new wave", "80s"],
             summary: "A classic.",
             year: 1987,
             related: ["Joy Division", "Depeche Mode"]
           }

    requests = collect_requests()

    assert [track, album, similar] = requests
    assert track[:url] == "https://ws.audioscrobbler.com/2.0/"
    assert track[:params][:method] == "track.getInfo"
    assert track[:params][:artist] == "New Order"
    assert track[:params][:track] == "Blue Monday"
    assert album[:params][:method] == "album.getInfo"
    assert album[:params][:album] == "Substance"
    assert similar[:params][:method] == "artist.getSimilar"
    assert similar[:params][:artist] == "New Order"
  end

  test "uses the documented album release date, never the wiki publication date" do
    # Release-date example: https://www.last.fm/api/show/album.getInfo
    for {album, expected} <- [
          {%{"releasedate" => "6 Apr 1999, 00:00"}, %{album: "Believe", year: 1999}},
          {%{"releasedate" => "2024-01-01"}, %{album: "Believe", year: 2024}},
          {%{"releasedate" => "1 Jan 1970, 00:00"}, %{album: "Believe"}},
          {%{"releasedate" => "0000-00-00"}, %{album: "Believe"}},
          {%{"releasedate" => "1800"}, %{album: "Believe"}},
          {%{"wiki" => %{"published" => "6 Apr 1999, 00:00"}}, %{album: "Believe"}}
        ] do
      request =
        stub(fn
          "track.getInfo" -> {200, %{"track" => %{"album" => %{"title" => "Believe"}}}}
          "album.getInfo" -> {200, %{"album" => album}}
          "artist.getSimilar" -> {200, %{"similarartists" => %{"artist" => []}}}
        end)

      assert {:ok, details} = Lastfm.track_info("Cher", "Believe", request)
      assert details == expected
    end
  end

  test "omits year and related when the provider has nothing to enrich with" do
    request =
      stub(fn
        "track.getInfo" -> {200, %{"track" => %{"name" => "Track"}}}
        "artist.getSimilar" -> {200, %{"similarartists" => %{"artist" => []}}}
      end)

    assert {:ok, details} = Lastfm.track_info("Artist", "Track", request)
    assert details == %{}

    methods = Enum.map(collect_requests(), & &1[:params][:method])
    assert methods == ["track.getInfo", "artist.getSimilar"]
  end

  test "drops untrusted image hosts and malformed optional fields" do
    request =
      stub(fn
        "track.getInfo" ->
          {200,
           %{
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
           }}

        "album.getInfo" ->
          {200, %{"album" => %{"releasedate" => "unknown"}}}

        "artist.getSimilar" ->
          {200, %{"similarartists" => %{"artist" => "unexpected"}}}
      end)

    assert {:ok, details} = Lastfm.track_info("Artist", "Track", request)
    assert details == %{album: "Album"}

    malformed =
      stub(fn
        "track.getInfo" ->
          {200,
           %{
             "track" => %{"album" => %{"image" => %{}}, "toptags" => %{}, "wiki" => %{}}
           }}

        method ->
          {200, %{method => "unexpected"}}
      end)

    assert {:ok, details} = Lastfm.track_info("Artist", "Track", malformed)
    assert details == %{}
  end

  test "keeps the track when the enrichment calls fail" do
    request =
      stub(fn
        "track.getInfo" ->
          {200, %{"track" => %{"album" => %{"title" => "Album"}, "toptags" => %{}}}}

        _method ->
          {500, %{"error" => 8}}
      end)

    assert {:ok, details} = Lastfm.track_info("Artist", "Track", request)
    assert details == %{album: "Album"}
  end

  test "skips the provider when no API key is configured" do
    key = Application.get_env(:nozomi_station, :lastfm_api_key)
    Application.put_env(:nozomi_station, :lastfm_api_key, nil)
    on_exit(fn -> Application.put_env(:nozomi_station, :lastfm_api_key, key) end)

    assert {:ok, details} =
             Lastfm.track_info("Artist", "Track", fn _ -> flunk("unexpected network request") end)

    assert details == %{}
  end

  test "fails softly when Last.fm is unavailable" do
    assert {:error, :provider_unavailable} =
             Lastfm.track_info("Artist", "Track", fn _ -> {:error, :timeout} end)
  end

  defp stub(handler) do
    test = self()

    fn options ->
      method = options[:params][:method]
      send(test, {:request, options})

      case handler.(method) do
        {status, body} -> {:ok, %Req.Response{status: status, body: body}}
        other -> other
      end
    end
  end

  defp collect_requests(acc \\ []) do
    receive do
      {:request, options} -> collect_requests([options | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
