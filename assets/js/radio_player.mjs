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
    this.status = this.el.querySelector("#stream-status")
    this.connected = false
    this.connecting = false
    this.onPlaying = () => this.markLive()
    this.onJoin = () => this.joinLive()
    this.audio.addEventListener("playing", this.onPlaying)
    this.button.addEventListener("click", this.onJoin)
  },

  markLive() {
    this.connected = true
    this.connecting = false
    this.button.hidden = false
    this.button.disabled = true
    this.button.ariaLabel = "Emisión en vivo"
    this.el.dataset.live = "true"
    this.status.textContent = "Señal sincronizada"
  },

  async joinLive() {
    if (this.connected || this.connecting) return

    this.connecting = true
    this.status.textContent = "Conectando"
    this.hls?.destroy()

    try {
      this.hls = await connectToLiveStream(this.audio, this.el.dataset.stream)
    } catch (_error) {
      this.connecting = false
      this.status.textContent = "Emisión no disponible"
    }
  },

  destroyed() {
    this.audio.removeEventListener("playing", this.onPlaying)
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
