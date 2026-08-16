defmodule NozomiStation.Programming.NowPlayingTest do
  use NozomiStation.DataCase, async: false

  alias NozomiStation.Programming.{ComplementaryTrack, NowPlaying}
  alias NozomiStation.Repo

  test "publishes the active database track enriched once" do
    track =
      %ComplementaryTrack{}
      |> ComplementaryTrack.changeset(%{
        youtube_id: "now-playing",
        title: "Blue Monday",
        artist: "New Order",
        duration_seconds: 451,
        origin: "seed",
        status: "queued",
        file_path: "tmp/media/c1.m4a"
      })
      |> Repo.insert!()

    topic = "now-playing-test-#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(NozomiStation.PubSub, topic)

    pid =
      start_supervised!(
        {NowPlaying,
         name: nil,
         topic: topic,
         poll_interval: 60_000,
         current_path: fn -> {:ok, track.file_path} end,
         enrich: fn base -> {:ok, Map.put(base, :album, "Substance")} end}
      )

    assert_receive {:now_playing, now_playing}
    assert now_playing.title == "Blue Monday"
    assert now_playing.artist == "New Order"
    assert now_playing.album == "Substance"
    assert NowPlaying.current(pid) == now_playing
  end

  test "retains the last track when the control boundary fails" do
    calls = start_supervised!({Agent, fn -> 0 end})
    topic = "now-playing-test-#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(NozomiStation.PubSub, topic)

    current_path = fn ->
      case Agent.get_and_update(calls, &{&1, &1 + 1}) do
        0 -> {:ok, "tmp/media/missing.m4a"}
        _ -> {:error, :control_unavailable}
      end
    end

    pid =
      start_supervised!(
        {NowPlaying,
         name: nil,
         topic: topic,
         poll_interval: 60_000,
         current_path: current_path,
         lookup: fn _path -> %{title: "Loaded", artist: "Artist", duration_seconds: 180} end,
         enrich: fn track -> {:ok, track} end}
      )

    assert_receive {:now_playing, %{title: "Loaded"} = original}
    send(pid, :poll)
    _ = :sys.get_state(pid)

    assert NowPlaying.current(pid) == original
    refute_receive {:now_playing, _}
  end
end
