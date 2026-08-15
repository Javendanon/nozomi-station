defmodule NozomiStation.Programming.Mood do
  import Ecto.Query

  alias NozomiStation.Repo
  alias NozomiStation.Requests.Request

  @reproducible_statuses ["ready", "queued", "played"]

  def recent do
    Repo.all(
      from(request in Request,
        where: request.status in @reproducible_statuses,
        order_by: [desc: request.id],
        limit: 20,
        select: %{title: request.title, artist: request.artist}
      )
    )
  end
end
