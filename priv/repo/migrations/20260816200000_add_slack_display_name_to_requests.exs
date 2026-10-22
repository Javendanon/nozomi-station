defmodule NozomiStation.Repo.Migrations.AddSlackDisplayNameToRequests do
  use Ecto.Migration

  def change do
    alter table(:requests) do
      add :slack_display_name, :string
    end
  end
end
