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
    assert has_element?(view, "#neo-journey")
    assert has_element?(view, "#signal-wave[aria-hidden='true']")
    assert has_element?(view, "#station-side > #volume-controller[phx-hook='VolumeControl']")
    assert has_element?(view, "#volume-control[type='range'][min='0'][max='1'][step='0.01']")
    assert has_element?(view, "label[for='volume-control']", "Línea de volumen")
  end

  test "updates two listeners with the same current track", %{conn: conn} do
    {:ok, first, _html} = live(conn, "/")
    {:ok, second, _html} = live(recycle(conn), "/")

    Phoenix.PubSub.broadcast(
      NozomiStation.PubSub,
      "now_playing",
      {:now_playing,
       %{
         title: "Blue Monday",
         artist: "New Order",
         duration_seconds: 451,
         album: "Substance",
         cover_url: "https://lastfm-img.freetls.fastly.net/i/u/300x300/cover.jpg",
         tags: ["new wave", "80s"],
         summary: "A classic.",
         listener_message: "Para quienes siguen despiertos"
       }}
    )

    assert has_element?(first, "#now-playing-title", "Blue Monday")
    assert has_element?(second, "#now-playing-title", "Blue Monday")
    assert has_element?(first, "#now-playing-album", "Substance")
    assert has_element?(first, "#now-playing-cover[src*='lastfm-img.freetls.fastly.net']")
    assert has_element?(first, "#now-playing-summary", "A classic.")
    assert has_element?(first, "#listener-message", "Para quienes siguen despiertos")
  end

  test "hides missing optional metadata without removing the player", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    send(view.pid, {
      :now_playing,
      %{title: "Unknown", artist: "Artist", duration_seconds: 180}
    })

    assert has_element?(view, "#now-playing-title", "Unknown")
    refute has_element?(view, "#now-playing-cover")
    refute has_element?(view, "#now-playing-album")
    refute has_element?(view, "#now-playing-summary")
    assert has_element?(view, "#live-audio")
  end
end
