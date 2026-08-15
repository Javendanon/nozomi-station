defmodule NozomiStationWeb.Router do
  use NozomiStationWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {NozomiStationWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :slack do
    plug NozomiStationWeb.Plugs.VerifySlackSignature
  end

  scope "/", NozomiStationWeb do
    pipe_through :browser

    live "/", RadioLive
  end

  scope "/slack", NozomiStationWeb do
    pipe_through [:api, :slack]

    post "/events", SlackEventController, :create
  end
end
