defmodule NozomiStation.Programming.MoodTest do
  use NozomiStation.DataCase, async: true

  alias NozomiStation.Programming.{Lastfm, Mood}
  alias NozomiStation.Repo
  alias NozomiStation.Requests.Request

  test "uses only the latest twenty reproducible, non-skipped requests" do
    requests = for index <- 1..25, do: insert_request(index, "played")

    requests
    |> Enum.at(24)
    |> Request.changeset(%{status: "skipped"})
    |> Repo.update!()

    requests
    |> Enum.at(23)
    |> Request.changeset(%{status: "failed"})
    |> Repo.update!()

    mood = Mood.recent()

    assert length(mood) == 20
    assert hd(mood) == %{title: "Track 23", artist: "Artist 23"}
    assert List.last(mood) == %{title: "Track 4", artist: "Artist 4"}
    refute Enum.any?(mood, &(&1.title in ["Track 24", "Track 25"]))
  end

  test "mood candidates use track similarity and never seed tags" do
    mood = [
      %{title: "Blue Monday", artist: "New Order"},
      %{title: "Just Like Heaven", artist: "The Cure"}
    ]

    request = fn options ->
      send(self(), {:request, options[:params]})
      title = options[:params][:track]

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "similartracks" => %{
             "track" => [%{"name" => "Like #{title}", "artist" => "Related"}]
           }
         }
       }}
    end

    assert {:ok, candidates} = Lastfm.candidates(mood, 2, request)
    assert Enum.map(candidates, & &1.title) == ["Like Blue Monday", "Like Just Like Heaven"]

    assert_received {:request, first}
    assert_received {:request, second}
    assert first[:method] == "track.getsimilar"
    assert second[:method] == "track.getsimilar"
    refute Keyword.has_key?(first, :tag)
    refute Keyword.has_key?(second, :tag)
  end

  defp insert_request(index, status) do
    attrs = %{
      youtube_id: "mood-#{index}",
      title: "Track #{index}",
      artist: "Artist #{index}",
      duration_seconds: 180,
      slack_user: "U01",
      slack_channel: "C01",
      thread_ts: Integer.to_string(index),
      status: status,
      file_path: "/media/#{index}.m4a"
    }

    %Request{} |> Request.changeset(attrs) |> Repo.insert!()
  end
end
