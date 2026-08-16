defmodule NozomiStation.Programming.LiquidsoapClient do
  @queues [:requested, :complementary]
  @timeout 1_000

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

  def active_paths, do: active_paths(&command/1, [])

  def active_paths(command, options) do
    with {:ok, lines} <- command.("request.all") do
      lines
      |> Enum.flat_map(&String.split/1)
      |> Enum.reduce_while({:ok, []}, fn id, {:ok, paths} ->
        case active_path(id, command, options) do
          {:ok, path} -> {:cont, {:ok, [path | paths]}}
          :finished -> {:cont, {:ok, paths}}
          error -> {:halt, error}
        end
      end)
      |> then(fn
        {:ok, paths} -> {:ok, Enum.reverse(paths)}
        error -> error
      end)
    end
  end

  def current_path, do: current_path(&command/1, [])

  def current_path(command, options) do
    with {:ok, all} <- request_ids(command, "request.all"),
         {:ok, requested} <- request_ids(command, "requested.queue"),
         {:ok, complementary} <- request_ids(command, "complementary.queue") do
      case List.first(all -- (requested ++ complementary)) do
        nil -> {:ok, nil}
        id -> current_request_path(id, command, options)
      end
    end
  end

  defp request_ids(command, value) do
    with {:ok, lines} <- command.(value) do
      ids = Enum.flat_map(lines, &String.split/1)

      if Enum.all?(ids, &(&1 =~ ~r/^\d+$/)),
        do: {:ok, ids},
        else: {:error, :invalid_control_response}
    end
  end

  defp current_request_path(id, command, options) do
    case active_path(id, command, options) do
      {:ok, path} -> {:ok, path}
      :finished -> {:ok, nil}
      error -> error
    end
  end

  defp active_path(id, command, options) do
    with true <- id =~ ~r/^\d+$/,
         {:ok, metadata} <- command.("request.metadata #{id}"),
         false <- metadata == ["No such request."],
         line when is_binary(line) <- Enum.find(metadata, &media_path?/1),
         [_, path] <- Regex.run(~r/^(?:filename|initial_uri)="([^"]+)"$/, line) do
      from_liquidsoap_path(path, options)
    else
      value when value in [true, false, nil] -> :finished
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_control_response}
    end
  end

  defp media_path?(line) do
    String.starts_with?(line, "filename=") or String.starts_with?(line, "initial_uri=")
  end

  defp command(value) do
    case send_command(value) do
      {:error, reason} when reason in [:closed, :econnrefused, :timeout] ->
        Process.sleep(50)
        send_command(value)

      result ->
        result
    end
  end

  defp send_command(value) do
    host = Application.get_env(:nozomi_station, :liquidsoap_host, "127.0.0.1")
    port = Application.get_env(:nozomi_station, :liquidsoap_port, 1234)

    with {:ok, socket} <-
           :gen_tcp.connect(String.to_charlist(host), port, [:binary, active: false], @timeout),
         :ok <- :gen_tcp.send(socket, value <> "\nquit\n"),
         {:ok, response} <- receive_response(socket, "") do
      :gen_tcp.close(socket)
      parse_response(response)
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
    relative = Path.relative_to(path, source_root)

    if Path.type(relative) != :relative or relative == ".." or
         String.starts_with?(relative, "../") or relative =~ ~r/\s/ do
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
