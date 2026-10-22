defmodule NozomiStation.Programming.NowPlaying do
  use GenServer

  import Ecto.Query

  require Logger

  alias NozomiStation.Programming.{ComplementaryTrack, Lastfm, LiquidsoapClient}
  alias NozomiStation.Repo
  alias NozomiStation.Requests.Request

  @topic "now_playing"

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: Keyword.get(options, :name, __MODULE__))
  end

  def subscribe do
    Phoenix.PubSub.subscribe(NozomiStation.PubSub, @topic)
  end

  def current(server \\ __MODULE__), do: GenServer.call(server, :current)

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)

    state = %{
      enrichment: nil,
      current: nil,
      path: nil,
      topic: Keyword.get(options, :topic, @topic),
      poll_interval: Keyword.get(options, :poll_interval, 2_000),
      current_path: Keyword.get(options, :current_path, &LiquidsoapClient.current_path/0),
      lookup: Keyword.get(options, :lookup, &lookup/1),
      enrich: Keyword.get(options, :enrich, &enrich/1)
    }

    if Keyword.get(options, :poll, true), do: send(self(), :poll)
    {:ok, state}
  end

  @impl true
  def handle_call(:current, _from, state), do: {:reply, state.current, state}

  @impl true
  def handle_info(:poll, state) do
    state = poll(state)
    Process.send_after(self(), :poll, state.poll_interval)
    {:noreply, state}
  end

  def handle_info({ref, result}, %{enrichment: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    state = %{state | enrichment: nil}

    current =
      case result do
        {:ok, details} -> Map.merge(state.current, details)
        {:error, _reason} -> state.current
      end

    if current == state.current do
      {:noreply, state}
    else
      {:noreply, publish(%{state | current: current}, current)}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{enrichment: %Task{ref: ref}} = state) do
    Logger.warning("now_playing_enrichment_failed reason=#{inspect(reason)}")
    {:noreply, %{state | enrichment: nil}}
  end

  def handle_info({ref, _result}, state) when is_reference(ref), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    cancel_enrichment(state)
    :ok
  end

  defp poll(state) do
    case state.current_path.() do
      {:ok, path} when path == state.path ->
        state

      {:ok, nil} ->
        state = cancel_enrichment(state)
        publish(%{state | current: nil, path: nil}, nil)

      {:ok, path} ->
        state = cancel_enrichment(state)

        case state.lookup.(path) do
          nil -> state
          track -> publish_track(state, path, track)
        end

      {:error, reason} ->
        Logger.warning("now_playing_poll_failed reason=#{inspect(reason)}")
        state
    end
  end

  defp publish_track(state, path, track) do
    enrich = state.enrich
    task = Task.Supervisor.async_nolink(__MODULE__.TaskSupervisor, fn -> enrich.(track) end)

    Logger.info("now_playing_changed title=#{inspect(track.title)}")
    publish(%{state | current: track, path: path, enrichment: task}, track)
  end

  defp cancel_enrichment(%{enrichment: nil} = state), do: state

  defp cancel_enrichment(state) do
    Task.shutdown(state.enrichment, :brutal_kill)
    %{state | enrichment: nil}
  end

  defp publish(state, current) do
    Phoenix.PubSub.broadcast(NozomiStation.PubSub, state.topic, {:now_playing, current})
    state
  end

  defp lookup(path) do
    find_by_path(Request, path) || find_by_path(ComplementaryTrack, path)
  end

  defp find_by_path(schema, path) do
    case Repo.one(from(item in schema, where: item.file_path == ^path, limit: 1)) do
      nil -> nil
      item -> Map.take(item, [:title, :artist, :duration_seconds, :listener_message])
    end
  end

  defp enrich(track), do: Lastfm.track_info(track.artist, track.title)
end
