defmodule NozomiStationWeb.RadioLiveTest do
  use NozomiStationWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "shows an accessible control to join the live broadcast", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#join-live", "Subir al tren")
  end

  test "exposes the live HLS stream while it connects", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#radio-player[data-stream='/hls/live.m3u8']")
    assert has_element?(view, "#stream-status", "Conectando")
  end
end
