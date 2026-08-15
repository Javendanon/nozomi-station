defmodule NozomiStation.Repo do
  use Ecto.Repo,
    otp_app: :nozomi_station,
    adapter: Ecto.Adapters.Postgres
end
