defmodule NozomiStationWeb.HealthControllerTest do
  use NozomiStationWeb.ConnCase, async: true

  test "readiness responds without a session when the database is available", %{conn: conn} do
    conn = get(conn, ~p"/health")

    assert json_response(conn, 200) == %{"status" => "ok"}
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "set-cookie") == []
  end
end
