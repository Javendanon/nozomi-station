defmodule NozomiStationWeb.IdentityLiveTest do
  use NozomiStationWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @alias "Nozomi-14-Tokyo-N700-Aoi"
  @claimant_id "11111111-1111-1111-1111-111111111111"

  test "restores and regenerates the display alias while preserving the shared listener ID", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#local-identity[phx-hook='LocalIdentity']")
    assert has_element?(view, "#regenerate-alias[disabled]")

    # The server owns the ID: the one in the browser payload is ignored.
    render_hook(view, "restore_identity", %{"id" => @claimant_id, "alias" => @alias})
    assert_push_event(view, "identity", %{id: id, alias: restored_alias})
    assert {:ok, id} == Ecto.UUID.cast(id)
    refute id == @claimant_id
    assert restored_alias == @alias
    assert has_element?(view, "#listener-alias[aria-live='polite']", @alias)
    assert has_element?(view, "#regenerate-alias:not([disabled])")

    view |> element("#regenerate-alias") |> render_click()
    assert_push_event(view, "identity", %{id: ^id, alias: new_alias})
    assert new_alias != @alias
    assert has_element?(view, "#listener-alias", new_alias)

    # A reconnect must not restore an outdated alias or replace the shared ID.
    render_hook(view, "restore_identity", %{"id" => Ecto.UUID.generate(), "alias" => @alias})
    assert_push_event(view, "identity", %{id: ^id, alias: ^new_alias})
  end

  test "keeps the shared listener ID when the browser loses its stored alias", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    render_hook(view, "restore_identity", %{"alias" => @alias})
    assert_push_event(view, "identity", %{id: id, alias: @alias})

    # Cleared storage sends no data; the session keeps votes attached to the same ID.
    render_hook(view, "restore_identity", %{})
    assert_push_event(view, "identity", %{id: ^id, alias: name})
    assert NozomiStation.Identity.Alias.valid?(name)
  end

  test "reports unavailable storage without losing the current identity", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    render_hook(view, "restore_identity", %{"alias" => @alias})
    assert_push_event(view, "identity", %{alias: @alias})

    render_hook(view, "identity_storage", %{available: false})
    assert has_element?(view, "#identity-storage-warning[role='status']")
    assert has_element?(view, "#listener-alias", @alias)
    assert has_element?(view, "#regenerate-alias:not([disabled])")

    render_hook(view, "identity_storage", %{available: "true"})
    assert has_element?(view, "#identity-storage-warning")

    render_hook(view, "identity_storage", %{available: true})
    refute has_element?(view, "#identity-storage-warning")
    assert has_element?(view, "#listener-alias", @alias)
  end

  test "shares one listener ID across LiveViews in the same session", %{conn: conn} do
    conn = get(conn, "/")
    {:ok, first, _html} = live(conn, "/")
    {:ok, second, _html} = live(recycle(conn), "/")

    render_hook(first, "restore_identity", %{"alias" => @alias})
    assert_push_event(first, "identity", %{id: id, alias: @alias})

    render_hook(second, "restore_identity", %{})
    assert_push_event(second, "identity", %{id: ^id, alias: name})
    assert NozomiStation.Identity.Alias.valid?(name)
  end

  test "ignores regeneration before restoration and repairs invalid local data", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    render_hook(view, "regenerate_alias", %{})
    assert has_element?(view, "#regenerate-alias[disabled]")

    render_hook(view, "restore_identity", %{"id" => "invalid", "alias" => "<script>bad</script>"})
    assert_push_event(view, "identity", %{id: id, alias: name})
    assert {:ok, id} == Ecto.UUID.cast(id)
    assert NozomiStation.Identity.Alias.valid?(name)
    assert has_element?(view, "#listener-alias", name)
  end
end
