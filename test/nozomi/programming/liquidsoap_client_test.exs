defmodule NozomiStation.Programming.LiquidsoapClientTest do
  use NozomiStation.DataCase, async: false

  alias NozomiStation.Programming.{LiquidsoapClient, SchedulerWorker}

  setup do
    keys = [:liquidsoap_host, :liquidsoap_port, :media_dir, :liquidsoap_media_dir]
    previous = Map.new(keys, &{&1, Application.get_env(:nozomi_station, &1)})

    Application.put_env(:nozomi_station, :liquidsoap_host, "127.0.0.1")
    Application.put_env(:nozomi_station, :media_dir, "tmp/media")
    Application.put_env(:nozomi_station, :liquidsoap_media_dir, "/media")

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:nozomi_station, key)
        {key, value} -> Application.put_env(:nozomi_station, key, value)
      end)
    end)
  end

  test "pushes through the local text protocol" do
    server = server(["17\r\nEND\r\nBye!\r\n"])

    assert :ok = LiquidsoapClient.push(:requested, "tmp/media/17.m4a")
    assert_receive {:control_command, "requested.push /media/17.m4a\nquit\n"}
    Task.await(server)
  end

  test "reads active paths across request metadata commands" do
    server =
      server([
        "4\r\nEND\r\nBye!\r\n",
        "status=\"ready\"\nfilename=\"/media/c4.m4a\"\r\nEND\r\nBye!\r\n"
      ])

    assert {:ok, ["tmp/media/c4.m4a"]} = LiquidsoapClient.active_paths()
    assert_receive {:control_command, "request.all\nquit\n"}
    assert_receive {:control_command, "request.metadata 4\nquit\n"}
    Task.await(server)
  end

  test "scheduler worker delegates through the real control boundary" do
    server = server(["\r\nEND\r\nBye!\r\n"])

    assert {:ok, %{requested: 0, complementary: 0}} =
             SchedulerWorker.perform(%Oban.Job{})

    Task.await(server)
  end

  test "fails closed when Liquidsoap rejects a command" do
    server = server(["ERROR: invalid request\r\nEND\r\nBye!\r\n"])

    assert {:error, :control_rejected} =
             LiquidsoapClient.push(:complementary, "tmp/media/c5.m4a")

    Task.await(server)
  end

  defp server(responses) do
    test = self()
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_address, port}} = :inet.sockname(listener)
    Application.put_env(:nozomi_station, :liquidsoap_port, port)

    Task.async(fn ->
      Enum.each(responses, fn response ->
        {:ok, socket} = :gen_tcp.accept(listener)
        {:ok, command} = :gen_tcp.recv(socket, 0, 1_000)
        send(test, {:control_command, command})
        :ok = :gen_tcp.send(socket, response)
        :gen_tcp.close(socket)
      end)

      :gen_tcp.close(listener)
    end)
  end
end
