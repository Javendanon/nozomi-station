defmodule NozomiStation.Programming.Scheduler do
  use GenServer

  import Ecto.Query

  require Logger

  alias NozomiStation.Programming.{ComplementaryTrack, LiquidsoapClient}
  alias NozomiStation.Repo
  alias NozomiStation.Requests.Request

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: Keyword.get(options, :name, __MODULE__))
  end

  @impl true
  def init(options) do
    if Keyword.get(options, :poll, true), do: send(self(), :poll)
    {:ok, options}
  end

  @impl true
  def handle_info(:poll, options) do
    case Keyword.get(options, :run, &run/0).() do
      {:ok, _counts} -> :ok
      {:error, reason} -> Logger.warning("programming_poll_failed reason=#{inspect(reason)}")
    end

    Process.send_after(self(), :poll, Keyword.get(options, :poll_interval, 2_000))
    {:noreply, options}
  end

  def run(options \\ []) do
    deliver = Keyword.get(options, :deliver, &LiquidsoapClient.deliver/3)

    Repo.transaction(fn ->
      requested = dispatch(Request, :requested, deliver)
      complementary = dispatch(ComplementaryTrack, :complementary, deliver)
      %{requested: requested, complementary: complementary}
    end)
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] -> {:error, :database_unavailable}
  end

  defp dispatch(schema, queue, deliver) do
    Repo.all(
      from(item in schema,
        where: item.status in ["ready", "queued"],
        order_by: item.id,
        lock: "FOR UPDATE SKIP LOCKED"
      )
    )
    |> Enum.count(fn item ->
      # The stable key survives rollback, lost ACKs, and either process restarting.
      case deliver.(queue, item.id, item.file_path) do
        {:ok, status} when status in ["queued", "played", "failed"] ->
          if status != item.status do
            item |> Ecto.Changeset.change(status: status) |> Repo.update!()
            Logger.info("programming_reconciled queue=#{queue} id=#{item.id} status=#{status}")
          end

          item.status == "ready" and status == "queued"

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end
end
