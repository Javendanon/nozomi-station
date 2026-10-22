defmodule NozomiStation.RuntimeConfigTest do
  use ExUnit.Case, async: false

  @settings ~w(DATABASE_URL SECRET_KEY_BASE PHX_HOST SLACK_SIGNING_SECRET SLACK_BOT_TOKEN SLACK_CHANNEL_ID SPOTIFY_CLIENT_ID SPOTIFY_CLIENT_SECRET LASTFM_API_KEY)
  @runtime Path.expand("../../config/runtime.exs", __DIR__)

  setup do
    names = @settings ++ Enum.map(@settings, &(&1 <> "_FILE"))
    previous = Map.new(names, &{&1, System.get_env(&1)})

    on_exit(fn ->
      for {name, value} <- previous do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end)

    for name <- @settings do
      System.put_env(name, "test-value")
      System.delete_env(name <> "_FILE")
    end

    System.put_env("DATABASE_URL", "ecto://test:test@postgres/test")
    :ok
  end

  test "plain environment settings remain supported" do
    config = Config.Reader.read!(@runtime, env: :prod)
    assert config[:nozomi_station][NozomiStation.Repo][:url] == "ecto://test:test@postgres/test"
    assert config[:nozomi_station][:slack_bot_token] == "test-value"
  end

  @tag :tmp_dir
  test "secret files take precedence and trim the terminal newline", %{tmp_dir: dir} do
    path = Path.join(dir, "token")
    File.write!(path, "file-token\n")
    System.put_env("SLACK_BOT_TOKEN_FILE", path)

    config = Config.Reader.read!(@runtime, env: :prod)
    assert config[:nozomi_station][:slack_bot_token] == "file-token"
  end

  @tag :tmp_dir
  test "missing or empty secret files fail closed despite an environment fallback", %{
    tmp_dir: dir
  } do
    path = Path.join(dir, "token")
    System.put_env("SLACK_BOT_TOKEN_FILE", path)

    assert_raise File.Error, fn -> Config.Reader.read!(@runtime, env: :prod) end

    File.write!(path, "\n")

    assert_raise RuntimeError, "required setting SLACK_BOT_TOKEN is missing", fn ->
      Config.Reader.read!(@runtime, env: :prod)
    end
  end

  test "missing mandatory settings fail without printing secret values" do
    System.delete_env("SECRET_KEY_BASE")

    assert_raise RuntimeError, "required setting SECRET_KEY_BASE is missing", fn ->
      Config.Reader.read!(@runtime, env: :prod)
    end
  end
end
