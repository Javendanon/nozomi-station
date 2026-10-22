defmodule NozomiStation.Railway.Clips do
  @moduledoc """
  Owns the local railway interlude catalog: metadata validation, normalization
  and the decode/level checks that gate every broadcastable clip.
  """

  @default_catalog "priv/railway/clips/catalog.json"
  @kinds ~w(announcement melody ambience)
  @statuses ~w(available pending)
  @id_format ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/
  @file_format ~r/^[a-z0-9]+(?:-[a-z0-9]+)*\.m4a$/

  @target_codec "aac"
  @target_sample_rate 48_000
  @target_channels 2
  @max_peak_db -1.0
  @loudness_filter "loudnorm=I=-16:TP=-1.5:LRA=11"
  @peak_format ~r/max_volume:\s*(-?\d+(?:\.\d+)?) dB/

  def load_catalog(path \\ @default_catalog) do
    with {:ok, body} <- File.read(path),
         {:ok, decoded} <- Jason.decode(body),
         {:ok, clips} <- validate_catalog(decoded) do
      {:ok, %{version: decoded["version"], clips: clips}}
    else
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_catalog}
      {:error, reason} -> {:error, reason}
    end
  end

  def verify_catalog(catalog, catalog_path \\ @default_catalog, opts \\ []) do
    catalog.clips
    |> Enum.filter(&(&1.status == "available"))
    |> Enum.reduce_while({:ok, []}, fn clip, {:ok, results} ->
      case verify_clip(clip, catalog_path, opts) do
        {:ok, metadata} -> {:cont, {:ok, [Map.put(metadata, :id, clip.id) | results]}}
        {:error, reason} -> {:halt, {:error, {clip.id, reason}}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end

  def verify_clip(clip, catalog_path \\ @default_catalog, opts \\ []) do
    clip
    |> clip_path(catalog_path)
    |> verify_file(opts)
  end

  def verify_file(path, opts \\ []) do
    runner = Keyword.get(opts, :runner, &run/2)

    with :ok <- ensure_regular_file(path),
         :ok <- decode(path, runner),
         {:ok, stream} <- probe_stream(path, runner),
         :ok <- validate_stream(stream),
         {:ok, peak_db} <- probe_peak(path, runner),
         :ok <- validate_peak(peak_db) do
      {:ok, Map.put(stream, :peak_db, peak_db)}
    end
  end

  def prepare(source, destination, opts \\ []) do
    with :ok <- ensure_regular_file(source),
         :ok <- ensure_destination(destination),
         :ok <- ensure_distinct_files(source, destination) do
      prepare_temporary(source, destination, opts)
    end
  end

  defp prepare_temporary(source, destination, opts) do
    runner = Keyword.get(opts, :runner, &run/2)
    directory = destination <> ".prepare-#{System.unique_integer([:positive])}"

    with :ok <- File.mkdir(directory) do
      temporary = Path.join(directory, "clip.m4a")

      try do
        with {_output, 0} <- runner.("ffmpeg", normalize_args(source, temporary)),
             {:ok, metadata} <- verify_file(temporary, opts),
             :ok <- File.rename(temporary, destination) do
          {:ok, metadata}
        else
          {:error, reason} -> {:error, reason}
          {_output, _status} -> {:error, :normalization_failed}
        end
      after
        File.rm_rf(directory)
      end
    end
  end

  defp validate_catalog(%{"version" => 1, "clips" => clips}) when is_list(clips) do
    with {:ok, clips} <- map_ok(clips, &validate_clip/1),
         :ok <- unique(clips, :id),
         :ok <- unique(clips, :file) do
      {:ok, clips}
    else
      {:error, reason} -> {:error, {:invalid_catalog, reason}}
    end
  end

  defp validate_catalog(_), do: {:error, {:invalid_catalog, :unsupported_version}}

  defp validate_clip(clip) when is_map(clip) do
    id = clip["id"]
    kind = clip["kind"]
    origin = clip["origin"]
    status = clip["status"]
    file = clip["file"]
    duration = clip["duration_seconds"]

    cond do
      not valid_id?(id) ->
        {:error, {:invalid_clip_id, id}}

      kind not in @kinds ->
        {:error, {:invalid_clip_kind, id, kind}}

      not non_empty_string?(origin) ->
        {:error, {:invalid_clip_origin, id}}

      status not in @statuses ->
        {:error, {:invalid_clip_status, id, status}}

      not valid_file?(file) ->
        {:error, {:invalid_clip_file, id, file}}

      not valid_duration?(duration, status) ->
        {:error, {:invalid_clip_duration, id, duration}}

      true ->
        {:ok,
         %{
           id: id,
           kind: kind,
           origin: origin,
           duration_seconds: duration,
           file: file,
           status: status
         }}
    end
  end

  defp validate_clip(_), do: {:error, :invalid_clip}

  defp valid_id?(id), do: is_binary(id) and Regex.match?(@id_format, id)

  defp valid_file?(file) do
    is_binary(file) and Regex.match?(@file_format, file) and Path.basename(file) == file
  end

  defp non_empty_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp valid_duration?(duration, "pending") when duration in [nil, 0], do: true

  defp valid_duration?(duration, _status) do
    is_number(duration) and duration > 0
  end

  defp map_ok(items, fun) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp unique(clips, field) do
    values = Enum.map(clips, &Map.fetch!(&1, field))

    if length(values) == length(Enum.uniq(values)),
      do: :ok,
      else: {:error, {:duplicate, field}}
  end

  defp clip_path(clip, catalog_path), do: Path.join(Path.dirname(catalog_path), clip.file)

  defp ensure_regular_file(path) do
    if is_binary(path) and File.regular?(path), do: :ok, else: {:error, :missing_file}
  end

  defp ensure_destination(path) do
    if is_binary(path) and Path.extname(path) == ".m4a" do
      File.mkdir_p(Path.dirname(path))
    else
      {:error, :invalid_destination}
    end
  end

  defp ensure_distinct_files(source, destination) do
    with {:ok, source_stat} <- File.stat(source),
         {:ok, destination_stat} <- File.stat(destination) do
      if source_stat.inode == destination_stat.inode and
           source_stat.major_device == destination_stat.major_device do
        {:error, :source_destination_alias}
      else
        :ok
      end
    else
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode(path, runner) do
    case runner.("ffmpeg", ["-xerror", "-v", "error", "-nostdin", "-i", path, "-f", "null", "-"]) do
      {_output, 0} -> :ok
      _ -> {:error, :undecodable}
    end
  end

  defp probe_stream(path, runner) do
    args = [
      "-v",
      "error",
      "-select_streams",
      "a:0",
      "-show_entries",
      "stream=codec_name,sample_rate,channels:format=duration",
      "-of",
      "json",
      path
    ]

    with {output, 0} <- runner.("ffprobe", args),
         {:ok, %{"streams" => [stream | _], "format" => %{"duration" => duration}}} <-
           Jason.decode(output),
         {:ok, duration_seconds} <- to_float(duration),
         {:ok, sample_rate} <- to_integer(stream["sample_rate"]),
         {:ok, channels} <- to_integer(stream["channels"]) do
      {:ok,
       %{
         codec: stream["codec_name"],
         sample_rate: sample_rate,
         channels: channels,
         duration_seconds: duration_seconds
       }}
    else
      _ -> {:error, :invalid_metadata}
    end
  end

  defp validate_stream(stream) do
    cond do
      stream.codec != @target_codec -> {:error, {:unsupported_codec, stream.codec}}
      stream.sample_rate != @target_sample_rate -> {:error, :unsupported_sample_rate}
      stream.channels != @target_channels -> {:error, :unsupported_channels}
      stream.duration_seconds <= 0 -> {:error, :invalid_duration}
      true -> :ok
    end
  end

  defp probe_peak(path, runner) do
    args = ["-v", "info", "-nostdin", "-i", path, "-af", "volumedetect", "-f", "null", "-"]

    with {output, 0} <- runner.("ffmpeg", args),
         [_, peak] <- Regex.run(@peak_format, output),
         {:ok, peak_db} <- to_float(peak) do
      {:ok, peak_db}
    else
      _ -> {:error, :invalid_levels}
    end
  end

  defp validate_peak(peak_db) when peak_db > @max_peak_db,
    do: {:error, {:peak_too_high, peak_db}}

  defp validate_peak(_peak_db), do: :ok

  defp normalize_args(source, destination) do
    [
      "-n",
      "-xerror",
      "-v",
      "error",
      "-nostdin",
      "-i",
      source,
      "-af",
      @loudness_filter,
      "-ac",
      Integer.to_string(@target_channels),
      "-ar",
      Integer.to_string(@target_sample_rate),
      "-c:a",
      @target_codec,
      "-b:a",
      "192k",
      destination
    ]
  end

  defp to_float(value) when is_float(value), do: {:ok, value}
  defp to_float(value) when is_integer(value), do: {:ok, value / 1}

  defp to_float(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> :error
    end
  end

  defp to_float(_), do: :error

  defp to_integer(value) when is_integer(value), do: {:ok, value}

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> :error
    end
  end

  defp to_integer(_), do: :error

  defp run(command, args) do
    System.cmd(command, args, stderr_to_stdout: true)
  rescue
    _ -> {"#{command} unavailable", 127}
  end
end
