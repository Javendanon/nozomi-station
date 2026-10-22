defmodule NozomiStation.IdentityTest do
  use ExUnit.Case, async: true

  alias NozomiStation.Identity
  alias NozomiStation.Identity.Alias, as: RailwayAlias

  @id "43035f40-e32c-4eff-9db9-2742f7ac1eb9"
  @other_id "3f2c8f1e-6d1a-4c11-9f0a-6d3a1e5b7c22"
  @alias "Nozomi-14-Tokyo-N700-Aoi"

  test "restores the session ID and the browser alias" do
    assert Identity.restore(%{"id" => @id, "alias" => @alias}, @id) == %{id: @id, alias: @alias}
  end

  test "ignores any client-supplied ID in favour of the session ID" do
    for data <- [
          %{"id" => @other_id, "alias" => @alias},
          %{"id" => "not-a-uuid", "alias" => @alias}
        ] do
      assert Identity.restore(data, @id) == %{id: @id, alias: @alias}
    end

    identity = Identity.restore(%{}, @id)
    assert identity.id == @id
    assert RailwayAlias.valid?(identity.alias)
  end

  test "creates a valid identity when the session ID is missing or malformed" do
    for {data, id} <- [
          {nil, nil},
          {[], @id},
          {"invalid", @id},
          {%{}, 42},
          {%{}, "not-a-uuid"},
          {%{"id" => @id}, String.duplicate("x", 36)},
          {%{"id" => @id}, <<0::128>>}
        ] do
      identity = Identity.restore(data, id)
      assert {:ok, identity.id} == Ecto.UUID.cast(identity.id)
      assert RailwayAlias.valid?(identity.alias)
    end
  end

  test "ignores malformed browser data" do
    for data <- [nil, [], "invalid", 42] do
      identity = Identity.restore(data, @id)
      assert identity.id == @id
      assert RailwayAlias.valid?(identity.alias)
    end
  end

  test "repairs an invalid alias without resetting the session ID" do
    for value <- [nil, 42, "", "<script>alert(1)</script>", String.duplicate("x", 1_000)] do
      identity = Identity.restore(%{"id" => @id, "alias" => value}, @id)
      assert identity.id == @id
      assert RailwayAlias.valid?(identity.alias)
    end
  end

  test "regenerates the display alias without changing the voting identity" do
    identity = Identity.restore(%{"alias" => @alias}, @id)

    for _ <- 1..100 do
      regenerated = Identity.regenerate(identity)
      assert regenerated.id == identity.id
      assert regenerated.alias != identity.alias
      assert RailwayAlias.valid?(regenerated.alias)
    end
  end
end
