defmodule NozomiStation.Slack.RequestWorker do
  use Oban.Worker, queue: :requests, max_attempts: 5

  alias NozomiStation.Slack.Event

  def enqueue(%Event{event_id: event_id}) do
    %{"event_id" => event_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: :ok
end
