defmodule NozomiStation.Release do
  @moduledoc "Database tasks for releases without Mix or application workers."

  def migrate do
    Enum.each(Application.fetch_env!(:nozomi_station, :ecto_repos), fn repo ->
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end)
  end
end
