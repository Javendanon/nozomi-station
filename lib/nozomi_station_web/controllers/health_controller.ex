defmodule NozomiStationWeb.HealthController do
  use NozomiStationWeb, :controller

  def show(conn, _params) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case NozomiStation.Repo.query("SELECT 1", [], timeout: 1_000) do
      {:ok, _result} -> json(conn, %{status: "ok"})
      {:error, _reason} -> unavailable(conn)
    end
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] -> unavailable(conn)
  end

  defp unavailable(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(:service_unavailable)
    |> json(%{status: "unavailable"})
  end
end
