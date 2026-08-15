defmodule NozomiStation.Slack.RequestWorkerTest do
  use NozomiStation.DataCase, async: true

  alias NozomiStation.Slack.{EventStore, RequestWorker}

  test "processes message links in order and confirms each request in its thread" do
    payload = %{
      "event_id" => "Ev-worker",
      "event" => %{
        "type" => "message",
        "channel" => "C01",
        "user" => "U01",
        "ts" => "123.45",
        "text" => "first https://youtu.be/one then https://open.spotify.com/track/two"
      }
    }

    assert {:ok, _event} = EventStore.insert(payload)

    resolver = fn url ->
      send(self(), {:resolved, url})

      {:ok,
       %{
         youtube_id: Path.basename(url),
         title: Path.basename(url),
         artist: "Nozomi",
         duration_seconds: 180
       }}
    end

    prepare = fn track, requester ->
      send(self(), {:prepared, track.title, requester})
      {:ok, %{title: track.title}, if(track.title == "one", do: 1, else: 2)}
    end

    reply = fn channel, thread_ts, text ->
      send(self(), {:reply, channel, thread_ts, text})
      :ok
    end

    job = %Oban.Job{args: %{"event_id" => "Ev-worker"}}
    deps = [channel: "C01", resolver: resolver, prepare: prepare, reply: reply]

    assert :ok = RequestWorker.perform(job, deps)

    assert_received {:resolved, "https://youtu.be/one"}
    assert_received {:resolved, "https://open.spotify.com/track/two"}

    assert_received {:prepared, "one",
                     %{slack_user: "U01", slack_channel: "C01", thread_ts: "123.45"}}

    assert_received {:reply, "C01", "123.45", "Aceptada: one · posición 1"}
    assert_received {:reply, "C01", "123.45", "Aceptada: two · posición 2"}
  end

  test "reports a permanent rejection and continues with later links" do
    payload = %{
      "event_id" => "Ev-rejection",
      "event" => %{
        "type" => "message",
        "channel" => "C01",
        "user" => "U01",
        "ts" => "456.78",
        "text" => "https://youtu.be/live https://youtu.be/ready"
      }
    }

    assert {:ok, _event} = EventStore.insert(payload)

    resolver = fn
      "https://youtu.be/live" ->
        {:error, :not_playable}

      "https://youtu.be/ready" ->
        {:ok, %{youtube_id: "ready", title: "Ready", artist: "Nozomi", duration_seconds: 120}}
    end

    prepare = fn track, _requester -> {:ok, %{title: track.title}, 1} end

    reply = fn channel, thread_ts, text ->
      send(self(), {:reply, channel, thread_ts, text})
      :ok
    end

    job = %Oban.Job{args: %{"event_id" => "Ev-rejection"}}
    deps = [channel: "C01", resolver: resolver, prepare: prepare, reply: reply]

    assert :ok = RequestWorker.perform(job, deps)
    assert_received {:reply, "C01", "456.78", "Rechazada: la canción no es reproducible"}
    assert_received {:reply, "C01", "456.78", "Aceptada: Ready · posición 1"}
  end
end
