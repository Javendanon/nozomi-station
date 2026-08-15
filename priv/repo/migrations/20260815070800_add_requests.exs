defmodule NozomiStation.Repo.Migrations.AddRequests do
  use Ecto.Migration

  def change do
    create table(:requests) do
      add :youtube_id, :string, null: false
      add :title, :string, null: false
      add :artist, :string, null: false
      add :duration_seconds, :integer, null: false
      add :slack_user, :string, null: false
      add :slack_channel, :string, null: false
      add :thread_ts, :string, null: false
      add :status, :string, null: false, default: "preparing"
      add :file_path, :string
      timestamps(type: :utc_datetime)
    end

    create index(:requests, [:status, :id])

    create unique_index(:requests, [:youtube_id],
             where: "status IN ('preparing', 'ready')",
             name: :requests_active_youtube_id_index
           )
  end
end
