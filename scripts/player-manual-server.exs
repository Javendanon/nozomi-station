# Invoked only by verify-player-manual.sh, against its disposable services.
alias NozomiStation.Programming.LiquidsoapClient
alias NozomiStation.Repo
alias NozomiStation.Requests.Request

repo_config = Application.fetch_env!(:nozomi_station, Repo)
Application.put_env(:nozomi_station, Repo, Keyword.put(repo_config, :database, "player_manual"))

Application.put_env(:nozomi_station, Oban,
  repo: Repo,
  queues: false,
  plugins: false
)

Application.put_env(:nozomi_station, :media_dir, System.fetch_env!("PLAYER_MEDIA_DIR"))

Application.put_env(
  :nozomi_station,
  :lastfm_api_key,
  if(System.get_env("PLAYER_REAL_LASTFM") == "1", do: System.fetch_env!("LASTFM_API_KEY"))
)

endpoint = Application.fetch_env!(:nozomi_station, NozomiStationWeb.Endpoint)

Application.put_env(
  :nozomi_station,
  NozomiStationWeb.Endpoint,
  Keyword.merge(endpoint, server: true, watchers: [], live_reload: [])
)

Mix.Task.run("ecto.create")
Mix.Task.run("ecto.migrate")
{:ok, _} = Application.ensure_all_started(:nozomi_station)

for {file, title, artist} <- [
      {"first.m4a", System.fetch_env!("PLAYER_FIRST_TITLE"),
       System.fetch_env!("PLAYER_FIRST_ARTIST")},
      {"second.m4a", System.fetch_env!("PLAYER_SECOND_TITLE"),
       System.fetch_env!("PLAYER_SECOND_ARTIST")}
    ] do
  path = Path.join(System.fetch_env!("PLAYER_MEDIA_DIR"), file)

  %Request{}
  |> Request.changeset(%{
    youtube_id: "manual-#{file}",
    title: title,
    artist: artist,
    duration_seconds: 60,
    slack_user: "U_MANUAL",
    slack_channel: "C_MANUAL",
    thread_ts: "manual",
    listener_message: "Local generated tones; metadata is for provider verification only.",
    status: "queued",
    file_path: path
  })
  |> Repo.insert!()

  :ok = LiquidsoapClient.push(:requested, path)
end

File.write!(System.fetch_env!("PLAYER_READY_FILE"), "ready\n")
