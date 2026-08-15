defmodule NozomiStationWeb.SlackEventController do
  use NozomiStationWeb, :controller

  def create(conn, %{"type" => "url_verification", "challenge" => challenge}) do
    json(conn, %{challenge: challenge})
  end

  def create(conn, _params), do: send_resp(conn, :accepted, "")
end
