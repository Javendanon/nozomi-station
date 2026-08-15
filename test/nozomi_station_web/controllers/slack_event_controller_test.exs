defmodule NozomiStationWeb.SlackEventControllerTest do
  use NozomiStationWeb.ConnCase, async: true

  @secret "test-signing-secret"

  test "returns a challenge only for a signed current request", %{conn: conn} do
    body = Jason.encode!(%{type: "url_verification", challenge: "ready"})

    conn = signed_post(conn, body)

    assert json_response(conn, 200) == %{"challenge" => "ready"}
  end

  test "rejects an invalid Slack signature", %{conn: conn} do
    body = Jason.encode!(%{type: "url_verification", challenge: "ready"})

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header(
        "x-slack-request-timestamp",
        Integer.to_string(System.system_time(:second))
      )
      |> put_req_header("x-slack-signature", "v0=invalid")
      |> post("/slack/events", body)

    assert response(conn, 401)
  end

  defp signed_post(conn, body) do
    timestamp = Integer.to_string(System.system_time(:second))

    signature =
      "v0=" <>
        (:crypto.mac(:hmac, :sha256, @secret, "v0:#{timestamp}:#{body}")
         |> Base.encode16(case: :lower))

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-slack-request-timestamp", timestamp)
    |> put_req_header("x-slack-signature", signature)
    |> post("/slack/events", body)
  end
end
