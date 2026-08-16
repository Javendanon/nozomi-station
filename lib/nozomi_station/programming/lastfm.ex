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

  def track_info(artist, title, request \\ &Req.request/1) do
    if key = api_key() do
      request_track_info(artist, title, key, request)
    else
      {:ok, %{}}
    end
  end

  defp request_track_info(artist, title, key, request) do
    options =
      [
        method: :get,
        url: @endpoint,
        params: [
          method: "track.getInfo",
          api_key: key,
          artist: artist,
          track: title,
          format: "json"
        ]
      ] ++ @request_options

    case request.(options) do
      {:ok, %Req.Response{status: 200, body: %{"track" => track}}} ->
        {:ok, track_details(track)}

      _ ->
        Logger.warning("lastfm_request_failed method=track.getInfo")
        {:error, :provider_unavailable}
    end
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

  defp track_details(track) do
    %{}
    |> put_detail(:album, get_in(track, ["album", "title"]))
    |> put_detail(:cover_url, cover_url(get_in(track, ["album", "image"])))
    |> put_detail(:tags, tags(get_in(track, ["toptags", "tag"])))
    |> put_detail(:summary, summary(get_in(track, ["wiki", "summary"])))
  end

  defp cover_url(images) when is_list(images) do
    images
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{"#text" => url} when is_binary(url) -> if allowed_image?(url), do: url
      _ -> nil
    end)
  end

  defp cover_url(_), do: nil

  defp allowed_image?(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: "lastfm.freetls.fastly.net"} -> true
      _ -> false
    end
  end

  defp tags(values) when is_list(values) do
    values
    |> Enum.flat_map(fn
      %{"name" => name} when is_binary(name) and name != "" -> [name]
      _ -> []
    end)
    |> Enum.take(5)
  end

  defp tags(_), do: []

  defp summary(value) when is_binary(value) do
    value
    |> String.split("<a href=", parts: 2)
    |> hd()
    |> String.trim()
  end

  defp summary(_), do: nil

  defp put_detail(details, _key, value) when value in [nil, "", []], do: details
  defp put_detail(details, key, value), do: Map.put(details, key, value)

  defp unique(tracks, limit) do
    tracks
    |> Enum.uniq_by(&{&1.artist, &1.title})
    |> Enum.take(limit)
  end

  defp api_key, do: Application.fetch_env!(:nozomi_station, :lastfm_api_key)
end
