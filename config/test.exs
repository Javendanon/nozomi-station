import Config

config :nozomi_station, NozomiStation.Repo,
  username: "postgres",
  password: "postgres",
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  database: "nozomi_station_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :nozomi_station, Oban, testing: :manual
config :nozomi_station, :slack_signing_secret, "test-signing-secret"
config :nozomi_station, :slack_bot_token, "test-bot-token"
config :nozomi_station, :slack_channel_id, "C01"
config :nozomi_station, :youtube_api_key, "test-youtube-key"
config :nozomi_station, :spotify_client_id, "test-spotify-id"
config :nozomi_station, :spotify_client_secret, "test-spotify-secret"
config :nozomi_station, :lastfm_api_key, "test-lastfm-key"

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :nozomi_station, NozomiStationWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "rLXlM+cfrEsDGV23dS72MlM/i33uxhHSsPMqOW7AYh2eayjkOtWv00KI9bgjs6IF",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
