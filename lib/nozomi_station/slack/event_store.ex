defmodule NozomiStation.Slack.EventStore do
  alias NozomiStation.Repo
  alias NozomiStation.Slack.Event

  def insert(%{"event_id" => event_id} = payload) do
    result =
      %Event{}
      |> Event.changeset(%{event_id: event_id, payload: payload})
      |> Repo.insert(on_conflict: :nothing, conflict_target: :event_id, returning: true)

    case result do
      {:ok, %Event{id: nil}} -> :duplicate
      other -> other
    end
  end
end
