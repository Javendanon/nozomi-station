defmodule NozomiStationWeb.SlackEventController do
  use NozomiStationWeb, :controller

  alias NozomiStation.Slack.{EventStore, RequestWorker}

  def create(conn, %{"type" => "url_verification", "challenge" => challenge}) do
    json(conn, %{challenge: challenge})
  end

  def create(conn, %{"type" => "event_callback"} = event) do
    case EventStore.accept(event, &RequestWorker.enqueue/1) do
      status when status in [:accepted, :duplicate] -> send_resp(conn, :accepted, "")
      {:error, _reason} -> send_resp(conn, :service_unavailable, "")
    end
  end

  def create(conn, _params), do: send_resp(conn, :bad_request, "")
end
