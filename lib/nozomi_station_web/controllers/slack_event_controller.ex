defmodule NozomiStationWeb.SlackEventController do
  use NozomiStationWeb, :controller

  alias NozomiStation.Slack.{Events, EventStore, RequestWorker}

  def create(conn, %{"type" => "url_verification", "challenge" => challenge}) do
    json(conn, %{challenge: challenge})
  end

  def create(conn, %{"type" => "event_callback"} = event) do
    Events.accept(event, &EventStore.insert/1, &RequestWorker.enqueue/1)
    send_resp(conn, :accepted, "")
  end

  def create(conn, _params), do: send_resp(conn, :bad_request, "")
end
