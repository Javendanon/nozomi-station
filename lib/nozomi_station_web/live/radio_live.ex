defmodule NozomiStationWeb.RadioLive do
  use NozomiStationWeb, :live_view

  alias NozomiStation.Identity
  alias NozomiStation.Programming.NowPlaying

  @impl true
  def mount(_params, session, socket) do
    now_playing =
      if connected?(socket) do
        :ok = NowPlaying.subscribe()
        NowPlaying.current()
      end

    {:ok,
     assign(socket,
       stream_url: ~p"/hls/live.m3u8",
       now_playing: now_playing,
       listener_id: session["listener_id"],
       identity: nil,
       identity_persistent?: true
     )}
  end

  @impl true
  def handle_event("restore_identity", data, socket) do
    identity = socket.assigns.identity || Identity.restore(data, socket.assigns.listener_id)
    {:noreply, put_identity(socket, identity, true)}
  end

  def handle_event("regenerate_alias", _params, %{assigns: %{identity: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("regenerate_alias", _params, socket) do
    {:noreply, put_identity(socket, Identity.regenerate(socket.assigns.identity))}
  end

  def handle_event("identity_storage", %{"available" => available}, socket)
      when is_boolean(available) do
    {:noreply, assign(socket, :identity_persistent?, available)}
  end

  def handle_event("identity_storage", _params, socket), do: {:noreply, socket}

  defp put_identity(socket, identity, restored? \\ false) do
    socket
    |> assign(:identity, identity)
    |> push_event("identity", Map.put(identity, :restored, restored?))
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

          <div id="station-side" class="station-side">
            <section
              id="local-identity"
              phx-hook="LocalIdentity"
              aria-label="Your local listener identity"
              class="rounded-2xl border border-white/15 bg-black/25 p-5 text-white"
            >
              <p class="text-xs font-medium uppercase tracking-widest text-white/60">
                Your railway alias
              </p>
              <p id="listener-alias" aria-live="polite" class="mt-2 break-words text-sm font-semibold">
                {if @identity, do: @identity.alias, else: "Connecting your identity…"}
              </p>
              <button
                id="regenerate-alias"
                type="button"
                phx-click="regenerate_alias"
                phx-disable-with="Regenerating…"
                disabled={is_nil(@identity)}
                class="mt-3 rounded-lg border border-white/20 px-3 py-2 text-xs transition-colors hover:bg-white/10 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-white disabled:cursor-wait disabled:opacity-50"
              >
                Regenerate alias
              </button>
              <p class="mt-3 text-xs leading-relaxed text-white/60">
                No account needed. Changing your alias does not reset your votes.
              </p>
              <p
                :if={!@identity_persistent?}
                id="identity-storage-warning"
                role="status"
                class="mt-3 text-xs leading-relaxed text-amber-200"
              >
                Browser storage is unavailable. Your alias lasts only until this page is closed or reloaded.
              </p>
            </section>

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

            <div
              id="volume-controller"
              class="nozomi-volume"
              phx-hook="VolumeControl"
              phx-update="ignore"
            >
              <div class="volume-heading">
                <label for="volume-control"><i aria-hidden="true"></i> Volumen</label>
                <span aria-hidden="true">N700 AUDIO</span>
              </div>
              <input
                id="volume-control"
                type="range"
                min="0"
                max="1"
                step="0.01"
                value="0.8"
                aria-label="Volumen del reproductor"
              />
              <div class="volume-terminals" aria-hidden="true">
                <span>静</span><i></i><span>のぞみ</span>
              </div>
            </div>
          </div>
        </div>

        <footer class="station-player">
          <div id="signal-wave" class="signal-wave" aria-hidden="true">
            <span :for={index <- 1..12} style={"--bar: #{index}"}></span>
          </div>
          <div
            id="radio-player"
            data-stream={@stream_url}
            phx-hook="RadioPlayer"
            phx-update="ignore"
          >
            <button id="join-live" type="button" aria-label="Subir al tren y escuchar en vivo">
              <span class="join-label">Subir al tren <i aria-hidden="true">→</i></span>
              <span class="live-label"><i aria-hidden="true">●</i> En vivo</span>
            </button>
            <audio id="live-audio" preload="none"></audio>
          </div>
        </footer>
      </section>
    </Layouts.app>
    """
  end
end
