defmodule NozomiStation.Media.Resolver do
  @max_duration_seconds 15 * 60
  @youtube_id ~r/^[A-Za-z0-9_-]+$/
  @spotify_id ~r/^[A-Za-z0-9]+$/
  @duration ~r/^PT(?:(?<hours>\d+)H)?(?:(?<minutes>\d+)M)?(?:(?<seconds>\d+)S)?$/

  def resolve(url, fetch) when is_binary(url) and is_function(fetch, 2) do
    with {:ok, provider, id} <- identify(url),
         {:ok, track} <- resolve_provider(provider, id, fetch) do
      validate(track)
    end
  end

  def resolve_search(query, fetch) when is_binary(query) and is_function(fetch, 2) do
    with {:ok, youtube_id} <- fetch.(:youtube_search, query),
         {:ok, track} <- fetch.(:youtube, youtube_id) do
      validate(track)
    end
  end

  defp identify(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: "youtu.be", path: "/" <> id}
      when id != "" ->
        youtube(id)

      %URI{scheme: "https", host: host, path: "/watch", query: query}
      when host in ["youtube.com", "www.youtube.com", "music.youtube.com"] and is_binary(query) ->
        query |> URI.decode_query() |> Map.get("v") |> youtube()

      %URI{scheme: "https", host: "open.spotify.com", path: "/track/" <> id} ->
        if Regex.match?(@spotify_id, id), do: {:ok, :spotify, id}, else: {:error, :invalid_url}

      _ ->
        {:error, :unsupported_url}
    end
  end

  defp resolve_provider(:youtube, id, fetch), do: fetch.(:youtube, id)

  defp resolve_provider(:spotify, id, fetch) do
    with {:ok, %{artist: artist, title: title}} <- fetch.(:spotify, id),
         {:ok, youtube_id} <- fetch.(:youtube_search, "#{artist} #{title}"),
         {:ok, track} <- fetch.(:youtube, youtube_id) do
      {:ok, track}
    end
  end

  defp youtube(id) when is_binary(id) do
    if Regex.match?(@youtube_id, id), do: {:ok, :youtube, id}, else: {:error, :invalid_url}
  end

  defp youtube(_), do: {:error, :invalid_url}

  defp validate(track) do
    with {:ok, seconds} <- duration_seconds(track.duration),
         true <- not track.live? and seconds <= @max_duration_seconds do
      {:ok, track |> Map.delete(:duration) |> Map.put(:duration_seconds, seconds)}
    else
      false -> {:error, :not_playable}
      error -> error
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
