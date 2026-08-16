defmodule NozomiStationWeb.RadioLive do
  use NozomiStationWeb, :live_view

  alias NozomiStation.Programming.NowPlaying

  @impl true
  def mount(_params, _session, socket) do
    now_playing =
      if connected?(socket) do
        :ok = NowPlaying.subscribe()
        NowPlaying.current()
      end

    {:ok, assign(socket, stream_url: ~p"/hls/live.m3u8", now_playing: now_playing)}
  end

  @impl true
  def handle_info({:now_playing, track}, socket) do
    {:noreply, assign(socket, :now_playing, track)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="station" class="station-shell">
        <div id="neo-journey" class="neo-journey" aria-hidden="true">
          <div class="neo-sun"></div>
          <div class="neo-city"></div>
          <div class="neo-rails"></div>
        </div>

        <header class="station-header">
          <div>
            <p class="station-kicker">NOZOMI / 望み</p>
            <h1>Nozomi Station</h1>
          </div>
          <p class="station-route"><span aria-hidden="true">●</span> Neo-Tokyo Express</p>
        </header>

        <div class="station-content">
          <div class="station-intro">
            <p class="station-eyebrow">Emisión continua · 24/7</p>
            <h2>La noche avanza.<br />La música también.</h2>
          </div>

          <article :if={@now_playing} id="now-playing" class="now-playing-card">
            <img
              :if={Map.get(@now_playing, :cover_url)}
              id="now-playing-cover"
              src={Map.get(@now_playing, :cover_url)}
              alt={"Portada de #{Map.get(@now_playing, :title)}"}
              referrerpolicy="no-referrer"
            />
            <div class="now-playing-copy">
              <p class="station-eyebrow">Ahora suena</p>
              <h3 id="now-playing-title">{Map.get(@now_playing, :title)}</h3>
              <p id="now-playing-artist">{Map.get(@now_playing, :artist)}</p>
              <p :if={Map.get(@now_playing, :album)} id="now-playing-album" class="track-album">
                {Map.get(@now_playing, :album)}
              </p>
              <ul
                :if={Map.get(@now_playing, :tags, []) != []}
                id="now-playing-tags"
                class="track-tags"
              >
                <li :for={tag <- Map.get(@now_playing, :tags, [])}>{tag}</li>
              </ul>
              <p
                :if={Map.get(@now_playing, :summary)}
                id="now-playing-summary"
                class="track-summary"
              >
                {Map.get(@now_playing, :summary)}
              </p>
              <blockquote
                :if={Map.get(@now_playing, :listener_message)}
                id="listener-message"
                class="listener-message"
              >
                “{Map.get(@now_playing, :listener_message)}”
              </blockquote>
            </div>
          </article>
        </div>

        <footer class="station-player">
          <div id="signal-wave" class="signal-wave" aria-hidden="true">
            <span :for={index <- 1..12} style={"--bar: #{index}"}></span>
          </div>
          <div
            id="radio-player"
            data-stream={@stream_url}
            data-live="false"
            phx-hook="RadioPlayer"
            phx-update="ignore"
          >
            <button id="join-live" type="button" aria-label="Subir al tren y escuchar en vivo">
              <span aria-hidden="true">▶</span> Subir al tren
            </button>
            <p id="stream-status" role="status">Conectando</p>
            <audio id="live-audio" preload="none"></audio>
          </div>
        </footer>
      </section>
    </Layouts.app>
    """
  end
end
