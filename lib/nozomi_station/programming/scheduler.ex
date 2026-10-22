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

    requested = dispatch(Request, :requested, deliver)
    complementary = dispatch(ComplementaryTrack, :complementary, deliver)

    {:ok, %{requested: requested, complementary: complementary}}
  rescue
    _error in DBConnection.ConnectionError -> {:error, :database_unavailable}
  end

  defp dispatch(schema, queue, deliver) do
    # Control I/O stays outside the database transactions: one slow or failing
    # delivery must not hold row locks or block its siblings.
    schema
    |> candidates()
    |> Enum.count(fn item -> dispatch_item(schema, queue, item, deliver) end)
  end

  defp candidates(schema) do
    Repo.all(
      from(item in schema,
        where: item.status in ["ready", "queued"],
        order_by: item.id
      )
    )
  end

  defp dispatch_item(schema, queue, item, deliver) do
    # The stable key survives rollback, lost ACKs, and either process restarting.
    case deliver.(queue, item.id, item.file_path) do
      {:ok, status} when status in ["queued", "played"] ->
        reconcile(schema, queue, item, status)

      {:ok, "failed"} ->
        # A failed receipt is retried on the next poll, so the row keeps its
        # status instead of being dropped as a terminal database failure.
        Logger.warning("programming_delivery_unavailable queue=#{queue} id=#{item.id}")
        false

      {:error, reason} ->
        Logger.warning(
          "programming_dispatch_failed queue=#{queue} id=#{item.id} reason=#{inspect(reason)}"
        )

        false
    end
  end

  defp reconcile(schema, queue, item, status) do
    # A short transaction per row: a bad sibling cannot roll back committed work.
    {:ok, dispatched} =
      Repo.transaction(fn ->
        case Repo.one(
               from(current in schema,
                 where: current.id == ^item.id and current.status in ["ready", "queued"],
                 lock: "FOR UPDATE SKIP LOCKED"
               )
             ) do
          nil ->
            false

          current ->
            if current.status != status do
              current |> Ecto.Changeset.change(status: status) |> Repo.update!()

              Logger.info(
                "programming_reconciled queue=#{queue} id=#{current.id} status=#{status}"
              )
            end

            current.status == "ready" and status == "queued"
        end
      end)

    dispatched
  end
end
