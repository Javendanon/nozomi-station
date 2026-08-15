defmodule NozomiStation.Media.ProviderClient do
  @youtube_videos "https://www.googleapis.com/youtube/v3/videos"

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

  defp youtube_key, do: Application.fetch_env!(:nozomi_station, :youtube_api_key)
end
