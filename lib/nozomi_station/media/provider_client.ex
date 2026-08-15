defmodule NozomiStation.Media.ProviderClient do
  @spotify_token "https://accounts.spotify.com/api/token"
  @spotify_tracks "https://api.spotify.com/v1/tracks/"
  @request_options [redirect: false, receive_timeout: 10_000]

  def fetch(:spotify, id, request \\ &Req.request/1) do
    with {:ok, token} <- spotify_token(request),
         {:ok, track} <- spotify_track(id, token, request),
         %{"name" => title, "artists" => [%{"name" => artist} | _]} <- track do
      {:ok, %{title: title, artist: artist}}
    else
      _ -> {:error, :provider_unavailable}
    end
  end

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

  defp spotify_id, do: Application.fetch_env!(:nozomi_station, :spotify_client_id)
  defp spotify_secret, do: Application.fetch_env!(:nozomi_station, :spotify_client_secret)
end
