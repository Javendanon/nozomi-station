defmodule NozomiStation.Programming.LastfmTest do
  use ExUnit.Case, async: false

  alias NozomiStation.Programming.{Lastfm, Mood}

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

  test "blends full similarity results with available genre and decade tracks" do
    profile = %{tracks: [%{title: "Source", artist: "Artist"}], tags: ["new wave", "80s"]}

    request = fn options ->
      params = options[:params]

      case params[:method] do
        "track.getsimilar" ->
          response("similartracks", for(index <- 1..6, do: "Related #{index}"))

        "tag.gettoptracks" ->
          response("tracks", for(index <- 1..6, do: "#{params[:tag]} #{index}"))
      end
    end

    assert {:ok, candidates} = Lastfm.candidates(profile, 6, request)

    assert Enum.map(candidates, & &1.title) == [
             "Related 1",
             "new wave 1",
             "80s 1",
             "Related 2",
             "new wave 2",
             "80s 2"
           ]
  end

  test "continues similarity collection until the unique limit is reached" do
    profile = %{
      tracks: for(index <- 1..3, do: %{title: "Source #{index}", artist: "Artist"}),
      tags: []
    }

    request = fn options ->
      case options[:params][:track] do
        "Source 1" -> response("similartracks", ["Shared", "Shared"])
        "Source 2" -> response("similartracks", ["Shared", "Second"])
        "Source 3" -> response("similartracks", ["Third"])
      end
    end

    assert {:ok, candidates} = Lastfm.candidates(profile, 3, request)
    assert Enum.map(candidates, & &1.title) == ["Shared", "Second", "Third"]
  end

  test "overlapping similarity and tag responses do not suppress useful tags" do
    profile = %{
      tracks: for(index <- 1..2, do: %{title: "Source #{index}", artist: "Artist"}),
      tags: ["new wave", "80s"]
    }

    request = fn options ->
      params = options[:params]

      case {params[:method], params[:tag]} do
        {"track.getsimilar", _} ->
          response("similartracks", ["Shared", "Second"])

        {"tag.gettoptracks", "new wave"} ->
          response("tracks", ["Shared", "Second", "Shared", "Second"])

        {"tag.gettoptracks", "80s"} ->
          response("tracks", ["Shared", "Decade 1", "Decade 2"])
      end
    end

    assert {:ok, candidates} = Lastfm.candidates(profile, 4, request)
    assert Enum.map(candidates, & &1.title) == ["Shared", "Second", "Decade 1", "Decade 2"]
  end

  test "duplicate seed results do not prevent the other seed from filling the limit" do
    request = fn options ->
      case options[:params][:tag] do
        "rock" -> response("tracks", ["Shared", "Shared", "Second"])
        "80s" -> response("tracks", ["Decade"])
      end
    end

    assert {:ok, candidates} = Lastfm.candidates([], 3, request)
    assert Enum.map(candidates, & &1.title) == ["Shared", "Decade", "Second"]
  end

  test "sparse tag results leave room for remaining similarity tracks" do
    profile = %{tracks: [%{title: "Source", artist: "Artist"}], tags: ["new wave", "80s"]}

    request = fn options ->
      params = options[:params]

      case {params[:method], params[:tag]} do
        {"track.getsimilar", _} ->
          response("similartracks", ["Related 1", "Related 2", "Related 3"])

        {"tag.gettoptracks", "new wave"} ->
          response("tracks", ["Genre"])

        {"tag.gettoptracks", "80s"} ->
          response("tracks", [])
      end
    end

    assert {:ok, candidates} = Lastfm.candidates(profile, 4, request)
    assert Enum.map(candidates, & &1.title) == ["Related 1", "Genre", "Related 2", "Related 3"]
  end

  test "default mood metadata callback accepts a nonempty mood without an API key" do
    key = Application.fetch_env!(:nozomi_station, :lastfm_api_key)
    Application.put_env(:nozomi_station, :lastfm_api_key, nil)
    on_exit(fn -> Application.put_env(:nozomi_station, :lastfm_api_key, key) end)
    tracks = [%{title: "Source", artist: "Artist"}]

    assert %{tracks: ^tracks, tags: []} = Mood.profile(mood: fn -> tracks end)
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

  defp response(container, titles) do
    tracks = Enum.map(titles, &%{"name" => &1, "artist" => %{"name" => "Artist"}})
    {:ok, %Req.Response{status: 200, body: %{container => %{"track" => tracks}}}}
  end
end
