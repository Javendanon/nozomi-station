defmodule NozomiStation.Programming.Scheduler do
  import Ecto.Query

  require Logger

  alias NozomiStation.Programming.{ComplementaryTrack, LiquidsoapClient}
  alias NozomiStation.Repo
  alias NozomiStation.Requests.Request

  def run(options \\ []) do
    active_paths = Keyword.get(options, :active_paths, &LiquidsoapClient.active_paths/0)
    push = Keyword.get(options, :push, &LiquidsoapClient.push/2)

    with {:ok, paths} <- active_paths.() do
      reconcile(paths)
      requested = dispatch(Request, :requested, push)
      complementary = dispatch(ComplementaryTrack, :complementary, push)
      {:ok, %{requested: requested, complementary: complementary}}
    end
  end

  defp reconcile(active_paths) do
    mark_completed(Request, active_paths)
    mark_completed(ComplementaryTrack, active_paths)
  end

  defp mark_completed(schema, active_paths) do
    from(item in schema, where: item.status == "queued" and item.file_path not in ^active_paths)
    |> Repo.update_all(set: [status: "played", updated_at: DateTime.utc_now(:second)])
  end

  defp dispatch(schema, queue, push) do
    schema
    |> ready()
    |> Enum.count(fn item -> dispatch_item(item, queue, push) end)
  end

  defp ready(schema) do
    Repo.all(from(item in schema, where: item.status == "ready", order_by: item.id))
  end

  defp dispatch_item(item, queue, push) do
    case push.(queue, item.file_path) do
      :ok ->
        item |> Ecto.Changeset.change(status: "queued") |> Repo.update!()
        Logger.info("programming_dispatched queue=#{queue} id=#{item.id}")
        true

      {:error, reason} ->
        Logger.warning(
          "programming_dispatch_failed queue=#{queue} id=#{item.id} reason=#{reason}"
        )

        false
    end
  end
end
