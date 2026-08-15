defmodule NozomiStation.Programming.SchedulerTest do
  use NozomiStation.DataCase, async: true

  alias NozomiStation.Programming.{
    ComplementaryTrack,
    LiquidsoapClient,
    Scheduler,
    SchedulerWorker
  }

  alias NozomiStation.Repo
  alias NozomiStation.Requests.Request

  test "dispatches requested tracks before complementary tracks" do
    request = insert_request("ready", "/host/media/request.m4a")
    complementary = insert_complementary("ready", "/host/media/complementary.m4a")

    push = fn queue, path ->
      send(self(), {:push, queue, path})
      :ok
    end

    assert {:ok, %{requested: 1, complementary: 1}} =
             Scheduler.run(active_paths: fn -> {:ok, []} end, push: push)

    assert_receive {:push, :requested, "/host/media/request.m4a"}
    assert_receive {:push, :complementary, "/host/media/complementary.m4a"}
    assert Repo.reload!(request).status == "queued"
    assert Repo.reload!(complementary).status == "queued"
  end

  test "reconciles completed tracks and keeps failed dispatches ready" do
    active = insert_request("queued", "/host/media/active.m4a")
    finished = insert_complementary("queued", "/host/media/finished.m4a")
    waiting = insert_complementary("ready", "/host/media/waiting.m4a", 2)

    assert {:ok, %{requested: 0, complementary: 0}} =
             Scheduler.run(
               active_paths: fn -> {:ok, [active.file_path]} end,
               push: fn :complementary, _path -> {:error, :control_unavailable} end
             )

    assert Repo.reload!(active).status == "queued"
    assert Repo.reload!(finished).status == "played"
    assert Repo.reload!(waiting).status == "ready"
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

  test "reads active request filenames from Liquidsoap metadata" do
    command = fn
      "request.all" -> {:ok, ["4 9"]}
      "request.metadata 4" -> {:ok, [~s(filename="/media/4.m4a"), ~s(status="ready")]}
      "request.metadata 9" -> {:ok, [~s(initial_uri="/media/c9.m4a"), ~s(status="idle")]}
    end

    assert {:ok, ["/host/media/4.m4a", "/host/media/c9.m4a"]} =
             LiquidsoapClient.active_paths(command,
               media_dir: "/host/media",
               liquidsoap_media_dir: "/media"
             )
  end

  test "ignores requests that finish during control reconciliation" do
    command = fn
      "request.all" -> {:ok, ["4"]}
      "request.metadata 4" -> {:ok, ["No such request."]}
    end

    assert {:ok, []} = LiquidsoapClient.active_paths(command, [])
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
