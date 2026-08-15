defmodule NozomiStation.Media.YtDlp do
  @metadata_timeout 30_000
  @download_timeout 120_000
  @youtube_id ~r/^[A-Za-z0-9_-]+$/

  def fetch(provider, value, runner \\ &run_metadata/2)

  def fetch(:youtube, id, runner) when is_binary(id) do
    if Regex.match?(@youtube_id, id) do
      metadata("https://www.youtube.com/watch?v=#{id}", runner)
    else
      {:error, :provider_unavailable}
    end
  end

  def fetch(:youtube_search, query, runner) when is_binary(query) do
    query = String.trim(query)

    if query != "" and byte_size(query) <= 500 do
      metadata("ytsearch1:#{query}", runner)
    else
      {:error, :provider_unavailable}
    end
  end

  def auth_args do
    path =
      Application.get_env(:nozomi_station, :ytdlp_cookies_file) ||
        System.get_env("YTDLP_COOKIES_FILE")

    if is_binary(path) and path != "" and File.regular?(path), do: ["--cookies", path], else: []
  end

  def run(command, args), do: run(command, args, @download_timeout)

  defp metadata(target, runner) do
    args =
      auth_args() ++ ["--quiet", "--no-warnings", "--dump-single-json", "--skip-download", target]

    case runner.("yt-dlp", args) do
      {output, 0} -> parse(output)
      _ -> {:error, :provider_unavailable}
    end
  end

  defp parse(output) do
    with {:ok, decoded} <- Jason.decode(output),
         metadata <- first_entry(decoded),
         id when is_binary(id) and id != "" <- metadata["id"],
         title when is_binary(title) and title != "" <- metadata["title"],
         artist when is_binary(artist) and artist != "" <- artist(metadata),
         {:ok, duration} <- duration(metadata["duration"]) do
      {:ok,
       %{
         youtube_id: id,
         title: title,
         artist: artist,
         duration: duration,
         live?: live?(metadata)
       }}
    else
      _ -> {:error, :provider_unavailable}
    end
  end

  defp first_entry(%{"entries" => [entry | _]}) when is_map(entry), do: entry
  defp first_entry(metadata), do: metadata

  defp artist(metadata), do: metadata["channel"] || metadata["uploader"]
  defp duration(value) when is_integer(value) and value >= 0, do: {:ok, value}
  defp duration(value) when is_float(value) and value >= 0, do: {:ok, ceil(value)}
  defp duration(_), do: {:error, :provider_unavailable}

  defp live?(metadata) do
    metadata["is_live"] == true or metadata["live_status"] in ["is_live", "is_upcoming"]
  end

  defp run_metadata(command, args), do: run(command, args, @metadata_timeout)

  defp run(command, args, timeout) do
    task = Task.async(fn -> System.cmd(command, args, stderr_to_stdout: true) end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> {"yt-dlp failed", 1}
    end
  end
end
