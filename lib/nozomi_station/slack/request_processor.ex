defmodule NozomiStation.Slack.RequestProcessor do
  @url ~r{https://[^\s>|]+}

  def process(%{"event" => event}, deps) do
    if processable?(event, Keyword.fetch!(deps, :channel)) do
      event["text"]
      |> links()
      |> Enum.reduce_while(:ok, &process_link(&1, event, deps, &2))
    else
      :ok
    end
  end

  defp process_link(url, event, deps, _result) do
    resolver = Keyword.fetch!(deps, :resolver)
    prepare = Keyword.fetch!(deps, :prepare)
    reply = Keyword.fetch!(deps, :reply)

    requester = %{
      slack_user: event["user"],
      slack_channel: event["channel"],
      thread_ts: event["ts"]
    }

    with {:ok, track} <- resolver.(url),
         {:ok, request, position} <- prepare.(track, requester),
         :ok <-
           reply.(
             event["channel"],
             event["ts"],
             "Aceptada: #{request.title} · posición #{position}"
           ) do
      {:cont, :ok}
    else
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp processable?(event, channel) do
    event["type"] == "message" and event["channel"] == channel and
      not Map.has_key?(event, "bot_id") and not Map.has_key?(event, "subtype")
  end

  defp links(text) when is_binary(text), do: @url |> Regex.scan(text) |> List.flatten()
  defp links(_), do: []
end
