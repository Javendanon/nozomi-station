defmodule NozomiStation.Identity.Alias do
  @moduledoc "Generates railway display names; aliases are not listener identifiers."

  @services ~w(Nozomi Hikari Kodama Hayabusa Sakura)
  @stations ~w(Tokyo Kyoto Osaka Nagoya Sendai)
  @trains ~w(N700 E5 E6 E7 500)
  @colors ~w(Aoi Akane Midori Shiro Kuro)

  def generate(previous \\ nil) do
    candidate =
      Enum.join(
        [
          Enum.random(@services),
          Enum.random(1..999),
          Enum.random(@stations),
          Enum.random(@trains),
          Enum.random(@colors)
        ],
        "-"
      )

    if candidate == previous, do: generate(previous), else: candidate
  end

  def valid?(value) when is_binary(value) and byte_size(value) <= 64 do
    case String.split(value, "-") do
      [service, number, station, train, color] ->
        service in @services and station in @stations and train in @trains and
          color in @colors and Regex.match?(~r/\A[1-9][0-9]{0,2}\z/, number)

      _ ->
        false
    end
  end

  def valid?(_value), do: false
end
