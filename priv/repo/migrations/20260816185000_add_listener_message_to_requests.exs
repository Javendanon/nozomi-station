defmodule NozomiStation.Repo.Migrations.AddListenerMessageToRequests do
  use Ecto.Migration

  def change do
    alter table(:requests) do
      add :listener_message, :string, size: 280
    end
  end
end
