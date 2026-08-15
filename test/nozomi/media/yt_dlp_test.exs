defmodule NozomiStation.Media.YtDlpTest do
  use ExUnit.Case, async: false

  alias NozomiStation.Media.{Preparer, Resolver, YtDlp}

  setup do
    previous_env = System.get_env("YTDLP_COOKIES_FILE")
    previous_config = Application.get_env(:nozomi_station, :ytdlp_cookies_file)

    on_exit(fn ->
      if previous_env,
        do: System.put_env("YTDLP_COOKIES_FILE", previous_env),
        else: System.delete_env("YTDLP_COOKIES_FILE")

      if previous_config,
        do: Application.put_env(:nozomi_station, :ytdlp_cookies_file, previous_config),
        else: Application.delete_env(:nozomi_station, :ytdlp_cookies_file)
    end)
  end

  test "searches one YouTube result and parses playback metadata" do
    runner = fn "yt-dlp", args ->
      send(self(), {:args, args})

      {Jason.encode!(%{
         "entries" => [
           %{
             "id" => "candidate_123",
             "title" => "Blue Monday",
             "uploader" => "New Order",
             "duration" => 449.2,
             "is_live" => false,
             "live_status" => "not_live"
           }
         ]
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
    Application.put_env(:nozomi_station, :ytdlp_cookies_file, path)

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

  test "uses the same cookie jar while preparing audio" do
    path = Path.join(System.tmp_dir!(), "nozomi-ytdlp-download-cookies.txt")
    File.write!(path, "# Netscape HTTP Cookie File\n")
    System.put_env("YTDLP_COOKIES_FILE", path)

    runner = fn "yt-dlp", args ->
      send(self(), {:args, args})
      output = Enum.at(args, Enum.find_index(args, &(&1 == "--output")) + 1)
      prepared = String.replace(output, ".%(ext)s", ".m4a")
      File.mkdir_p!(Path.dirname(prepared))
      File.write!(prepared, "audio")
      {"", 0}
    end

    assert {:ok, _prepared} = Preparer.prepare("video_789", {:complementary, 789}, runner)
    assert_received {:args, ["--cookies", ^path | _]}
  end

  test "resolves yt-dlp search metadata without a second provider call" do
    track = %{
      youtube_id: "search_1",
      title: "Search result",
      artist: "Artist",
      duration: 180,
      live?: false
    }

    fetch = fn
      :youtube_search, "Artist Search result" -> {:ok, track}
      :youtube, _value -> flunk("search metadata triggered a second yt-dlp call")
    end

    assert {:ok, %{youtube_id: "search_1", duration_seconds: 180}} =
             Resolver.resolve_search("Artist Search result", fetch)
  end

  test "accepts integer yt-dlp durations through the resolver" do
    fetch = fn :youtube, "integer_1" ->
      {:ok,
       %{
         youtube_id: "integer_1",
         title: "Integer duration",
         artist: "Artist",
         duration: 120,
         live?: false
       }}
    end

    assert {:ok, %{duration_seconds: 120}} = Resolver.resolve("https://youtu.be/integer_1", fetch)
  end

  test "rejects command failures and malformed metadata without network calls" do
    assert {:error, :provider_unavailable} =
             YtDlp.fetch(:youtube, "missing", fn _, _ -> {"failed", 1} end)

    assert {:error, :provider_unavailable} =
             YtDlp.fetch(:youtube_search, "missing", fn _, _ -> {~s({"id":"only"}), 0} end)

    invalid_duration = ~s({"id":"id","title":"Title","uploader":"Artist"})

    assert {:error, :provider_unavailable} =
             YtDlp.fetch(:youtube, "missing", fn _, _ -> {invalid_duration, 0} end)

    refute_runner = fn _, _ -> flunk("invalid input reached yt-dlp") end
    assert {:error, :provider_unavailable} = YtDlp.fetch(:youtube, "invalid&id", refute_runner)
    assert {:error, :provider_unavailable} = YtDlp.fetch(:youtube_search, " ", refute_runner)
  end
end
