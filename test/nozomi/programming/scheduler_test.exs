defmodule NozomiStation.Programming.SchedulerTest do
  use NozomiStation.DataCase, async: true

  import ExUnit.CaptureLog

  alias NozomiStation.Programming.{
    ComplementaryTrack,
    LiquidsoapClient,
    Scheduler,
    SchedulerWorker
  }

  alias NozomiStation.Repo
  alias NozomiStation.Requests.Request

  test "reconciles a durable receipt after an ACK without pushing again" do
    request = insert_request("ready", "/host/media/accepted.m4a")

    assert {:ok, %{requested: 1, complementary: 0}} =
             Scheduler.run(
               deliver: fn :requested, id, path ->
                 assert id == request.id
                 assert path == request.file_path
                 {:ok, "queued"}
               end
             )

    assert Repo.reload!(request).status == "queued"
  end

  test "dispatches requested tracks before complementary tracks" do
    request = insert_request("ready", "/host/media/request.m4a")
    complementary = insert_complementary("ready", "/host/media/complementary.m4a")

    deliver = fn queue, _id, path ->
      send(self(), {:push, queue, path})
      {:ok, "queued"}
    end

    assert {:ok, %{requested: 1, complementary: 1}} = Scheduler.run(deliver: deliver)

    assert_receive {:push, :requested, "/host/media/request.m4a"}
    assert_receive {:push, :complementary, "/host/media/complementary.m4a"}
    assert Repo.reload!(request).status == "queued"
    assert Repo.reload!(complementary).status == "queued"
  end

  test "requires durable completion receipts instead of absence from a volatile queue" do
    active = insert_request("queued", "/host/media/active.m4a")
    finished = insert_complementary("queued", "/host/media/finished.m4a")
    waiting = insert_complementary("ready", "/host/media/waiting.m4a", 2)

    deliver = fn
      :requested, _, _ -> {:ok, "queued"}
      :complementary, id, _ when id == finished.id -> {:ok, "played"}
      :complementary, _, _ -> {:ok, "queued"}
    end

    assert {:ok, %{requested: 0, complementary: 1}} = Scheduler.run(deliver: deliver)
    assert Repo.reload!(active).status == "queued"
    assert Repo.reload!(finished).status == "played"
    assert Repo.reload!(waiting).status == "queued"
  end

  test "reconciles exactly once when Phoenix fails after ACK and before committing" do
    request = insert_request("ready", "/host/media/ack.m4a")
    receipts = start_supervised!({Agent, fn -> %{} end})

    deliver = fn queue, id, _path ->
      Agent.update(receipts, &Map.put_new(&1, {queue, id}, "queued"))
      {:ok, Agent.get(receipts, &Map.fetch!(&1, {queue, id}))}
    end

    assert {:error, :injected_after_ack} =
             Repo.transaction(fn ->
               assert {:ok, _} = Scheduler.run(deliver: deliver)
               Repo.rollback(:injected_after_ack)
             end)

    assert Repo.reload!(request).status == "ready"
    assert {:ok, %{requested: 1}} = Scheduler.run(deliver: deliver)
    assert Repo.reload!(request).status == "queued"
    assert Agent.get(receipts, &map_size/1) == 1

    Agent.update(receipts, &Map.put(&1, {:requested, request.id}, "played"))
    assert {:ok, %{requested: 0}} = Scheduler.run(deliver: deliver)
    assert Repo.reload!(request).status == "played"
    assert {:ok, %{requested: 0}} = Scheduler.run(deliver: deliver)
  end

  test "lost ACKs and control outages preserve ready and queued requests" do
    ready = insert_request("ready", "/host/media/ready.m4a")
    queued = insert_complementary("queued", "/host/media/queued.m4a")

    assert capture_log(fn ->
             assert {:ok, %{requested: 0, complementary: 0}} =
                      Scheduler.run(deliver: fn _, _, _ -> {:error, :timeout} end)
           end) =~ "programming_dispatch_failed"

    assert Repo.reload!(ready).status == "ready"
    assert Repo.reload!(queued).status == "queued"

    assert {:ok, %{requested: 0, complementary: 0}} =
             Scheduler.run(deliver: fn _, _, _ -> {:ok, "played"} end)

    assert Repo.reload!(ready).status == "played"
    assert Repo.reload!(queued).status == "played"
  end

  test "a permanently failing delivery does not block its siblings" do
    broken = insert_request("ready", "/host/outside/media.m4a")
    healthy = insert_request("ready", "/host/media/healthy.m4a")

    assert capture_log(fn ->
             assert {:ok, %{requested: 1}} =
                      Scheduler.run(
                        deliver: fn
                          :requested, id, _path when id == broken.id ->
                            {:error, :invalid_media_path}

                          :requested, id, _path when id == healthy.id ->
                            {:ok, "queued"}
                        end
                      )
           end) =~ "programming_dispatch_failed"

    assert Repo.reload!(broken).status == "ready"
    assert Repo.reload!(healthy).status == "queued"
  end

  test "a failed receipt keeps the row retryable until the media is available" do
    request = insert_request("ready", "/host/media/late.m4a")

    assert {:ok, %{requested: 0}} =
             Scheduler.run(deliver: fn _, _, _ -> {:ok, "failed"} end)

    assert Repo.reload!(request).status == "ready"

    assert {:ok, %{requested: 1}} =
             Scheduler.run(deliver: fn _, _, _ -> {:ok, "queued"} end)

    assert Repo.reload!(request).status == "queued"
  end

  test "a restarted poller reconciles immediately without provider I/O" do
    test = self()

    options = [
      name: nil,
      run: fn ->
        send(test, :reconciled)
        {:ok, %{}}
      end
    ]

    start_supervised!({Scheduler, options})
    assert_receive :reconciled
    stop_supervised!(Scheduler)
    start_supervised!({Scheduler, options})
    assert_receive :reconciled
  end

  test "database disconnects roll back dispatch and remain retryable" do
    request = insert_request("ready", "/host/media/disconnect.m4a")

    assert {:error, :database_unavailable} =
             Scheduler.run(deliver: fn _, _, _ -> raise DBConnection.ConnectionError end)

    assert Repo.reload!(request).status == "ready"
  end

  test "non-availability database errors surface instead of being retried as outages" do
    insert_request("ready", "/host/media/bad-sql.m4a")

    assert_raise Postgrex.Error, fn ->
      Scheduler.run(deliver: fn _, _, _ -> raise Postgrex.Error, message: "syntax error" end)
    end
  end

  test "the supervised poller keeps retrying after control outages" do
    test = self()

    pid =
      start_supervised!(
        {Scheduler,
         name: nil,
         poll: false,
         run: fn ->
           send(test, :attempted)
           {:error, :timeout}
         end}
      )

    send(pid, :poll)
    assert_receive :attempted
    _ = :sys.get_state(pid)
    send(pid, :poll)
    assert_receive :attempted
  end

  test "scheduler worker preserves success and retry results" do
    assert {:ok, %{requested: 1}} =
             SchedulerWorker.run(fn -> {:ok, %{requested: 1}} end)

    assert {:error, :control_unavailable} =
             SchedulerWorker.run(fn -> {:error, :control_unavailable} end)

    assert "programming" == Ecto.Changeset.get_change(SchedulerWorker.new(%{}), :queue)
  end

  test "maps media paths into allowlisted Liquidsoap commands" do
    command = fn value ->
      send(self(), {:command, value})
      {:ok, ["17"]}
    end

    assert :ok =
             LiquidsoapClient.push(
               :requested,
               "/host/media/17.m4a",
               command,
               media_dir: "/host/media",
               liquidsoap_media_dir: "/media"
             )

    assert_received {:command, "requested.push /media/17.m4a"}

    assert {:error, :invalid_media_path} =
             LiquidsoapClient.push(
               :requested,
               "/host/secret",
               command,
               media_dir: "/host/media",
               liquidsoap_media_dir: "/media"
             )

    refute_received {:command, "requested.push /host/secret"}

    assert {:error, :invalid_media_path} =
             LiquidsoapClient.push(:requested, "/host/media/17.m4a\nrequested.skip", command,
               media_dir: "/host/media",
               liquidsoap_media_dir: "/media"
             )

    assert {:error, :invalid_control_response} =
             LiquidsoapClient.push(:requested, "/host/media/empty.m4a", fn _ -> {:ok, []} end,
               media_dir: "/host/media",
               liquidsoap_media_dir: "/media"
             )
  end

  test "allows a configured media root with spaces and validates only the relative segment" do
    assert {:ok, "queued"} =
             LiquidsoapClient.deliver(
               :requested,
               17,
               "/mnt/audio store/17.m4a",
               fn "radio.enqueue requested-17 requested /media/17.m4a" ->
                 {:ok, [~s({"key":"requested-17","state":"queued","position":0})]}
               end,
               media_dir: "/mnt/audio store",
               liquidsoap_media_dir: "/media"
             )

    assert {:error, :invalid_media_path} =
             LiquidsoapClient.deliver(
               :requested,
               17,
               "/mnt/audio store/track one.m4a",
               fn _ -> flunk("unsafe path reached control socket") end,
               media_dir: "/mnt/audio store",
               liquidsoap_media_dir: "/media"
             )
  end

  test "does not resurrect a row changed by another writer during delivery" do
    track = insert_complementary("ready", "/host/media/skipped.m4a")

    assert {:ok, %{complementary: 0}} =
             Scheduler.run(
               deliver: fn :complementary, _id, _path ->
                 track |> Ecto.Changeset.change(status: "skipped") |> Repo.update!()
                 {:ok, "queued"}
               end
             )

    assert Repo.reload!(track).status == "skipped"
  end

  defp insert_request(status, path) do
    attrs = %{
      youtube_id: "request-#{System.unique_integer([:positive])}",
      title: "Request",
      artist: "Artist",
      duration_seconds: 180,
      slack_user: "U01",
      slack_channel: "C01",
      thread_ts: "1",
      status: status,
      file_path: path
    }

    %Request{} |> Request.changeset(attrs) |> Repo.insert!()
  end

  defp insert_complementary(status, path, suffix \\ 1) do
    attrs = %{
      youtube_id: "complementary-#{suffix}-#{System.unique_integer([:positive])}",
      title: "Complementary",
      artist: "Artist",
      duration_seconds: 180,
      origin: "seed",
      status: status,
      file_path: path
    }

    %ComplementaryTrack{} |> ComplementaryTrack.changeset(attrs) |> Repo.insert!()
  end
end
