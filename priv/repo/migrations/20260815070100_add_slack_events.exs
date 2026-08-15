defmodule NozomiStation.Repo.Migrations.AddSlackEvents do
  use Ecto.Migration

  def change do
    create table(:slack_events) do
      add :event_id, :string, null: false
      add :payload, :map, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:slack_events, [:event_id])
  end
end
