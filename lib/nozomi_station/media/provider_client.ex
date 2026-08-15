defmodule NozomiStation.Media.ProviderClient do
  @youtube_videos "https://www.googleapis.com/youtube/v3/videos"
  @youtube_search "https://www.googleapis.com/youtube/v3/search"
  @spotify_token "https://accounts.spotify.com/api/token"
  @spotify_tracks "https://api.spotify.com/v1/tracks/"
  @request_options [redirect: false, receive_timeout: 10_000]

  def fetch(provider, value, request \\ &Req.request/1)

  def fetch(:youtube, id, request) do
    options =
      [
        method: :get,
        url: @youtube_videos,
        params: [part: "snippet,contentDetails", id: id, key: youtube_key()]
      ] ++ @request_options

    request.(options) |> youtube_track()
  end

  def fetch(:youtube_search, query, request) do
    options =
      [
        method: :get,
        url: @youtube_search,
        params: [part: "snippet", type: "video", maxResults: 1, q: query, key: youtube_key()]
      ] ++ @request_options

    case request.(options) do
      {:ok, %Req.Response{status: 200, body: %{"items" => [%{"id" => %{"videoId" => id}} | _]}}} ->
        {:ok, id}

      _ ->
        {:error, :provider_unavailable}
    end
  end

  def fetch(:spotify, id, request) do
    with {:ok, token} <- spotify_token(request),
         {:ok, track} <- spotify_track(id, token, request),
         %{"name" => title, "artists" => [%{"name" => artist} | _]} <- track do
      {:ok, %{title: title, artist: artist}}
    else
      _ -> {:error, :provider_unavailable}
    end
  end

  defp youtube_track({:ok, %Req.Response{status: 200, body: %{"items" => [item | _]}}}) do
    snippet = item["snippet"]

    {:ok,
     %{
       youtube_id: item["id"],
       title: snippet["title"],
       artist: snippet["channelTitle"],
       duration: item["contentDetails"]["duration"],
       live?: snippet["liveBroadcastContent"] != "none"
     }}
  end

  defp youtube_track(_), do: {:error, :provider_unavailable}

  defp spotify_token(request) do
    options =
      [
        method: :post,
        url: @spotify_token,
        form: [grant_type: "client_credentials"],
        auth: {:basic, "#{spotify_id()}:#{spotify_secret()}"}
      ] ++ @request_options

    case request.(options) do
      {:ok, %Req.Response{status: 200, body: %{"access_token" => token}}} -> {:ok, token}
      _ -> {:error, :provider_unavailable}
    end
  end

  defp spotify_track(id, token, request) do
    options =
      [method: :get, url: @spotify_tracks <> id, auth: {:bearer, token}] ++ @request_options

    case request.(options) do
      {:ok, %Req.Response{status: 200, body: track}} -> {:ok, track}
      _ -> {:error, :provider_unavailable}
    end
  end

  defp youtube_key, do: Application.fetch_env!(:nozomi_station, :youtube_api_key)
  defp spotify_id, do: Application.fetch_env!(:nozomi_station, :spotify_client_id)
  defp spotify_secret, do: Application.fetch_env!(:nozomi_station, :spotify_client_secret)
end
