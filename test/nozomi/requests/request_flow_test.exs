defmodule NozomiStation.Requests.RequestFlowTest do
  use NozomiStation.DataCase, async: true

  alias NozomiStation.Requests.RequestFlow

  test "prepares one safe FIFO request and rejects an active duplicate" do
    track = %{
      youtube_id: "video_123",
      title: "Night Train",
      artist: "Nozomi",
      duration_seconds: 200
    }

    runner = fn "yt-dlp", args ->
      send(self(), {:yt_dlp, args})
      output = Enum.at(args, Enum.find_index(args, &(&1 == "--output")) + 1)
      path = String.replace(output, ".%(ext)s", ".m4a")
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "prepared")
      {"", 0}
    end

    requester = %{slack_user: "U01", slack_channel: "C01", thread_ts: "123.45"}

    assert {:ok, request, 1} = RequestFlow.prepare(track, requester, runner)
    assert request.status == "ready"
    assert File.read!(request.file_path) == "prepared"

    assert_received {:yt_dlp, args}
    assert List.last(args) == "https://www.youtube.com/watch?v=video_123"
    assert "--no-playlist" in args

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

    successful_runner = fn "yt-dlp", args ->
      output = Enum.at(args, Enum.find_index(args, &(&1 == "--output")) + 1)
      path = String.replace(output, ".%(ext)s", ".m4a")
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "prepared")
      {"", 0}
    end

    assert {:ok, request, 1} = RequestFlow.prepare(track, requester, successful_runner)
    assert request.status == "ready"
  end
end
