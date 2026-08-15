defmodule NozomiStationWeb.SlackEventControllerTest do
  use NozomiStationWeb.ConnCase, async: true

  alias NozomiStation.Slack.RequestWorker

  @secret "test-signing-secret"

  test "returns a challenge only for a signed current request", %{conn: conn} do
    body = Jason.encode!(%{type: "url_verification", challenge: "ready"})

    conn = signed_post(conn, body)

    assert json_response(conn, 200) == %{"challenge" => "ready"}
  end

  test "persists and enqueues an event callback once", %{conn: conn} do
    body =
      Jason.encode!(%{
        type: "event_callback",
        event_id: "Ev-controller",
        event: %{type: "message", text: "https://youtu.be/track"}
      })

    assert signed_post(conn, body).status == 202
    assert_enqueued(worker: RequestWorker, args: %{"event_id" => "Ev-controller"})

    assert signed_post(build_conn(), body).status == 202
    assert [_job] = all_enqueued(worker: RequestWorker)
  end

  test "rejects a signed unsupported payload", %{conn: conn} do
    conn = signed_post(conn, Jason.encode!(%{type: "unsupported"}))
    assert response(conn, 400)
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
