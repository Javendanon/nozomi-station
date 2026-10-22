defmodule NozomiStation.Identity.AliasTest do
  use ExUnit.Case, async: true

  alias NozomiStation.Identity.Alias, as: RailwayAlias

  test "generates an alias containing a Japanese service, number, station, train, and color" do
    for _ <- 1..100 do
      assert RailwayAlias.generate() =~
               ~r/\A(Nozomi|Hikari|Kodama|Hayabusa|Sakura)-[1-9][0-9]{0,2}-(Tokyo|Kyoto|Osaka|Nagoya|Sendai)-(N700|E5|E6|E7|500)-(Aoi|Akane|Midori|Shiro|Kuro)\z/
    end
  end

  test "rejects aliases outside the generated vocabulary and number range" do
    for value <- [
          nil,
          [],
          "Nozomi-0-Tokyo-N700-Aoi",
          "Nozomi-1000-Tokyo-N700-Aoi",
          "Nozomi-01-Tokyo-N700-Aoi",
          "Unknown-14-Tokyo-N700-Aoi",
          "Nozomi-14-London-N700-Aoi",
          "Nozomi-14-Tokyo-TGV-Aoi",
          "Nozomi-14-Tokyo-N700-Blue",
          "Nozomi-14-Tokyo-N700-Aoi\n",
          "Nozomi-14-Tokyo-N700-Aoi-extra"
        ] do
      refute RailwayAlias.valid?(value)
    end

    assert RailwayAlias.valid?("Nozomi-1-Tokyo-N700-Aoi")
    assert RailwayAlias.valid?("Sakura-999-Sendai-500-Kuro")
  end
end
