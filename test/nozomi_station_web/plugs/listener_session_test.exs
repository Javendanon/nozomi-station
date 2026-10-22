defmodule NozomiStationWeb.Plugs.ListenerSessionTest do
  use NozomiStationWeb.ConnCase, async: true

  alias NozomiStationWeb.Plugs.ListenerSession

  test "keeps one server-owned listener ID across requests", %{conn: conn} do
    conn = get(conn, "/")
    id = get_session(conn, "listener_id")
    assert {:ok, id} == Ecto.UUID.cast(id)

    next = get(recycle(conn), "/")
    assert get_session(next, "listener_id") == id
  end

  test "replaces a client-tampered listener ID", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{"listener_id" => "chosen-by-the-client"})
      |> get("/")

    id = get_session(conn, "listener_id")

    assert {:ok, id} == Ecto.UUID.cast(id)
    refute id == "chosen-by-the-client"
  end

  test "rejects a tampered persistent session cookie", %{conn: conn} do
    conn = get(conn, "/")
    id = get_session(conn, "listener_id")
    cookie = Map.fetch!(conn.resp_cookies, "_nozomi_station_key")

    returning =
      build_conn()
      |> put_req_cookie("_nozomi_station_key", cookie.value <> "tampered")
      |> get("/")

    new_id = get_session(returning, "listener_id")
    assert {:ok, new_id} == Ecto.UUID.cast(new_id)
    refute new_id == id
  end

  test "leaves an existing session ID untouched", %{conn: conn} do
    id = Ecto.UUID.generate()

    conn =
      conn |> init_test_session(%{"listener_id" => id}) |> ListenerSession.call([])

    assert get_session(conn, "listener_id") == id
  end
end
