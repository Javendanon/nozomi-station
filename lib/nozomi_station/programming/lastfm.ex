defmodule NozomiStation.Programming.Lastfm do
  require Logger

  @endpoint "https://ws.audioscrobbler.com/2.0/"
  @seeds ["rock", "80s"]
  @request_options [redirect: false, receive_timeout: 10_000]

  def candidates(mood, limit, request \\ &Req.request/1)

  def candidates([], limit, request) do
    tracks =
      Enum.flat_map(@seeds, fn tag ->
        fetch(request, "tag.gettoptracks", tag: tag, limit: limit)
      end)

    {:ok, unique(tracks, limit)}
  end

  def candidates(mood, limit, request) do
    tracks =
      mood
      |> Enum.reduce_while([], fn track, found ->
        if length(found) >= limit do
          {:halt, found}
        else
          params = [artist: track.artist, track: track.title, limit: limit]
          {:cont, found ++ fetch(request, "track.getsimilar", params)}
        end
      end)

    {:ok, unique(tracks, limit)}
  end

  defp fetch(request, method, params) do
    options =
      [
        method: :get,
        url: @endpoint,
        params: [method: method, api_key: api_key(), format: "json"] ++ params
      ] ++ @request_options

    case request.(options) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        tracks(body)

      _ ->
        Logger.warning("lastfm_request_failed method=#{method}")
        []
    end
  end

  defp tracks(%{"tracks" => %{"track" => tracks}}), do: Enum.flat_map(tracks, &candidate/1)
  defp tracks(%{"similartracks" => %{"track" => tracks}}), do: Enum.flat_map(tracks, &candidate/1)
  defp tracks(_), do: []

  defp candidate(%{"name" => title, "artist" => %{"name" => artist}})
       when is_binary(title) and is_binary(artist) do
    [%{title: title, artist: artist}]
  end

  defp candidate(%{"name" => title, "artist" => artist})
       when is_binary(title) and is_binary(artist) do
    [%{title: title, artist: artist}]
  end

  defp candidate(_), do: []

  defp unique(tracks, limit) do
    tracks
    |> Enum.uniq_by(&{&1.artist, &1.title})
    |> Enum.take(limit)
  end

  defp api_key, do: Application.fetch_env!(:nozomi_station, :lastfm_api_key)
end
