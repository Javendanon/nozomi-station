defmodule NozomiStation.Programming.ComplementaryQueue do
  import Ecto.Query

  require Logger

  alias NozomiStation.Media.{Preparer, Resolver}
  alias NozomiStation.Programming.ComplementaryTrack
  alias NozomiStation.Repo

  @available_statuses ["preparing", "ready", "queued"]
  @target 10

  def fill(candidates, origin, options \\ []) do
    target = Keyword.get(options, :target, @target)
    resolver = Keyword.get(options, :resolver, &resolve/1)
    prepare = Keyword.get(options, :prepare, &Preparer.prepare/2)
    initial = %{available: available_count(), prepared: 0, discarded: 0}

    result =
      Enum.reduce_while(candidates, initial, fn candidate, counts ->
        if counts.available >= target do
          {:halt, counts}
        else
          {:cont, prepare_candidate(candidate, origin, resolver, prepare, counts)}
        end
      end)

    Logger.info(
      "complementary_margin available=#{result.available} prepared=#{result.prepared} discarded=#{result.discarded}"
    )

    {:ok, result}
  end

  def available_count do
    Repo.aggregate(
      from(track in ComplementaryTrack, where: track.status in @available_statuses),
      :count
    )
  end

  defp prepare_candidate(candidate, origin, resolver, prepare, counts) do
    with {:ok, resolved} <- resolver.(candidate),
         {:ok, track} <- reserve(resolved, origin),
         {:ok, path} <- prepare_track(track, prepare),
         {:ok, _track} <- persist(track, %{status: "ready", file_path: path}) do
      %{counts | available: counts.available + 1, prepared: counts.prepared + 1}
    else
      {:error, %Ecto.Changeset{}} -> discard(counts)
      {:error, reason, track} -> fail(track, reason, counts)
      {:error, _reason} -> discard(counts)
    end
  end

  defp reserve(resolved, origin) do
    attrs = resolved |> Map.put(:origin, Atom.to_string(origin)) |> Map.put(:status, "preparing")
    %ComplementaryTrack{} |> ComplementaryTrack.changeset(attrs) |> Repo.insert()
  end

  defp persist(track, attrs), do: track |> ComplementaryTrack.changeset(attrs) |> Repo.update()

  defp prepare_track(track, prepare) do
    case prepare.(track.youtube_id, {:complementary, track.id}) do
      {:ok, path} -> {:ok, path}
      {:error, reason} -> {:error, reason, track}
    end
  end

  defp fail(track, reason, counts) do
    persist(track, %{status: "failed"})
    Logger.warning("complementary_candidate_failed id=#{track.id} reason=#{inspect(reason)}")
    discard(counts)
  end

  defp discard(counts), do: %{counts | discarded: counts.discarded + 1}

  defp resolve(candidate) do
    Resolver.resolve_search("#{candidate.artist} #{candidate.title}")
  end
end
