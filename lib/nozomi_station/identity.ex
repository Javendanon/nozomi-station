defmodule NozomiStation.Identity do
  @moduledoc """
  Browser-local listener identity shared by chat and voting, without accounts.

  Key votes and rate limits by `id`, never by the regenerable display `alias`.
  Local IDs are not authentication: clearing storage or using another browser
  can create a new identity.
  """

  alias NozomiStation.Identity.Alias, as: RailwayAlias

  def restore(%{"id" => id} = data) when is_binary(id) and byte_size(id) == 36 do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        name = Map.get(data, "alias")
        %{id: id, alias: if(RailwayAlias.valid?(name), do: name, else: RailwayAlias.generate())}

      :error ->
        new()
    end
  end

  def restore(_data), do: new()

  def regenerate(%{id: _id, alias: name} = identity) do
    %{identity | alias: RailwayAlias.generate(name)}
  end

  defp new, do: %{id: Ecto.UUID.generate(), alias: RailwayAlias.generate()}
end
