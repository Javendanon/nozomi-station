defmodule NozomiStation.Identity.AliasTest do
  use ExUnit.Case, async: true

  alias NozomiStation.Identity.Alias, as: RailwayAlias

  test "generates an alias containing a Japanese service, number, station, train, and color" do
    for _ <- 1..100 do
      assert RailwayAlias.generate() =~
               ~r/\A(Nozomi|Hikari|Kodama|Hayabusa|Sakura)-[1-9][0-9]{0,2}-(Tokyo|Kyoto|Osaka|Nagoya|Sendai)-(N700|E5|E6|E7|500)-(Aoi|Akane|Midori|Shiro|Kuro)\z/
    end
  end
end
