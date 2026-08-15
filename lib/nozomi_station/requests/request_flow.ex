defmodule NozomiStation.Requests.RequestFlow do
  import Ecto.Query

  alias NozomiStation.Media.Preparer
  alias NozomiStation.Repo
  alias NozomiStation.Requests.Request

  @active_statuses ["preparing", "ready", "queued"]

  def prepare(track, requester) do
    prepare_with(track, requester, &Preparer.prepare/2)
  end

  def prepare(track, requester, runner) do
    prepare_with(track, requester, fn youtube_id, request_id ->
      Preparer.prepare(youtube_id, request_id, runner)
    end)
  end

  defp prepare_with(track, requester, prepare) do
    with {:ok, request} <- reserve(track, requester) do
      case prepare.(track.youtube_id, request.id) do
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

  defp duplicate?(youtube_id), do: active?(youtube_id) or youtube_id in recent_ids()

  defp active?(youtube_id) do
    Repo.exists?(
      from(request in Request,
        where: request.youtube_id == ^youtube_id and request.status in @active_statuses
      )
    )
  end

  defp recent_ids do
    Repo.all(
      from(request in Request,
        where: request.status == "played",
        order_by: [desc: request.updated_at, desc: request.id],
        limit: 10,
        select: request.youtube_id
      )
    )
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
