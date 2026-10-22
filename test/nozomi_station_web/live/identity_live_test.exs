defmodule NozomiStationWeb.IdentityLiveTest do
  use NozomiStationWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @identity %{id: "43035f40-e32c-4eff-9db9-2742f7ac1eb9", alias: "Nozomi-14-Tokyo-N700-Aoi"}

  test "restores and regenerates the display alias while preserving the shared listener ID", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#local-identity[phx-hook='LocalIdentity']")
    assert has_element?(view, "#regenerate-alias[disabled]")

    render_hook(view, "restore_identity", @identity)
    assert_push_event(view, "identity", @identity)
    assert has_element?(view, "#listener-alias[aria-live='polite']", @identity.alias)
    assert has_element?(view, "#regenerate-alias:not([disabled])")

    view |> element("#regenerate-alias") |> render_click()
    assert_push_event(view, "identity", %{id: id, alias: name})
    assert id == @identity.id
    assert name != @identity.alias
    assert has_element?(view, "#listener-alias", name)

    # A reconnect must not restore an outdated alias or replace the current voting ID.
    render_hook(view, "restore_identity", %{id: Ecto.UUID.generate(), alias: @identity.alias})
    assert_push_event(view, "identity", %{id: ^id, alias: ^name})
  end

  test "reports unavailable storage without losing the current identity", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    render_hook(view, "restore_identity", @identity)
    assert_push_event(view, "identity", @identity)

    render_hook(view, "identity_storage", %{available: false})
    assert has_element?(view, "#identity-storage-warning[role='status']")
    assert has_element?(view, "#listener-alias", @identity.alias)
    assert has_element?(view, "#regenerate-alias:not([disabled])")

    render_hook(view, "identity_storage", %{available: true})
    refute has_element?(view, "#identity-storage-warning")
  end

  test "ignores regeneration before restoration and repairs invalid local data", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    render_hook(view, "regenerate_alias", %{})
    assert has_element?(view, "#regenerate-alias[disabled]")

    render_hook(view, "restore_identity", %{id: "invalid", alias: "<script>bad</script>"})
    assert_push_event(view, "identity", %{id: id, alias: name})
    assert {:ok, id} == Ecto.UUID.cast(id)
    assert NozomiStation.Identity.Alias.valid?(name)
    assert has_element?(view, "#listener-alias", name)
  end
end
