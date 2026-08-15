defmodule NozomiStationWeb.Plugs.VerifySlackSignature do
  import Plug.Conn

  alias NozomiStation.Slack.Signature

  def init(opts), do: opts

  def call(conn, _opts) do
    with [timestamp] <- get_req_header(conn, "x-slack-request-timestamp"),
         [signature] <- get_req_header(conn, "x-slack-signature"),
         secret when is_binary(secret) <-
           Application.get_env(:nozomi_station, :slack_signing_secret),
         true <- Signature.valid?(conn.assigns[:raw_body] || "", timestamp, signature, secret) do
      conn
    else
      _ -> conn |> send_resp(:unauthorized, "") |> halt()
    end
  end
end
