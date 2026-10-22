defmodule NozomiStation.Slack.Client do
  @post_message "https://slack.com/api/chat.postMessage"
  @users_info "https://slack.com/api/users.info"

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

  def display_name(user, request \\ &Req.request/1)

  def display_name(user, request) when is_binary(user) do
    options = [
      method: :get,
      url: @users_info,
      auth: {:bearer, Application.fetch_env!(:nozomi_station, :slack_bot_token)},
      params: [user: user],
      redirect: false,
      receive_timeout: 10_000
    ]

    case request.(options) do
      {:ok, %Req.Response{status: 200, body: %{"ok" => true, "user" => profile}}} ->
        visible_name(profile)

      _ ->
        {:error, :slack_unavailable}
    end
  end

  def display_name(_user, _request), do: {:error, :invalid_user}

  # Slack exposes the user-chosen display name and the real name; IDs and handles are never names.
  defp visible_name(profile) when is_map(profile) do
    [get_in(profile, ["profile", "display_name"]), get_in(profile, ["profile", "real_name"])]
    |> Enum.find_value(&present/1)
    |> case do
      nil -> {:error, :display_name_missing}
      name -> {:ok, name}
    end
  end

  defp visible_name(_profile), do: {:error, :display_name_missing}

  defp present(name) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_name), do: nil
end
