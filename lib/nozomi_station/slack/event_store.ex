defmodule NozomiStation.Slack.EventStore do
  require Logger

  alias NozomiStation.Repo
  alias NozomiStation.Slack.Event

  def accept(payload, enqueue) do
    case Repo.transaction(fn -> accept_in_transaction(payload, enqueue) end) do
      {:ok, result} ->
        Logger.info("slack_event_#{result} event_id=#{payload["event_id"]}")
        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp accept_in_transaction(payload, enqueue) do
    case insert(payload) do
      {:ok, event} ->
        case enqueue.(event) do
          {:ok, _job} -> :accepted
          {:error, reason} -> Repo.rollback(reason)
        end

      :duplicate ->
        :duplicate
    end
  end

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
