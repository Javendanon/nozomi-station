defmodule NozomiStation.ReleaseTest do
  use ExUnit.Case, async: false

  alias NozomiStation.{Release, Repo}

  test "release migrations can run repeatedly on an up-to-date database" do
    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      before = Repo.query!("SELECT version FROM schema_migrations ORDER BY version").rows
      assert :ok = Release.migrate()
      assert :ok = Release.migrate()
      assert Repo.query!("SELECT version FROM schema_migrations ORDER BY version").rows == before
    end)
  end
end
