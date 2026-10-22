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
    {server, ref} = server(["17\r\nEND\r\nBye!\r\n"])

    assert :ok = LiquidsoapClient.push(:requested, "tmp/media/17.m4a")
    assert_receive {:control_command, "requested.push /media/17.m4a\nquit\n"}
    assert_receive {:DOWN, ^ref, :process, ^server, :normal}
  end

  test "reads the actual current track including the private resume queue" do
    command = fn "radio.current" ->
      {:ok, [~s({"key":"complementary-3","path":"/media/c3.m4a","position":42.0})]}
    end

    assert {:ok, "tmp/media/c3.m4a"} = LiquidsoapClient.current_path(command, [])
  end

  test "returns no current path during fallback and preserves control failures" do
    assert {:ok, nil} =
             LiquidsoapClient.current_path(
               fn "radio.current" -> {:ok, [~s({"key":"","path":""})]} end,
               []
             )

    assert {:error, :closed} =
             LiquidsoapClient.current_path(fn "radio.current" -> {:error, :closed} end, [])
  end

  test "rejects malformed current snapshots" do
    for snapshot <- ["not json", ~s({"key":17,"path":"/media/c3.m4a"})] do
      assert {:error, :invalid_control_response} =
               LiquidsoapClient.current_path(fn "radio.current" -> {:ok, [snapshot]} end, [])
    end
  end

  test "scheduler worker leaves an empty queue unchanged without control I/O" do
    assert {:ok, %{requested: 0, complementary: 0}} =
             SchedulerWorker.perform(%Oban.Job{})
  end

  test "uses a stable delivery key and validates the durable receipt" do
    command = fn value ->
      assert value == "radio.enqueue requested-17 requested /media/17.m4a"
      {:ok, [~s({"key":"requested-17","state":"playing","position":42.5})]}
    end

    assert {:ok, "queued"} =
             LiquidsoapClient.deliver(:requested, 17, "tmp/media/17.m4a", command, [])

    for response <- [
          ~s({"key":"requested-18","state":"played","position":0}),
          ~s({"key":"requested-17","state":"unknown","position":0}),
          ~s({"key":"requested-17","state":"played","position":-1}),
          "not json"
        ] do
      assert {:error, :invalid_control_response} =
               LiquidsoapClient.deliver(
                 :requested,
                 17,
                 "tmp/media/17.m4a",
                 fn _ -> {:ok, [response]} end,
                 []
               )
    end
  end

  test "rejects traversal and annotation injection before sending a delivery" do
    for path <- [
          "tmp/media/../secret.m4a",
          "tmp/media/a/../../secret.m4a",
          "tmp/media/track\".m4a",
          "tmp/media/track\nquit"
        ] do
      assert {:error, :invalid_media_path} =
               LiquidsoapClient.deliver(
                 :requested,
                 17,
                 path,
                 fn _ -> flunk("unsafe path reached control socket") end,
                 []
               )
    end
  end

  test "fails closed when Liquidsoap rejects a command" do
    {server, ref} = server(["ERROR: invalid request\r\nEND\r\nBye!\r\n"])

    assert {:error, :control_rejected} =
             LiquidsoapClient.push(:complementary, "tmp/media/c5.m4a")

    assert_receive {:DOWN, ^ref, :process, ^server, :normal}
  end

  defp server(responses) do
    test = self()
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_address, port}} = :inet.sockname(listener)
    Application.put_env(:nozomi_station, :liquidsoap_port, port)

    pid =
      start_supervised!(
        {Task,
         fn ->
           Enum.each(responses, fn response ->
             {:ok, socket} = :gen_tcp.accept(listener)
             {:ok, command} = :gen_tcp.recv(socket, 0, 1_000)
             send(test, {:control_command, command})
             :ok = :gen_tcp.send(socket, response)
             :gen_tcp.close(socket)
           end)

           :gen_tcp.close(listener)
         end}
      )

    {pid, Process.monitor(pid)}
  end
end
