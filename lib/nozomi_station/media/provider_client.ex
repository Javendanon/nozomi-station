defmodule NozomiStation.Media.ProviderClient do
  @youtube_videos "https://www.googleapis.com/youtube/v3/videos"
  @youtube_search "https://www.googleapis.com/youtube/v3/search"
  @spotify_token "https://accounts.spotify.com/api/token"
  @spotify_tracks "https://api.spotify.com/v1/tracks/"

  def fetch(provider, value, request \\ &Req.request/1)

  def fetch(:youtube, id, request) do
    options = [
      method: :get,
      url: @youtube_videos,
      params: [part: "snippet,contentDetails", id: id, key: youtube_key()],
      redirect: false,
      receive_timeout: 10_000
    ]

    with {:ok, %Req.Response{status: 200, body: %{"items" => [item | _]}}} <- request.(options) do
      snippet = item["snippet"]

      {:ok,
       %{
         youtube_id: item["id"],
         title: snippet["title"],
         artist: snippet["channelTitle"],
         duration: item["contentDetails"]["duration"],
         live?: snippet["liveBroadcastContent"] != "none"
       }}
    else
      _ -> {:error, :provider_unavailable}
    end
  end

  def fetch(:youtube_search, query, request) do
    options = [
      method: :get,
      url: @youtube_search,
      params: [part: "snippet", type: "video", maxResults: 1, q: query, key: youtube_key()],
      redirect: false,
      receive_timeout: 10_000
    ]

    case request.(options) do
      {:ok, %Req.Response{status: 200, body: %{"items" => [%{"id" => %{"videoId" => id}} | _]}}} ->
        {:ok, id}

      _ ->
        {:error, :provider_unavailable}
    end
  end

  def fetch(:spotify, id, request) do
    with {:ok, %Req.Response{status: 200, body: %{"access_token" => token}}} <-
           request.(
             method: :post,
             url: @spotify_token,
             form: [grant_type: "client_credentials"],
             auth: {:basic, "#{spotify_id()}:#{spotify_secret()}"},
             redirect: false,
             receive_timeout: 10_000
           ),
         {:ok, %Req.Response{status: 200, body: track}} <-
           request.(
             method: :get,
             url: @spotify_tracks <> id,
             auth: {:bearer, token},
             redirect: false,
             receive_timeout: 10_000
           ),
         %{"name" => title, "artists" => [%{"name" => artist} | _]} <- track do
      {:ok, %{title: title, artist: artist}}
    else
      _ -> {:error, :provider_unavailable}
    end
  end

  defp youtube_key, do: Application.fetch_env!(:nozomi_station, :youtube_api_key)
  defp spotify_id, do: Application.fetch_env!(:nozomi_station, :spotify_client_id)
  defp spotify_secret, do: Application.fetch_env!(:nozomi_station, :spotify_client_secret)
end
