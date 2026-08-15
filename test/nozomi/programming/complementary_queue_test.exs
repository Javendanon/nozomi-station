defmodule NozomiStation.Programming.ComplementaryQueueTest do
  use NozomiStation.DataCase, async: true

  alias NozomiStation.Programming.{ComplementaryQueue, ComplementaryTrack, Lastfm, RefillWorker}
  alias NozomiStation.Repo

  test "fills a ten-track margin and ignores failed candidates" do
    candidates = candidates(13)

    resolver = fn
      %{title: "Track 2"} -> {:error, :provider_unavailable}
      candidate -> {:ok, resolved(candidate)}
    end

    prepare = fn
      "Track-1", _output -> {:error, :preparation_failed}
      youtube_id, {:complementary, id} -> {:ok, "/media/c#{id}-#{youtube_id}.m4a"}
    end

    assert {:ok, %{available: 10, discarded: 2}} =
             ComplementaryQueue.fill(candidates, :seed,
               resolver: resolver,
               prepare: prepare
             )

    assert ComplementaryQueue.available_count() == 10
    assert Repo.aggregate(ComplementaryTrack, :count) == 11
    assert Repo.aggregate(from(t in ComplementaryTrack, where: t.status == "failed"), :count) == 1

    assert {:ok, %{available: 10, prepared: 0}} =
             ComplementaryQueue.fill(candidates, :seed,
               resolver: resolver,
               prepare: prepare
             )

    assert {:ok, %{available: 10, prepared: 0}} = RefillWorker.perform(%Oban.Job{})
  end

  test "a skipped complementary track is never selected again" do
    [candidate] = candidates(1)
    resolver = fn candidate -> {:ok, resolved(candidate)} end
    prepare = fn _, {:complementary, id} -> {:ok, "/media/c#{id}.m4a"} end

    assert {:ok, _} =
             ComplementaryQueue.fill([candidate], :mood,
               target: 1,
               resolver: resolver,
               prepare: prepare
             )

    track = Repo.one!(ComplementaryTrack)
    track |> ComplementaryTrack.changeset(%{status: "skipped"}) |> Repo.update!()

    assert {:ok, %{available: 0, prepared: 0, discarded: 1}} =
             ComplementaryQueue.fill([candidate], :mood,
               target: 1,
               resolver: resolver,
               prepare: prepare
             )
  end

  test "refill worker requests enough candidates for the missing margin" do
    candidates = candidates(30)

    source = fn mood, limit ->
      send(self(), {:source, mood, limit})
      {:ok, candidates}
    end

    fill = fn supplied, origin ->
      send(self(), {:fill, supplied, origin})
      {:ok, %{available: 10}}
    end

    assert {:ok, %{available: 10}} =
             RefillWorker.run(
               count: fn -> 0 end,
               mood: fn -> [] end,
               source: source,
               fill: fill
             )

    assert_received {:source, [], 30}
    assert_received {:fill, ^candidates, :seed}
  end

  test "refill worker does nothing when the margin is full" do
    assert {:ok, %{available: 10, prepared: 0}} =
             RefillWorker.run(count: fn -> 10 end)

    assert "programming" == Ecto.Changeset.get_change(RefillWorker.new(%{}), :queue)
  end

  test "uses only rock and 80s tags when there is no mood" do
    request = fn options ->
      send(self(), {:request, options})
      tag = options[:params][:tag]

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "tracks" => %{
             "track" => [
               %{"name" => "#{tag} one", "artist" => %{"name" => "Artist"}}
             ]
           }
         }
       }}
    end

    assert {:ok, candidates} = Lastfm.candidates([], 10, request)
    assert Enum.map(candidates, & &1.title) == ["rock one", "80s one"]

    assert_received {:request, first}
    assert_received {:request, second}
    assert first[:url] == "https://ws.audioscrobbler.com/2.0/"
    assert Enum.map([first, second], & &1[:params][:tag]) == ["rock", "80s"]

    assert Enum.all?(
             [first, second],
             &(&1[:redirect] == false and &1[:receive_timeout] == 10_000)
           )
  end

  test "ignores unavailable and malformed Last.fm responses" do
    request = fn options ->
      if options[:params][:tag] == "rock",
        do: {:error, :timeout},
        else: {:ok, %Req.Response{status: 200, body: %{"unexpected" => []}}}
    end

    assert {:ok, []} = Lastfm.candidates([], 10, request)
  end

  defp candidates(count) do
    for index <- 1..count, do: %{title: "Track #{index}", artist: "Artist #{index}"}
  end

  defp resolved(candidate) do
    %{
      youtube_id: String.replace(candidate.title, " ", "-"),
      title: candidate.title,
      artist: candidate.artist,
      duration_seconds: 180
    }
  end
end
