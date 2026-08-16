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
    state = %{
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

  defp poll(state) do
    case state.current_path.() do
      {:ok, path} when path == state.path ->
        state

      {:ok, nil} ->
        publish(%{state | current: nil, path: nil}, nil)

      {:ok, path} ->
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
    current =
      case state.enrich.(track) do
        {:ok, details} -> Map.merge(track, details)
        {:error, _reason} -> track
      end

    Logger.info("now_playing_changed title=#{inspect(current.title)}")
    publish(%{state | current: current, path: path}, current)
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
      item -> Map.take(item, [:title, :artist, :duration_seconds])
    end
  end

  defp enrich(track), do: Lastfm.track_info(track.artist, track.title)
end
