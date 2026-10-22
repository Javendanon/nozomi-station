defmodule NozomiStation.Slack.RequestProcessor do
  require Logger

  @url ~r{https://[^\s>|]+}
  @slack_link ~r{<https://[^>]+>}
  @trailing_url_punctuation [".", ",", "!", "?", ":", ";"]
  @permanent_errors [:duplicate, :invalid_duration, :invalid_url, :not_playable, :unsupported_url]

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

    result =
      with {:ok, track} <- resolver.(url),
           {:ok, request, position} <- prepare.(track, requester(event)) do
        {:accepted, track, request, position}
      end

    handle_result(result, event, reply)
  end

  defp handle_result({:accepted, track, request, position}, event, reply) do
    message = "Aceptada: #{request.title} · posición #{position}"

    case reply.(event["channel"], event["ts"], message) do
      :ok ->
        Logger.info("request_ready youtube_id=#{track.youtube_id} position=#{position}")
        {:cont, :ok}

      error ->
        {:halt, error}
    end
  end

  defp handle_result({:error, reason}, event, reply) when reason in @permanent_errors do
    Logger.info("request_rejected reason=#{reason}")

    message =
      if reason == :duplicate,
        do: "Rechazada: canción duplicada",
        else: "Rechazada: la canción no es reproducible"

    case reply.(event["channel"], event["ts"], message) do
      :ok -> {:cont, :ok}
      error -> {:halt, error}
    end
  end

  defp handle_result({:error, reason}, _event, _reply) do
    Logger.warning("request_retry reason=#{reason}")
    {:halt, {:error, reason}}
  end

  defp requester(event) do
    %{
      slack_user: event["user"],
      slack_channel: event["channel"],
      thread_ts: event["ts"],
      listener_message: listener_message(event["text"])
    }
  end

  defp processable?(event, channel) do
    event["type"] == "message" and event["channel"] == channel and
      not Map.has_key?(event, "bot_id") and not Map.has_key?(event, "subtype")
  end

  defp links(text) when is_binary(text) do
    @url
    |> Regex.scan(text)
    |> List.flatten()
    |> Enum.map(&trim_url/1)
  end

  defp links(_), do: []

  defp trim_url(url) do
    Enum.reduce(@trailing_url_punctuation, url, &String.trim_trailing(&2, &1))
  end

  defp listener_message(text) when is_binary(text) do
    message =
      text
      |> String.replace(@slack_link, " ")
      |> String.replace(@url, " ")
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()
      |> String.slice(0, 280)

    if message =~ ~r/[\p{L}\p{N}]/u, do: message
  end

  defp listener_message(_), do: nil
end
