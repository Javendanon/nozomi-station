defmodule NozomiStation.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      NozomiStationWeb.Telemetry,
      NozomiStation.Repo,
      {Oban, Application.fetch_env!(:nozomi_station, Oban)},
      {DNSCluster, query: Application.get_env(:nozomi_station, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: NozomiStation.PubSub},
      {NozomiStation.Programming.NowPlaying,
       Application.get_env(:nozomi_station, :now_playing_options, [])},
      # Start a worker by calling: NozomiStation.Worker.start_link(arg)
      # {NozomiStation.Worker, arg},
      # Start to serve requests, typically the last entry
      NozomiStationWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: NozomiStation.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    NozomiStationWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
