defmodule NozomiStation.Programming.SchedulerWorker do
  use Oban.Worker, queue: :programming, max_attempts: 10, unique: [period: 55]

  alias NozomiStation.Programming.Scheduler

  @impl Oban.Worker
  def perform(_job) do
    case Scheduler.run() do
      {:ok, counts} -> {:ok, counts}
      {:error, reason} -> {:error, reason}
    end
  end
end
