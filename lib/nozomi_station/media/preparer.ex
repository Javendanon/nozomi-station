defmodule NozomiStation.Media.Preparer do
  @timeout 120_000

  def prepare(youtube_id, request_id, runner \\ &run/2) do
    base = Path.join(media_dir(), Integer.to_string(request_id))
    File.mkdir_p!(Path.dirname(base))

    args = [
      "--no-playlist",
      "--no-live-from-start",
      "--max-filesize",
      "50M",
      "--extract-audio",
      "--audio-format",
      "m4a",
      "--output",
      base <> ".%(ext)s",
      "https://www.youtube.com/watch?v=#{youtube_id}"
    ]

    path = base <> ".m4a"

    case runner.("yt-dlp", args) do
      {_output, 0} ->
        if(File.regular?(path), do: {:ok, path}, else: {:error, :preparation_failed})

      _ ->
        {:error, :preparation_failed}
    end
  end

  defp run(command, args) do
    task = Task.async(fn -> System.cmd(command, args, stderr_to_stdout: true) end)

    case Task.yield(task, @timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> {"preparation timed out", 1}
    end
  end

  defp media_dir, do: Application.get_env(:nozomi_station, :media_dir, "tmp/media")
end
