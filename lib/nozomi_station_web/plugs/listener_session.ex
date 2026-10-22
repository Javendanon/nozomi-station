defmodule NozomiStationWeb.Plugs.ListenerSession do
  @moduledoc """
  Gives every browser a server-owned listener identifier.

  The identifier lives in the signed Phoenix session cookie, retained for one
  year across browser restarts. The browser can display it but never choose it.
  Votes and rate limits can therefore be keyed by it: minting a fresh UUID in a
  payload or clearing local storage keeps the same identity.
  """

  @behaviour Plug

  import Plug.Conn

  @session_key "listener_id"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case Ecto.UUID.cast(get_session(conn, @session_key)) do
      {:ok, _id} -> conn
      :error -> put_session(conn, @session_key, Ecto.UUID.generate())
    end
  end
end
