defmodule NozomiStation.Programming.RefillWorker do
  use Oban.Worker, queue: :programming, max_attempts: 5, unique: [period: 55]

  alias NozomiStation.Programming.{ComplementaryQueue, Lastfm, Mood}

  @target 10

  @impl Oban.Worker
  def perform(_job), do: run()

  def run(options \\ []) do
    count = Keyword.get(options, :count, &ComplementaryQueue.available_count/0)
    profile = Keyword.get(options, :profile, &Mood.profile/0)
    source = Keyword.get(options, :source, &Lastfm.candidates/2)
    fill = Keyword.get(options, :fill, &ComplementaryQueue.fill/2)
    missing = max(@target - count.(), 0)

    if missing == 0 do
      {:ok, %{available: @target, prepared: 0}}
    else
      signals = profile.()
      origin = if signals.tracks == [], do: :seed, else: :mood

      with {:ok, candidates} <- source.(signals, missing * 3) do
        fill.(candidates, origin)
      end
    end
  end
end
