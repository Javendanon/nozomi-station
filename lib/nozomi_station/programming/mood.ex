defmodule NozomiStation.Programming.Mood do
  import Ecto.Query

  alias NozomiStation.Programming.Lastfm
  alias NozomiStation.Repo
  alias NozomiStation.Requests.Request

  @reproducible_statuses ["ready", "queued", "played"]
  @window 20
  @signal_limit 10

  def recent do
    Repo.all(
      from(request in Request,
        where: request.status in @reproducible_statuses,
        order_by: [desc: request.id],
        limit: @window,
        select: %{title: request.title, artist: request.artist}
      )
    )
  end

  def profile(options \\ []) do
    tracks = Keyword.get(options, :mood, &recent/0).()
    info = Keyword.get(options, :info, &Lastfm.track_info/3)

    %{tracks: tracks, tags: tags(tracks, info)}
  end

  # ponytail: tags are refetched on every refill; cache them per artist/title if Last.fm quota matters.
  defp tags(tracks, info) do
    tracks
    |> Enum.uniq_by(&{&1.artist, &1.title})
    |> Enum.flat_map(fn track -> track_tags(info.(track.artist, track.title)) end)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {tag, count} -> {-count, tag} end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.take(@signal_limit)
  end

  defp track_tags({:ok, %{tags: tags}}) when is_list(tags), do: tags
  defp track_tags(_), do: []
end
