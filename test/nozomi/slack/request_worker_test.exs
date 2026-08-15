defmodule NozomiStation.Slack.RequestWorkerTest do
  use NozomiStation.DataCase, async: false

  import ExUnit.CaptureLog

  alias NozomiStation.Slack.{Client, EventStore, RequestWorker}

  test "posts thread replies only to Slack's fixed API host" do
    request = fn options ->
      send(self(), {:slack_request, options})
      {:ok, %Req.Response{status: 200, body: %{"ok" => true}}}
    end

    assert :ok = Client.reply("C01", "123.45", "Aceptada", request)
    assert_receive {:slack_request, options}
    assert options[:url] == "https://slack.com/api/chat.postMessage"
    assert options[:redirect] == false
    assert options[:json] == %{channel: "C01", thread_ts: "123.45", text: "Aceptada"}

    assert {:error, :slack_unavailable} =
             Client.reply("C01", "123.45", "Aceptada", fn _options ->
               {:ok, %Req.Response{status: 500, body: %{}}}
             end)
  end

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

    previous_level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous_level) end)
    log = capture_log([level: :info], fn -> assert :ok = RequestWorker.perform(job, deps) end)

    assert log =~ "request_ready"
    assert log =~ "position=1"
    assert_received {:resolved, "https://youtu.be/one"}
    assert_received {:resolved, "https://open.spotify.com/track/two"}

    assert_received {:prepared, "one",
                     %{slack_user: "U01", slack_channel: "C01", thread_ts: "123.45"}}

    assert_received {:reply, "C01", "123.45", "Aceptada: one · posición 1"}
    assert_received {:reply, "C01", "123.45", "Aceptada: two · posición 2"}
  end

  test "discards a job whose persisted event is missing" do
    job = %Oban.Job{args: %{"event_id" => "missing"}}
    assert {:discard, :event_not_found} = RequestWorker.perform(job, [])
  end

  test "returns transient provider failures for Oban to retry" do
    payload = %{
      "event_id" => "Ev-transient",
      "event" => %{
        "type" => "message",
        "channel" => "C01",
        "user" => "U01",
        "ts" => "400.00",
        "text" => "https://youtu.be/retry"
      }
    }

    assert {:ok, _event} = EventStore.insert(payload)

    deps = [
      channel: "C01",
      resolver: fn _url -> {:error, :provider_unavailable} end,
      prepare: fn _, _ -> flunk("transient resolver result reached preparation") end,
      reply: fn _, _, _ -> flunk("transient resolver result reached Slack") end
    ]

    job = %Oban.Job{args: %{"event_id" => "Ev-transient"}}
    assert {:error, :provider_unavailable} = RequestWorker.perform(job, deps)
  end

  test "ignores messages outside the configured channel" do
    payload = %{
      "event_id" => "Ev-other-channel",
      "event" => %{"type" => "message", "channel" => "C02", "text" => nil}
    }

    assert {:ok, _event} = EventStore.insert(payload)

    deps = [
      channel: "C01",
      resolver: fn _ -> flunk("ignored event reached resolver") end,
      prepare: fn _, _ -> flunk("ignored event reached preparation") end,
      reply: fn _, _, _ -> flunk("ignored event reached Slack") end
    ]

    job = %Oban.Job{args: %{"event_id" => "Ev-other-channel"}}
    assert :ok = RequestWorker.perform(job, deps)
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
