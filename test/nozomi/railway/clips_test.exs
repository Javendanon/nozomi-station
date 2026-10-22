defmodule NozomiStation.Railway.ClipsTest do
  use ExUnit.Case, async: true

  alias NozomiStation.Railway.Clips

  setup do
    dir = Path.join(System.tmp_dir!(), "nozomi-clips-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "loads the bundled catalog with every clip still pending" do
    assert {:ok, %{version: 1, clips: clips}} = Clips.load_catalog()
    assert length(clips) == 3
    assert Enum.all?(clips, &(&1.status == "pending"))
    assert Enum.map(clips, & &1.kind) |> Enum.sort() == ~w(ambience announcement melody)
  end

  test "verifies only available clips" do
    catalog = %{
      version: 1,
      clips: [
        %{
          id: "pending-clip",
          kind: "melody",
          origin: "test",
          duration_seconds: nil,
          file: "pending-clip.m4a",
          status: "pending"
        }
      ]
    }

    assert {:ok, []} = Clips.verify_catalog(catalog, catalog_path(), runner: passing_runner())
    assert {:ok, []} = Clips.verify_catalog(%{version: 1, clips: []})
  end

  test "fails catalog verification for an unavailable file", %{dir: dir} do
    clip = %{
      id: "missing",
      kind: "melody",
      origin: "test fixture",
      duration_seconds: 2,
      file: "missing.m4a",
      status: "available"
    }

    assert {:error, {"missing", :missing_file}} =
             Clips.verify_catalog(
               %{version: 1, clips: [clip]},
               Path.join(dir, "catalog.json"),
               runner: passing_runner()
             )
  end

  test "verifies a normalized clip and reports its duration and peak", %{dir: dir} do
    path = Path.join(dir, "melody.m4a")
    File.write!(path, "audio")

    clip = %{
      id: "melody",
      kind: "melody",
      origin: "test fixture",
      duration_seconds: 2,
      file: "melody.m4a",
      status: "available"
    }

    assert {:ok, metadata} =
             Clips.verify_clip(clip, Path.join(dir, "catalog.json"), runner: passing_runner())

    assert metadata.duration_seconds == 2.0
    assert metadata.peak_db == -2.0
    assert metadata.codec == "aac"
  end

  test "rejects a clip that ffmpeg cannot decode", %{dir: dir} do
    path = Path.join(dir, "broken.m4a")
    File.write!(path, "not audio")

    runner = fn
      "ffmpeg", _args -> {"Invalid data found when processing input", 1}
      "ffprobe", _args -> flunk("metadata probe reached an undecodable clip")
    end

    assert {:error, :undecodable} = Clips.verify_file(path, runner: runner)
  end

  test "rejects clipped levels above the peak ceiling", %{dir: dir} do
    path = Path.join(dir, "clipped.m4a")
    File.write!(path, "audio")

    assert {:error, {:peak_too_high, peak}} =
             Clips.verify_file(path, runner: passing_runner("0.0"))

    assert peak > -1.0
  end

  test "rejects clips that were never normalized to the target stream", %{dir: dir} do
    path = Path.join(dir, "source.m4a")
    File.write!(path, "audio")

    runner = fn
      "ffmpeg", args ->
        if "volumedetect" in args, do: {"max_volume: -2.0 dB", 0}, else: {"", 0}

      "ffprobe", _args ->
        {Jason.encode!(%{
           "streams" => [%{"codec_name" => "mp3", "sample_rate" => "44100", "channels" => 3}],
           "format" => %{"duration" => "2.0"}
         }), 0}
    end

    assert {:error, {:unsupported_codec, "mp3"}} = Clips.verify_file(path, runner: runner)
  end

  test "rejects invalid levels and malformed metadata" do
    runner = fn
      "ffmpeg", _args -> {"no volume report", 0}
      "ffprobe", _args -> {stream_json("aac", "48000", 2), 0}
    end

    assert {:error, :invalid_levels} =
             Clips.verify_file(available_path(), runner: runner)

    bad_duration = fn
      "ffmpeg", args ->
        if "volumedetect" in args, do: {"max_volume: -2.0 dB", 0}, else: {"", 0}

      "ffprobe", _args ->
        {Jason.encode!(%{
           "streams" => [%{"codec_name" => "aac", "sample_rate" => "48000", "channels" => 2}],
           "format" => %{"duration" => "unknown"}
         }), 0}
    end

    assert {:error, :invalid_metadata} =
             Clips.verify_file(available_path(), runner: bad_duration)
  end

  test "accepts numeric durations and rejects malformed stream fields" do
    integer_duration = fn
      "ffmpeg", args ->
        if "volumedetect" in args, do: {"max_volume: -2.0 dB", 0}, else: {"", 0}

      "ffprobe", _args ->
        {Jason.encode!(%{
           "streams" => [%{"codec_name" => "aac", "sample_rate" => "48000", "channels" => 2}],
           "format" => %{"duration" => 2}
         }), 0}
    end

    assert {:ok, %{duration_seconds: 2.0}} =
             Clips.verify_file(available_path(), runner: integer_duration)

    bad_sample_rate = fn
      "ffmpeg", args ->
        if "volumedetect" in args, do: {"max_volume: -2.0 dB", 0}, else: {"", 0}

      "ffprobe", _args ->
        {stream_json("aac", "fast", 2), 0}
    end

    assert {:error, :invalid_metadata} =
             Clips.verify_file(available_path(), runner: bad_sample_rate)
  end

  test "rejects missing sources and non-m4a destinations", %{dir: dir} do
    source = Path.join(dir, "source.wav")
    File.write!(source, "source")

    assert {:error, :missing_file} = Clips.prepare(Path.join(dir, "absent.wav"), "tmp/clip.m4a")

    assert {:error, :invalid_destination} =
             Clips.prepare(source, Path.join(dir, "clip.wav"), runner: passing_runner())
  end

  test "normalizes a source file and verifies the output", %{dir: dir} do
    source = Path.join(dir, "source.wav")
    destination = Path.join(dir, "prepared.m4a")
    File.write!(source, "source")
    File.write!(destination, "previous clip")
    test = self()
    normalize = normalizing_runner()

    runner = fn command, args ->
      if "-b:a" in args do
        send(test, {:normalize_args, args})
        assert File.read!(destination) == "previous clip"
      end

      normalize.(command, args)
    end

    assert {:ok, %{peak_db: -1.5} = metadata} =
             Clips.prepare(source, destination, runner: runner)

    assert File.read!(destination) == "normalized"
    assert File.read!(source) == "source"
    assert Enum.sort(File.ls!(dir)) == ["prepared.m4a", "source.wav"]
    assert_received {:normalize_args, args}
    assert List.last(args) != destination
    assert "loudnorm=I=-16:TP=-1.5:LRA=11" in args
    assert "48000" in args
    assert "192k" in args
    assert metadata.duration_seconds == 2.0
  end

  test "reloads measured metadata as an available catalog entry", %{dir: dir} do
    source = Path.join(dir, "source.wav")
    destination = Path.join(dir, "prepared.m4a")
    File.write!(source, "source")
    runner = normalizing_runner()
    assert {:ok, metadata} = Clips.prepare(source, destination, runner: runner)

    assert {:ok, catalog} =
             load_catalog(dir, [clip("prepared", duration_seconds: metadata.duration_seconds)])

    assert [%{duration_seconds: 2.0}] = catalog.clips

    assert {:ok, [%{id: "prepared", duration_seconds: 2.0}]} =
             Clips.verify_catalog(catalog, Path.join(dir, "catalog.json"), runner: runner)
  end

  test "deletes a prepared file that fails verification", %{dir: dir} do
    source = Path.join(dir, "source.wav")
    destination = Path.join(dir, "prepared.m4a")
    File.write!(source, "source")

    assert {:error, {:peak_too_high, peak}} =
             Clips.prepare(source, destination, runner: normalizing_runner("0.0"))

    assert peak > -1.0
    refute File.exists?(destination)
    assert File.ls!(dir) == ["source.wav"]
  end

  test "preserves existing files when normalization fails or ffmpeg is unavailable", %{dir: dir} do
    source = Path.join(dir, "source.wav")
    destination = Path.join(dir, "prepared.m4a")
    File.write!(source, "source")

    for status <- [1, 127] do
      File.write!(destination, "previous clip")

      runner = fn "ffmpeg", args ->
        if status == 1, do: File.write!(List.last(args), "partial output")
        {"normalization failed", status}
      end

      assert {:error, :normalization_failed} = Clips.prepare(source, destination, runner: runner)
      assert File.read!(source) == "source"
      assert File.read!(destination) == "previous clip"
      assert Enum.sort(File.ls!(dir)) == ["prepared.m4a", "source.wav"]
    end
  end

  test "preserves the destination when output verification fails", %{dir: dir} do
    source = Path.join(dir, "source.wav")
    destination = Path.join(dir, "prepared.m4a")
    File.write!(source, "source")
    File.write!(destination, "previous clip")

    assert {:error, {:peak_too_high, _peak}} =
             Clips.prepare(source, destination, runner: normalizing_runner("0.0"))

    assert File.read!(source) == "source"
    assert File.read!(destination) == "previous clip"
    assert Enum.sort(File.ls!(dir)) == ["prepared.m4a", "source.wav"]
  end

  test "rejects source and destination aliases without invoking ffmpeg", %{dir: dir} do
    source = Path.join(dir, "source.m4a")
    symlink = Path.join(dir, "symlink.m4a")
    hardlink = Path.join(dir, "hardlink.m4a")
    File.write!(source, "source")
    File.ln_s!(source, symlink)
    File.ln!(source, hardlink)
    runner = fn _, _ -> flunk("ffmpeg reached an aliased destination") end

    for destination <- [source, dir <> "/./source.m4a", symlink, hardlink] do
      assert {:error, :source_destination_alias} =
               Clips.prepare(source, destination, runner: runner)

      assert File.read!(destination) == "source"
      assert File.read!(source) == "source"
    end

    assert Enum.sort(File.ls!(dir)) == ["hardlink.m4a", "source.m4a", "symlink.m4a"]
  end

  test "rejects malformed catalog entries", %{dir: dir} do
    assert {:error, {:invalid_catalog, {:invalid_clip_kind, "voice", "speech"}}} =
             load_catalog(dir, [clip("voice", kind: "speech")])

    assert {:error, {:invalid_catalog, {:invalid_clip_file, "escape", "../escape.m4a"}}} =
             load_catalog(dir, [clip("escape", file: "../escape.m4a")])

    assert {:error, {:invalid_catalog, {:invalid_clip_duration, "silent", nil}}} =
             load_catalog(dir, [clip("silent", status: "available", duration_seconds: nil)])

    assert {:error, {:invalid_catalog, {:invalid_clip_id, "Bad_ID"}}} =
             load_catalog(dir, [clip("Bad_ID")])

    assert {:error, {:invalid_catalog, {:invalid_clip_origin, "no-origin"}}} =
             load_catalog(dir, [clip("no-origin", origin: " ")])

    assert {:error, {:invalid_catalog, {:invalid_clip_status, "wrong-status", "ready"}}} =
             load_catalog(dir, [clip("wrong-status", status: "ready")])

    assert {:error, {:invalid_catalog, {:duplicate, :id}}} =
             load_catalog(dir, [clip("same"), clip("same", file: "other.m4a")])

    assert {:error, {:invalid_catalog, {:duplicate, :file}}} =
             load_catalog(dir, [clip("first"), clip("second", file: "first.m4a")])

    path = Path.join(dir, "catalog.json")
    File.write!(path, "not json")
    assert {:error, :invalid_catalog} = Clips.load_catalog(path)

    File.write!(path, Jason.encode!(%{"version" => 2, "clips" => []}))
    assert {:error, {:invalid_catalog, :unsupported_version}} = Clips.load_catalog(path)

    File.write!(path, Jason.encode!(%{"version" => 1, "clips" => ["not a clip"]}))
    assert {:error, {:invalid_catalog, :invalid_clip}} = Clips.load_catalog(path)
  end

  defp load_catalog(dir, clips) do
    path = Path.join(dir, "catalog.json")
    File.write!(path, Jason.encode!(%{"version" => 1, "clips" => clips}))
    Clips.load_catalog(path)
  end

  defp clip(id, overrides \\ []) do
    Map.merge(
      %{
        "id" => id,
        "kind" => "melody",
        "origin" => "test fixture",
        "duration_seconds" => 2,
        "file" => "#{id}.m4a",
        "status" => "available"
      },
      Map.new(overrides, fn {key, value} -> {Atom.to_string(key), value} end)
    )
  end

  defp catalog_path, do: Path.join(System.tmp_dir!(), "unused-catalog.json")

  defp available_path do
    path = Path.join(System.tmp_dir!(), "nozomi-clip-#{System.unique_integer([:positive])}.m4a")
    File.write!(path, "audio")
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp normalizing_runner(peak \\ "-1.5") do
    verify = passing_runner(peak)

    fn command, args ->
      if "-b:a" in args do
        File.write!(List.last(args), "normalized")
        {"", 0}
      else
        verify.(command, args)
      end
    end
  end

  defp passing_runner(peak \\ "-2.0") do
    fn
      "ffmpeg", args ->
        if "volumedetect" in args, do: {"max_volume: #{peak} dB", 0}, else: {"", 0}

      "ffprobe", _args ->
        {stream_json("aac", "48000", 2), 0}
    end
  end

  defp stream_json(codec, sample_rate, channels) do
    Jason.encode!(%{
      "streams" => [
        %{"codec_name" => codec, "sample_rate" => sample_rate, "channels" => channels}
      ],
      "format" => %{"duration" => "2.0"}
    })
  end
end
