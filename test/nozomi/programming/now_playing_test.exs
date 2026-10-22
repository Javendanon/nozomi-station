defmodule NozomiStation.Programming.NowPlayingTest do
  use NozomiStation.DataCase, async: false

  alias NozomiStation.Programming.NowPlaying
  alias NozomiStation.Repo
  alias NozomiStation.Requests.Request

  test "serves the base track while enrichment is pending, then publishes its details" do
    test = self()
    track = %{title: "Track", artist: "Artist", duration_seconds: 180}
    topic = "now-playing-test-#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(NozomiStation.PubSub, topic)

    pid =
      start_supervised!(
        {NowPlaying,
         name: nil,
         topic: topic,
         poll_interval: 60_000,
         current_path: fn -> {:ok, "tmp/media/track.m4a"} end,
         lookup: fn _path -> track end,
         enrich: fn _track ->
           send(test, {:enrichment_pending, self()})

           receive do
             :complete -> {:ok, %{year: 1987, related: ["Related Artist"]}}
           end
         end}
      )

    assert_receive {:enrichment_pending, worker}
    assert_receive {:now_playing, ^track}
    assert NowPlaying.current(pid) == track

    send(worker, :complete)
    assert_receive {:now_playing, enriched}
    assert enriched == Map.merge(track, %{year: 1987, related: ["Related Artist"]})
    assert NowPlaying.current(pid) == enriched
  end

  test "publishes the active database track enriched once" do
    track =
      %Request{}
      |> Request.changeset(%{
        youtube_id: "now-playing",
        title: "Blue Monday",
        artist: "New Order",
        duration_seconds: 451,
        slack_user: "U01",
        slack_channel: "C01",
        thread_ts: "123.45",
        listener_message: "For the night journey",
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
         enrich: fn base ->
           {:ok, Map.merge(base, %{album: "Substance", year: 1987, related: ["Joy Division"]})}
         end}
      )

    assert_receive {:now_playing, base}
    assert base.title == "Blue Monday"
    refute Map.has_key?(base, :year)
    refute Map.has_key?(base, :related)

    assert_receive {:now_playing, now_playing}
    assert now_playing.title == "Blue Monday"
    assert now_playing.artist == "New Order"
    assert now_playing.album == "Substance"
    assert now_playing.year == 1987
    assert now_playing.related == ["Joy Division"]
    assert now_playing.listener_message == "For the night journey"
    assert NowPlaying.current(pid) == now_playing

    send(pid, :poll)
    _ = :sys.get_state(pid)
    refute_receive {:now_playing, _}
  end

  test "discards stale results on track changes and cancels enrichment when playback ends" do
    test = self()
    paths = start_supervised!({Agent, fn -> ["first", "second", nil] end})
    topic = "now-playing-test-#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(NozomiStation.PubSub, topic)

    pid =
      start_supervised!(
        {NowPlaying,
         name: nil,
         topic: topic,
         poll_interval: 60_000,
         current_path: fn ->
           Agent.get_and_update(paths, fn [path | rest] -> {{:ok, path}, rest} end)
         end,
         lookup: fn path -> %{title: path, artist: "Artist"} end,
         enrich: fn track ->
           send(test, {:enrichment_pending, track.title, self()})

           receive do
             :complete -> {:ok, %{year: 1987, related: ["Old Artist"]}}
           end
         end}
      )

    assert_receive {:enrichment_pending, "first", first_worker}
    first_ref = Process.monitor(first_worker)
    assert_receive {:now_playing, %{title: "first"}}

    :ok = :sys.suspend(pid)
    send(pid, :poll)
    send(first_worker, :complete)
    assert_receive {:DOWN, ^first_ref, :process, ^first_worker, :normal}
    :ok = :sys.resume(pid)

    assert_receive {:enrichment_pending, "second", second_worker}
    second_ref = Process.monitor(second_worker)
    assert_receive {:now_playing, %{title: "second"} = second}
    assert second == %{title: "second", artist: "Artist"}
    assert NowPlaying.current(pid) == second

    send(pid, :poll)
    assert_receive {:DOWN, ^second_ref, :process, ^second_worker, :killed}
    assert_receive {:now_playing, nil}
    assert NowPlaying.current(pid) == nil
    refute_receive {:now_playing, _}
  end

  @tag capture_log: true
  test "keeps serving the base track when the enrichment worker exits" do
    test = self()
    track = %{title: "Track", artist: "Artist"}
    topic = "now-playing-test-#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(NozomiStation.PubSub, topic)

    pid =
      start_supervised!(
        {NowPlaying,
         name: nil,
         topic: topic,
         poll_interval: 60_000,
         current_path: fn -> {:ok, "track"} end,
         lookup: fn _path -> track end,
         enrich: fn _track ->
           send(test, {:enrichment_pending, self()})

           receive do
             :fail -> exit(:provider_crashed)
           end
         end}
      )

    assert_receive {:enrichment_pending, worker}
    ref = Process.monitor(worker)
    send(worker, :fail)
    assert_receive {:DOWN, ^ref, :process, ^worker, :provider_crashed}
    assert_receive {:now_playing, ^track}
    assert NowPlaying.current(pid) == track
    refute_receive {:now_playing, _}
  end

  test "stops pending enrichment when the publisher shuts down" do
    test = self()

    start_supervised!(
      {NowPlaying,
       name: nil,
       poll_interval: 60_000,
       current_path: fn -> {:ok, "track"} end,
       lookup: fn _path -> %{title: "Track", artist: "Artist"} end,
       enrich: fn _track ->
         send(test, {:enrichment_pending, self()})

         receive do
           :complete -> {:ok, %{year: 1987}}
         end
       end}
    )

    assert_receive {:enrichment_pending, worker}
    ref = Process.monitor(worker)
    stop_supervised!(NowPlaying)
    assert_receive {:DOWN, ^ref, :process, ^worker, :killed}
  end

  test "clears a finished track without repeating unchanged updates" do
    paths =
      start_supervised!({Agent, fn -> ["tmp/media/track.m4a", "tmp/media/track.m4a", nil] end})

    topic = "now-playing-test-#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(NozomiStation.PubSub, topic)

    current_path = fn ->
      Agent.get_and_update(paths, fn [path | rest] -> {{:ok, path}, rest} end)
    end

    pid =
      start_supervised!(
        {NowPlaying,
         name: nil,
         topic: topic,
         poll_interval: 60_000,
         current_path: current_path,
         lookup: fn _path -> %{title: "Track", artist: "Artist", duration_seconds: 180} end,
         enrich: fn _track -> {:error, :provider_unavailable} end}
      )

    assert_receive {:now_playing, %{title: "Track"}}
    send(pid, :poll)
    _ = :sys.get_state(pid)
    refute_receive {:now_playing, _}

    send(pid, :poll)
    assert_receive {:now_playing, nil}
    assert NowPlaying.current(pid) == nil
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
