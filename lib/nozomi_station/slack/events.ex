defmodule NozomiStation.Slack.Events do
  def accept(event, store, enqueue) do
    case store.(event) do
      {:ok, stored_event} ->
        enqueue.(stored_event)
        :accepted

      :duplicate ->
        :duplicate
    end
  end
end
