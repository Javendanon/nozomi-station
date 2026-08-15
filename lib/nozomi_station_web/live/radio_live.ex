defmodule NozomiStationWeb.RadioLive do
  use NozomiStationWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, stream_url: ~p"/hls/live.m3u8")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="space-y-6 text-center">
        <p class="text-sm font-semibold uppercase tracking-[0.3em] text-zinc-500">
          Nozomi Station
        </p>
        <h1 class="text-4xl font-bold tracking-tight text-zinc-950 sm:text-6xl">
          Radio en vivo
        </h1>
        <div id="radio-player" data-stream={@stream_url} class="space-y-3">
          <button
            id="join-live"
            type="button"
            aria-label="Subir al tren y escuchar en vivo"
            class="rounded-full bg-zinc-950 px-6 py-3 font-semibold text-white transition hover:bg-zinc-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-zinc-950"
          >
            Subir al tren
          </button>
          <p id="stream-status" role="status" class="text-sm text-zinc-500">Conectando</p>
          <audio id="live-audio" preload="none"></audio>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
