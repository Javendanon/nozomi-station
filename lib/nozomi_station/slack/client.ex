defmodule NozomiStation.Slack.Client do
  @post_message "https://slack.com/api/chat.postMessage"

  def reply(channel, thread_ts, text, request \\ &Req.request/1) do
    options = [
      method: :post,
      url: @post_message,
      auth: {:bearer, Application.fetch_env!(:nozomi_station, :slack_bot_token)},
      json: %{channel: channel, thread_ts: thread_ts, text: text},
      redirect: false,
      receive_timeout: 10_000
    ]

    case request.(options) do
      {:ok, %Req.Response{status: 200, body: %{"ok" => true}}} -> :ok
      _ -> {:error, :slack_unavailable}
    end
  end
end
