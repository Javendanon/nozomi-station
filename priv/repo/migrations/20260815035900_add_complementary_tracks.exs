defmodule NozomiStation.Repo.Migrations.AddComplementaryTracks do
  use Ecto.Migration

  def change do
    create table(:complementary_tracks) do
      add :youtube_id, :string, null: false
      add :title, :string, null: false
      add :artist, :string, null: false
      add :duration_seconds, :integer, null: false
      add :origin, :string, null: false
      add :status, :string, null: false, default: "preparing"
      add :file_path, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:complementary_tracks, [:youtube_id])
    create index(:complementary_tracks, [:status, :id])

    drop index(:requests, [:youtube_id], name: :requests_active_youtube_id_index)

    create unique_index(:requests, [:youtube_id],
             where: "status IN ('preparing', 'ready', 'queued')",
             name: :requests_active_youtube_id_index
           )
  end
end
