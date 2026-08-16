import Hls from "hls.js"

const hlsMimeType = "application/vnd.apple.mpegurl"

export async function connectToLiveStream(audio, streamUrl, HlsType = Hls) {
  if (audio.canPlayType(hlsMimeType)) {
    audio.src = streamUrl
    await audio.play()
    return null
  }

  if (!HlsType.isSupported()) throw new Error("HLS no está disponible en este navegador")

  const hls = new HlsType({
    liveSyncDuration: 1,
    liveMaxLatencyDuration: 2,
  })

  hls.on(HlsType.Events.MANIFEST_PARSED, () => audio.play())
  hls.attachMedia(audio)
  hls.loadSource(streamUrl)
  return hls
}

export const RadioPlayer = {
  mounted() {
    this.audio = this.el.querySelector("#live-audio")
    this.button = this.el.querySelector("#join-live")
    this.connected = false
    this.connecting = false
    this.button.dataset.live = "false"
    this.onPlaying = () => this.markLive()
    this.onDisconnected = () => this.markDisconnected()
    this.onJoin = () => this.joinLive()
    this.audio.addEventListener("playing", this.onPlaying)
    this.audio.addEventListener("ended", this.onDisconnected)
    this.audio.addEventListener("error", this.onDisconnected)
    this.button.addEventListener("click", this.onJoin)
  },

  markLive() {
    this.connected = true
    this.connecting = false
    this.button.hidden = false
    this.button.disabled = true
    this.button.ariaLabel = "Emisión en vivo"
    this.button.dataset.live = "true"
  },

  markDisconnected() {
    this.hls?.destroy()
    this.hls = null
    this.connected = false
    this.connecting = false
    this.button.disabled = false
    this.button.ariaLabel = "Subir al tren y escuchar en vivo"
    this.button.dataset.live = "false"
  },

  async joinLive() {
    if (this.connected || this.connecting) return

    this.connecting = true
    this.button.disabled = true
    this.hls?.destroy()

    try {
      this.hls = await connectToLiveStream(this.audio, this.el.dataset.stream)
    } catch (_error) {
      this.markDisconnected()
      this.button.ariaLabel = "Emisión no disponible; reintentar"
    }
  },

  destroyed() {
    this.audio.removeEventListener("playing", this.onPlaying)
    this.audio.removeEventListener("ended", this.onDisconnected)
    this.audio.removeEventListener("error", this.onDisconnected)
    this.button.removeEventListener("click", this.onJoin)
    this.hls?.destroy()
  },
}

export const VolumeControl = {
  mounted() {
    this.audio ||= document.querySelector("#live-audio")
    this.volume = this.el.querySelector("#volume-control")
    this.onVolume = () => this.setVolume()
    this.volume.addEventListener("input", this.onVolume)
    this.setVolume()
  },

  setVolume() {
    this.audio.volume = Number(this.volume.value)
  },

  destroyed() {
    this.volume.removeEventListener("input", this.onVolume)
  },
}
