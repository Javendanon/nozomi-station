defmodule NozomiStation.Slack.RequestWorker do
  use Oban.Worker, queue: :requests, max_attempts: 5

  import Ecto.Query

  alias NozomiStation.Media.{ProviderClient, Resolver}
  alias NozomiStation.Repo
  alias NozomiStation.Requests.RequestFlow
  alias NozomiStation.Slack.{Client, Event, RequestProcessor}

  def enqueue(%Event{event_id: event_id}) do
    %{"event_id" => event_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: perform(job, dependencies())

  def perform(%Oban.Job{args: %{"event_id" => event_id}}, deps) do
    case Repo.one(from(event in Event, where: event.event_id == ^event_id)) do
      nil -> {:discard, :event_not_found}
      event -> RequestProcessor.process(event.payload, deps)
    end
  end

  defp dependencies do
    [
      channel: Application.fetch_env!(:nozomi_station, :slack_channel_id),
      resolver: fn url -> Resolver.resolve(url, &ProviderClient.fetch/2) end,
      prepare: &RequestFlow.prepare/2,
      reply: &Client.reply/3
    ]
  end
end
