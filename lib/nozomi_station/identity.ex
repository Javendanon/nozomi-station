defmodule NozomiStation.Identity do
  @moduledoc """
  Accountless listener identity shared by chat and voting.

  The server owns `id`: `NozomiStationWeb.Plugs.ListenerSession` keeps it in the
  persistent signed Phoenix session cookie, so votes and rate limits keyed by
  `id` survive alias regeneration, local storage clearing, and browser restarts.
  The browser only restores the display `alias`, which is regenerable and never
  an identifier.

  Listener IDs are still not authentication: clearing or expiring the cookie
  creates a new identity, and any `id` a client sends is ignored.
  """

  alias NozomiStation.Identity.Alias, as: RailwayAlias

  def restore(data, id) when is_binary(id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      %{id: id, alias: restored_alias(alias_from(data))}
    else
      :error -> new()
    end
  end

  def restore(_data, _id), do: new()

  def regenerate(%{id: _id, alias: name} = identity) do
    %{identity | alias: RailwayAlias.generate(name)}
  end

  defp alias_from(data) when is_map(data), do: Map.get(data, "alias")
  defp alias_from(_data), do: nil

  defp restored_alias(name) do
    if RailwayAlias.valid?(name), do: name, else: RailwayAlias.generate()
  end

  defp new, do: %{id: Ecto.UUID.generate(), alias: RailwayAlias.generate()}
end
