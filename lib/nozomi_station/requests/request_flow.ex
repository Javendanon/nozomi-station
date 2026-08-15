defmodule NozomiStation.Requests.RequestFlow do
  import Ecto.Query

  alias NozomiStation.Media.Preparer
  alias NozomiStation.Repo
  alias NozomiStation.Requests.Request

  @active_statuses ["preparing", "ready"]

  def prepare(track, requester, runner \\ &System.cmd/2) do
    with {:ok, request} <- reserve(track, requester) do
      case Preparer.prepare(track.youtube_id, request.id, runner) do
        {:ok, path} ->
          with {:ok, ready} <- persist(request, %{status: "ready", file_path: path}) do
            {:ok, ready, position(ready)}
          end

        {:error, reason} ->
          persist(request, %{status: "failed"})
          {:error, reason}
      end
    end
  end

  defp reserve(track, requester) do
    if duplicate?(track.youtube_id) do
      {:error, :duplicate}
    else
      attrs = Map.merge(track, Map.put(requester, :status, "preparing"))

      case Repo.insert(Request.changeset(%Request{}, attrs)) do
        {:error, changeset} ->
          if changeset.errors[:youtube_id], do: {:error, :duplicate}, else: {:error, changeset}

        result ->
          result
      end
    end
  end

  defp duplicate?(youtube_id) do
    active? =
      Repo.exists?(
        from(request in Request,
          where: request.youtube_id == ^youtube_id and request.status in @active_statuses
        )
      )

    recent_ids =
      Repo.all(
        from(request in Request,
          where: request.status == "played",
          order_by: [desc: request.updated_at, desc: request.id],
          limit: 10,
          select: request.youtube_id
        )
      )

    active? or youtube_id in recent_ids
  end

  defp persist(request, attrs), do: request |> Request.changeset(attrs) |> Repo.update()

  defp position(request) do
    Repo.aggregate(
      from(item in Request,
        where: item.status in @active_statuses and item.id <= ^request.id
      ),
      :count
    )
  end
end
