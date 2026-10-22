defmodule NozomiStation.Programming.LiquidsoapClient do
  @queues [:requested, :complementary]
  @timeout 1_000

  def deliver(queue, id, path), do: deliver(queue, id, path, &command/1, [])

  def deliver(queue, id, path, command, options)
      when queue in @queues and is_integer(id) and id > 0 do
    key = "#{queue}-#{id}"

    with {:ok, liquidsoap_path} <- to_liquidsoap_path(path, options),
         {:ok, [receipt]} <- command.("radio.enqueue #{key} #{queue} #{liquidsoap_path}"),
         {:ok, %{"key" => ^key, "state" => state, "position" => position}} <-
           Jason.decode(receipt),
         true <- state in ["queued", "playing", "played", "failed"],
         true <- is_number(position) and position >= 0 do
      {:ok, if(state == "playing", do: "queued", else: state)}
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _ -> {:error, :invalid_control_response}
    end
  end

  def push(queue, path), do: push(queue, path, &command/1, [])

  def push(queue, path, command, options) when queue in @queues do
    with {:ok, liquidsoap_path} <- to_liquidsoap_path(path, options),
         {:ok, [_request_id]} <- command.("#{queue}.push #{liquidsoap_path}") do
      :ok
    else
      {:ok, _response} -> {:error, :invalid_control_response}
      error -> error
    end
  end

  def current_path, do: current_path(&command/1, [])

  def current_path(command, options) do
    with {:ok, [snapshot]} <- command.("radio.current"),
         {:ok, %{"key" => key, "path" => path}} when is_binary(key) and is_binary(path) <-
           Jason.decode(snapshot) do
      if key == "", do: {:ok, nil}, else: from_liquidsoap_path(path, options)
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _ -> {:error, :invalid_control_response}
    end
  end

  defp command(value) do
    host = Application.get_env(:nozomi_station, :liquidsoap_host, "127.0.0.1")
    port = Application.get_env(:nozomi_station, :liquidsoap_port, 1234)

    with {:ok, socket} <-
           :gen_tcp.connect(String.to_charlist(host), port, [:binary, active: false], @timeout) do
      try do
        with :ok <- :gen_tcp.send(socket, value <> "\nquit\n"),
             {:ok, response} <- receive_response(socket, "") do
          parse_response(response)
        end
      after
        :gen_tcp.close(socket)
      end
    end
  end

  defp receive_response(socket, response) do
    if String.contains?(response, "\r\nEND\r\n") do
      {:ok, response}
    else
      case :gen_tcp.recv(socket, 0, @timeout) do
        {:ok, data} -> receive_response(socket, response <> data)
        {:error, :closed} when response != "" -> {:ok, response}
        error -> error
      end
    end
  end

  defp parse_response(response) do
    lines =
      response
      |> String.replace("\r", "")
      |> String.split("\n", trim: true)
      |> Enum.take_while(&(&1 != "END"))

    case lines do
      ["ERROR: " <> _ | _] -> {:error, :control_rejected}
      _ -> {:ok, lines}
    end
  end

  defp to_liquidsoap_path(path, options) do
    translate(path, media_dir(options), liquidsoap_media_dir(options))
  end

  defp from_liquidsoap_path(path, options) do
    translate(path, liquidsoap_media_dir(options), media_dir(options))
  end

  defp translate(path, source_root, target_root) do
    relative = Path.relative_to(Path.expand(path), Path.expand(source_root))

    if Path.type(relative) != :relative or relative in [".", ".."] or
         String.starts_with?(relative, "../") or
         not Regex.match?(~r/\A[a-zA-Z0-9_\/.\-]+\z/, relative) do
      {:error, :invalid_media_path}
    else
      {:ok, Path.join(target_root, relative)}
    end
  end

  defp media_dir(options) do
    Keyword.get(
      options,
      :media_dir,
      Application.get_env(:nozomi_station, :media_dir, "tmp/media")
    )
  end

  defp liquidsoap_media_dir(options) do
    Keyword.get(
      options,
      :liquidsoap_media_dir,
      Application.get_env(:nozomi_station, :liquidsoap_media_dir, "/media")
    )
  end
end
