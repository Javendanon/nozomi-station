defmodule NozomiStation.Media.YtDlpTest do
  use ExUnit.Case, async: false

  alias NozomiStation.Media.YtDlp

  setup do
    previous = System.get_env("YTDLP_COOKIES_FILE")

    on_exit(fn ->
      if previous,
        do: System.put_env("YTDLP_COOKIES_FILE", previous),
        else: System.delete_env("YTDLP_COOKIES_FILE")
    end)
  end

  test "searches one YouTube result and parses playback metadata" do
    runner = fn "yt-dlp", args ->
      send(self(), {:args, args})

      {Jason.encode!(%{
         "id" => "candidate_123",
         "title" => "Blue Monday",
         "uploader" => "New Order",
         "duration" => 449.2,
         "is_live" => false,
         "live_status" => "not_live"
       }), 0}
    end

    assert {:ok, track} = YtDlp.fetch(:youtube_search, "New Order Blue Monday", runner)
    assert track.youtube_id == "candidate_123"
    assert track.duration == 450
    refute track.live?

    assert_received {:args, args}
    assert "--dump-single-json" in args
    assert "--skip-download" in args
    assert List.last(args) == "ytsearch1:New Order Blue Monday"
  end

  test "uses a configured cookie jar for direct metadata" do
    path = Path.join(System.tmp_dir!(), "nozomi-ytdlp-cookies.txt")
    File.write!(path, "# Netscape HTTP Cookie File\n")
    System.put_env("YTDLP_COOKIES_FILE", path)

    runner = fn "yt-dlp", args ->
      send(self(), {:args, args})

      {Jason.encode!(%{
         "id" => "video_456",
         "title" => "Railway",
         "channel" => "Express",
         "duration" => 240,
         "live_status" => "is_live"
       }), 0}
    end

    assert {:ok, %{live?: true, artist: "Express"}} =
             YtDlp.fetch(:youtube, "video_456", runner)

    assert_received {:args, args}
    assert Enum.chunk_every(args, 2, 1, :discard) |> Enum.any?(&(&1 == ["--cookies", path]))
    assert List.last(args) == "https://www.youtube.com/watch?v=video_456"
  end

  test "rejects command failures and malformed metadata" do
    assert {:error, :provider_unavailable} =
             YtDlp.fetch(:youtube, "missing", fn _, _ -> {"failed", 1} end)

    assert {:error, :provider_unavailable} =
             YtDlp.fetch(:youtube_search, "missing", fn _, _ -> {~s({"id":"only"}), 0} end)
  end
end
