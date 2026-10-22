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
        "text" =>
          "Hola, les comparto estas canciones: https://youtu.be/one https://open.spotify.com/track/two"
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

    display_name = fn user ->
      send(self(), {:display_name, user})
      {:ok, "Listener"}
    end

    deps = [
      channel: "C01",
      resolver: resolver,
      prepare: prepare,
      reply: reply,
      display_name: display_name
    ]

    previous_level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous_level) end)
    log = capture_log([level: :info], fn -> assert :ok = RequestWorker.perform(job, deps) end)

    assert log =~ "request_ready"
    assert log =~ "position=1"
    assert_received {:resolved, "https://youtu.be/one"}
    assert_received {:resolved, "https://open.spotify.com/track/two"}

    requester = %{
      slack_user: "U01",
      slack_display_name: "Listener",
      slack_channel: "C01",
      thread_ts: "123.45",
      listener_message: "Hola, les comparto estas canciones:"
    }

    assert_received {:display_name, "U01"}
    refute_received {:display_name, _}

    assert_received {:prepared, "one", ^requester}
    assert_received {:prepared, "two", ^requester}

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
      reply: fn _, _, _ -> flunk("transient resolver result reached Slack") end,
      display_name: fn _user -> {:error, :slack_unavailable} end
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
      reply: fn _, _, _ -> flunk("ignored event reached Slack") end,
      display_name: fn _ -> flunk("ignored event reached the Slack lookup") end
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
        "text" => "<https://youtu.be/live> <https://youtu.be/ready>.."
      }
    }

    assert {:ok, _event} = EventStore.insert(payload)

    resolver = fn
      "https://youtu.be/live" ->
        {:error, :not_playable}

      "https://youtu.be/ready" ->
        {:ok, %{youtube_id: "ready", title: "Ready", artist: "Nozomi", duration_seconds: 120}}
    end

    prepare = fn track, requester ->
      send(self(), {:requester, requester})
      {:ok, %{title: track.title}, 1}
    end

    reply = fn channel, thread_ts, text ->
      send(self(), {:reply, channel, thread_ts, text})
      :ok
    end

    job = %Oban.Job{args: %{"event_id" => "Ev-rejection"}}

    deps = [
      channel: "C01",
      resolver: resolver,
      prepare: prepare,
      reply: reply,
      display_name: fn _user -> {:error, :display_name_missing} end
    ]

    assert :ok = RequestWorker.perform(job, deps)
    assert_received {:reply, "C01", "456.78", "Rechazada: la canción no es reproducible"}
    assert_received {:reply, "C01", "456.78", "Aceptada: Ready · posición 1"}

    # A failed lookup keeps the request but never promotes the Slack ID to a public name.
    assert_received {:requester,
                     %{listener_message: nil, slack_user: "U01", slack_display_name: nil}}
  end

  test "resolves the visible name through Slack and tolerates a failed lookup" do
    request = fn options ->
      send(self(), {:slack_request, options})

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "ok" => true,
           "user" => %{"id" => "U01", "profile" => %{"display_name" => " Kaede "}}
         }
       }}
    end

    assert {:ok, "Kaede"} = Client.display_name("U01", request)
    assert_receive {:slack_request, options}
    assert options[:url] == "https://slack.com/api/users.info"
    assert options[:method] == :get
    assert options[:params] == [user: "U01"]
    assert options[:redirect] == false

    real_name = fn _options ->
      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "ok" => true,
           "user" => %{
             "id" => "U01",
             "profile" => %{"display_name" => "", "real_name" => "Kaede Hoshino"}
           }
         }
       }}
    end

    assert {:ok, "Kaede Hoshino"} = Client.display_name("U01", real_name)

    anonymous = fn _options ->
      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "ok" => true,
           "user" => %{"id" => "U01", "profile" => %{"display_name" => " "}}
         }
       }}
    end

    assert {:error, :display_name_missing} = Client.display_name("U01", anonymous)

    assert {:error, :slack_unavailable} =
             Client.display_name("U01", fn _options ->
               {:ok, %Req.Response{status: 500, body: %{"ok" => false}}}
             end)

    assert {:error, :slack_unavailable} =
             Client.display_name("U01", fn _options -> {:error, :timeout} end)

    assert {:error, :invalid_user} = Client.display_name(nil, request)
  end
end
