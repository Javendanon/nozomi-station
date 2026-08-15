defmodule NozomiStationWeb.RawBodyReader do
  def read_body(conn, opts) do
    with {:ok, body, conn} <- Plug.Conn.read_body(conn, opts) do
      raw_body = (conn.assigns[:raw_body] || "") <> body
      {:ok, body, Plug.Conn.assign(conn, :raw_body, raw_body)}
    end
  end
end
