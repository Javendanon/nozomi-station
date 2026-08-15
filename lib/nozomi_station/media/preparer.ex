defmodule NozomiStation.Media.Preparer do
  alias NozomiStation.Media.YtDlp

  def prepare(youtube_id, output, runner \\ &YtDlp.run/2) do
    base = Path.join(media_dir(), output_name(output))
    File.mkdir_p!(Path.dirname(base))

    args =
      YtDlp.auth_args() ++
        [
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
    File.rm(path)

    case runner.("yt-dlp", args) do
      {_output, 0} ->
        if(File.regular?(path), do: {:ok, path}, else: {:error, :preparation_failed})

      _ ->
        {:error, :preparation_failed}
    end
  end

  defp output_name(id) when is_integer(id), do: Integer.to_string(id)
  defp output_name({:complementary, id}) when is_integer(id), do: "c#{id}"

  defp media_dir, do: Application.get_env(:nozomi_station, :media_dir, "tmp/media")
end
