defmodule NozomiStation.Identity.Alias do
  @moduledoc "Generates railway display names; aliases are not listener identifiers."

  @services ~w(Nozomi Hikari Kodama Hayabusa Sakura)
  @stations ~w(Tokyo Kyoto Osaka Nagoya Sendai)
  @trains ~w(N700 E5 E6 E7 500)
  @colors ~w(Aoi Akane Midori Shiro Kuro)

  def generate do
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
  end
end
