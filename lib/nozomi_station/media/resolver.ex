defmodule NozomiStation.Media.Resolver do
  @max_duration_seconds 15 * 60
  @youtube_id ~r/^[A-Za-z0-9_-]+$/
  @duration ~r/^PT(?:(?<hours>\d+)H)?(?:(?<minutes>\d+)M)?(?:(?<seconds>\d+)S)?$/

  def resolve(url, fetch) when is_binary(url) and is_function(fetch, 2) do
    with {:ok, provider, id} <- identify(url),
         {:ok, track} <- fetch.(provider, id),
         {:ok, seconds} <- duration_seconds(track.duration),
         true <- not track.live? and seconds <= @max_duration_seconds do
      {:ok, track |> Map.delete(:duration) |> Map.put(:duration_seconds, seconds)}
    else
      false -> {:error, :not_playable}
      error -> error
    end
  end

  defp identify(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: "youtu.be", path: "/" <> id}
      when id != "" ->
        if Regex.match?(@youtube_id, id), do: {:ok, :youtube, id}, else: {:error, :invalid_url}

      _ ->
        {:error, :unsupported_url}
    end
  end

  defp duration_seconds(duration) do
    case Regex.named_captures(@duration, duration) do
      nil ->
        {:error, :invalid_duration}

      parts ->
        {:ok,
         number(parts["hours"]) * 3600 + number(parts["minutes"]) * 60 + number(parts["seconds"])}
    end
  end

  defp number(""), do: 0
  defp number(nil), do: 0
  defp number(value), do: String.to_integer(value)
end
