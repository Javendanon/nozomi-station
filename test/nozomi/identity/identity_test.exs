defmodule NozomiStation.IdentityTest do
  use ExUnit.Case, async: true

  alias NozomiStation.Identity
  alias NozomiStation.Identity.Alias, as: RailwayAlias

  @id "43035f40-e32c-4eff-9db9-2742f7ac1eb9"
  @alias "Nozomi-14-Tokyo-N700-Aoi"

  test "restores the same local ID and alias" do
    assert Identity.restore(%{"id" => @id, "alias" => @alias}) == %{id: @id, alias: @alias}
  end

  test "creates a valid identity for missing or malformed browser data" do
    for data <- [nil, [], "invalid", %{}, %{"id" => 42}, %{"id" => "not-a-uuid"}] do
      identity = Identity.restore(data)
      assert {:ok, identity.id} == Ecto.UUID.cast(identity.id)
      assert RailwayAlias.valid?(identity.alias)
    end
  end

  test "repairs an invalid alias without resetting the local ID" do
    for value <- [nil, 42, "", "<script>alert(1)</script>", String.duplicate("x", 1_000)] do
      identity = Identity.restore(%{"id" => @id, "alias" => value})
      assert identity.id == @id
      assert RailwayAlias.valid?(identity.alias)
    end
  end

  test "regenerates the display alias without changing the voting identity" do
    identity = Identity.restore(%{"id" => @id, "alias" => @alias})

    for _ <- 1..100 do
      regenerated = Identity.regenerate(identity)
      assert regenerated.id == identity.id
      assert regenerated.alias != identity.alias
      assert RailwayAlias.valid?(regenerated.alias)
    end
  end
end
