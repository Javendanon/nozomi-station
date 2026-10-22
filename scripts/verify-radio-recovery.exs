# Invoked only by verify-radio-recovery.sh against its disposable database.
"1" = System.fetch_env!("RADIO_RECOVERY_VERIFY")
[mode] = System.argv()

alias NozomiStation.Programming.{ComplementaryTrack, LiquidsoapClient, Scheduler}
alias NozomiStation.Repo
alias NozomiStation.Requests.Request

repo_config =
  Application.fetch_env!(:nozomi_station, Repo)
  |> Keyword.merge(
    hostname: "127.0.0.1",
    port: String.to_integer(System.fetch_env!("RECOVERY_POSTGRES_PORT")),
    database: "nozomi_recovery",
    pool: DBConnection.ConnectionPool,
    pool_size: 4
  )

Application.put_env(:nozomi_station, Repo, repo_config)

Application.put_env(
  :nozomi_station,
  :liquidsoap_port,
  String.to_integer(System.fetch_env!("RECOVERY_CONTROL_PORT"))
)

Application.put_env(:nozomi_station, :media_dir, System.fetch_env!("RECOVERY_MEDIA_DIR"))

Application.put_env(:nozomi_station, :scheduler_options,
  poll: mode == "serve",
  poll_interval: 200
)

Application.put_env(:nozomi_station, :now_playing_options, poll: false)

endpoint = NozomiStationWeb.Endpoint

Application.put_env(
  :nozomi_station,
  endpoint,
  Application.fetch_env!(:nozomi_station, endpoint)
  |> Keyword.merge(server: mode == "serve", http: [ip: {127, 0, 0, 1}, port: 0])
)

if mode == "seed" do
  {:ok, _} = Application.ensure_all_started(:ecto_sql)
  :ok = Repo.__adapter__().storage_up(repo_config)

  {:ok, _, _} =
    Ecto.Migrator.with_repo(Repo, fn repo ->
      Ecto.Migrator.run(repo, Application.app_dir(:nozomi_station, "priv/repo/migrations"), :up,
        all: true
      )
    end)
end

{:ok, _} = Application.ensure_all_started(:nozomi_station)

media_dir = System.fetch_env!("RECOVERY_MEDIA_DIR")

case mode do
  "seed" ->
    %ComplementaryTrack{}
    |> ComplementaryTrack.changeset(%{
      youtube_id: "recovery-current",
      title: "Recovery current",
      artist: "Local generator",
      duration_seconds: 24,
      origin: "seed",
      status: "ready",
      file_path: Path.join(media_dir, "current.m4a")
    })
    |> Repo.insert!()

  "seed-waiting" ->
    for id <- 1..2 do
      %Request{}
      |> Request.changeset(%{
        youtube_id: "recovery-request-#{id}",
        title: "Recovery request #{id}",
        artist: "Local generator",
        duration_seconds: 2,
        slack_user: "U01",
        slack_channel: "C01",
        thread_ts: "1",
        status: "ready",
        file_path: Path.join(media_dir, "waiting.m4a")
      })
      |> Repo.insert!()
    end

    %ComplementaryTrack{}
    |> ComplementaryTrack.changeset(%{
      youtube_id: "recovery-waiting",
      title: "Recovery waiting",
      artist: "Local generator",
      duration_seconds: 2,
      origin: "seed",
      status: "ready",
      file_path: Path.join(media_dir, "waiting.m4a")
    })
    |> Repo.insert!()

  "fail-after-ack" ->
    Scheduler.run(
      deliver: fn queue, id, path ->
        {:ok, "queued"} = LiquidsoapClient.deliver(queue, id, path)
        # Deliberately exit the VM before the scheduler transaction can commit.
        System.halt(71)
      end
    )

    raise "Expected a delivery before the injected failure"

  "assert-ready" ->
    [%{status: "ready"}] = Repo.all(ComplementaryTrack)

  "assert-queued" ->
    true = Enum.all?(Repo.all(Request) ++ Repo.all(ComplementaryTrack), &(&1.status == "queued"))

  "assert-played" ->
    {:ok, %{requested: 0, complementary: 0}} = Scheduler.run()
    items = Repo.all(Request) ++ Repo.all(ComplementaryTrack)
    4 = length(items)
    true = Enum.all?(items, &(&1.status == "played"))

  "serve" ->
    true = is_pid(Process.whereis(NozomiStationWeb.Endpoint))
    IO.puts("RECOVERY_PHOENIX_READY")
    Process.sleep(:infinity)
end
