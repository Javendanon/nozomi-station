defmodule NozomiStation.Slack.Event do
  use Ecto.Schema

  import Ecto.Changeset

  schema "slack_events" do
    field(:event_id, :string)
    field(:payload, :map)
    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:event_id, :payload])
    |> validate_required([:event_id, :payload])
    |> unique_constraint(:event_id)
  end
end
