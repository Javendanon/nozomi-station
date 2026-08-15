defmodule NozomiStationWeb.PageController do
  use NozomiStationWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
