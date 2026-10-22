defmodule NozomiStation.Requests.RequestFlowTest do
  use NozomiStation.DataCase, async: true

  alias NozomiStation.Requests.{Request, RequestFlow}

  test "prepares one safe FIFO request and rejects an active duplicate" do
    track = %{
      youtube_id: "video_123",
      title: "Night Train",
      artist: "Nozomi",
      duration_seconds: 200
    }

    runner = &successful_runner/2

    requester = %{
      slack_user: "U01",
      slack_channel: "C01",
      thread_ts: "123.45",
      listener_message: "Esta canción me gusta"
    }

    assert {:ok, request, 1} = RequestFlow.prepare(track, requester, runner)
    assert request.status == "ready"
    assert request.listener_message == "Esta canción me gusta"
    assert File.read!(request.file_path) == "prepared"

    assert_received {:yt_dlp, args}
    assert List.last(args) == "https://www.youtube.com/watch?v=video_123"
    assert "--no-playlist" in args

    assert {:error, :duplicate} = RequestFlow.prepare(track, requester, runner)

    request |> Request.changeset(%{status: "queued"}) |> Repo.update!()
    assert {:error, :duplicate} = RequestFlow.prepare(track, requester, runner)
  end

  test "releases the duplicate guard after preparation fails" do
    track = %{
      youtube_id: "retry_456",
      title: "Retry Express",
      artist: "Nozomi",
      duration_seconds: 180
    }

    requester = %{slack_user: "U02", slack_channel: "C01", thread_ts: "234.56"}
    failed_runner = fn "yt-dlp", _args -> {"failed", 1} end

    assert {:error, :preparation_failed} = RequestFlow.prepare(track, requester, failed_runner)

    assert {:ok, request, 1} = RequestFlow.prepare(track, requester, &successful_runner/2)
    assert request.status == "ready"
  end

  test "returns validation errors for incomplete request metadata" do
    requester = %{slack_user: "U01", slack_channel: "C01", thread_ts: "345.00"}

    assert {:error, changeset} =
             RequestFlow.prepare(%{youtube_id: "incomplete"}, requester, fn _, _ -> {"", 1} end)

    refute changeset.valid?
  end

  test "does not queue a downloader success without an output file" do
    track = %{
      youtube_id: "missing_file",
      title: "Missing",
      artist: "Nozomi",
      duration_seconds: 120
    }

    requester = %{slack_user: "U01", slack_channel: "C01", thread_ts: "345.67"}

    assert {:error, :preparation_failed} =
             RequestFlow.prepare(track, requester, fn "yt-dlp", _args -> {"", 0} end)
  end

  test "rejects the last ten played tracks but permits the older one" do
    for number <- 1..11 do
      Repo.insert!(
        Request.changeset(%Request{}, %{
          youtube_id: "played_#{number}",
          title: "Track #{number}",
          artist: "Nozomi",
          duration_seconds: 120,
          slack_user: "U01",
          slack_channel: "C01",
          thread_ts: Integer.to_string(number),
          status: "played"
        })
      )
    end

    requester = %{slack_user: "U02", slack_channel: "C01", thread_ts: "999"}

    runner = &successful_runner/2

    assert {:error, :duplicate} =
             RequestFlow.prepare(
               %{
                 youtube_id: "played_11",
                 title: "Recent",
                 artist: "Nozomi",
                 duration_seconds: 120
               },
               requester,
               runner
             )

    assert {:ok, request, 1} =
             RequestFlow.prepare(
               %{youtube_id: "played_1", title: "Old", artist: "Nozomi", duration_seconds: 120},
               requester,
               runner
             )

    assert request.status == "ready"
  end

  defp successful_runner("yt-dlp", args) do
    send(self(), {:yt_dlp, args})
    output = Enum.at(args, Enum.find_index(args, &(&1 == "--output")) + 1)
    path = String.replace(output, ".%(ext)s", ".m4a")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "prepared")
    {"", 0}
  end
end
