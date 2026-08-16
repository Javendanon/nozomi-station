defmodule NozomiStation.Requests.Request do
  use Ecto.Schema

  import Ecto.Changeset

  schema "requests" do
    field(:youtube_id, :string)
    field(:title, :string)
    field(:artist, :string)
    field(:duration_seconds, :integer)
    field(:slack_user, :string)
    field(:slack_channel, :string)
    field(:thread_ts, :string)
    field(:listener_message, :string)
    field(:status, :string, default: "preparing")
    field(:file_path, :string)
    timestamps(type: :utc_datetime)
  end

  def changeset(request, attrs) do
    request
    |> cast(attrs, [
      :youtube_id,
      :title,
      :artist,
      :duration_seconds,
      :slack_user,
      :slack_channel,
      :thread_ts,
      :listener_message,
      :status,
      :file_path
    ])
    |> validate_required([
      :youtube_id,
      :title,
      :artist,
      :duration_seconds,
      :slack_user,
      :slack_channel,
      :thread_ts,
      :status
    ])
    |> validate_length(:listener_message, max: 280)
    |> unique_constraint(:youtube_id, name: :requests_active_youtube_id_index)
  end
end
