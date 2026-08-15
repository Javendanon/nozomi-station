defmodule NozomiStation.Programming.ComplementaryTrack do
  use Ecto.Schema

  import Ecto.Changeset

  schema "complementary_tracks" do
    field(:youtube_id, :string)
    field(:title, :string)
    field(:artist, :string)
    field(:duration_seconds, :integer)
    field(:origin, :string)
    field(:status, :string, default: "preparing")
    field(:file_path, :string)
    timestamps(type: :utc_datetime)
  end

  def changeset(track, attrs) do
    track
    |> cast(attrs, [
      :youtube_id,
      :title,
      :artist,
      :duration_seconds,
      :origin,
      :status,
      :file_path
    ])
    |> validate_required([:youtube_id, :title, :artist, :duration_seconds, :origin, :status])
    |> validate_inclusion(:origin, ["seed", "mood"])
    |> validate_inclusion(:status, ["preparing", "ready", "queued", "played", "failed", "skipped"])
    |> unique_constraint(:youtube_id)
  end
end
