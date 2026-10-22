defmodule NozomiStation.Config.LiquidsoapRadioTest do
  @moduledoc """
  Guards the broadcast contract encoded in `config/liquidsoap/radio.liq`.

  The Docker verification scripts prove the audible behaviour, but they need a
  running Liquidsoap. These assertions catch an accidental edit to the script
  during `mix test`.
  """

  use ExUnit.Case, async: true

  @script Path.expand("../../config/liquidsoap/radio.liq", __DIR__)

  setup_all do
    %{script: File.read!(@script)}
  end

  test "crossfades music over four seconds", %{script: script} do
    assert script =~ ~s{crossfade(id="music", duration=4.0, fade_in=4.0, fade_out=4.0}
  end

  test "keeps requested tracks ahead of complementary ones at track boundaries", %{
    script: script
  } do
    assert script =~ "fallback(track_sensitive=true, [requested, complementary])"
  end

  test "observes the track change after the crossfade for the card and votes", %{script: script} do
    [before_crossfade, after_crossfade] = String.split(script, "crossfade(")

    refute before_crossfade =~ "radio.last_metadata()"
    assert after_crossfade =~ "radio.last_metadata() ?? []"
    assert after_crossfade =~ ~s{server.register(namespace="radio"}
  end
end
