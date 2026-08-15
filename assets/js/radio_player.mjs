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
    this.onPlaying = () => {
      this.connected = true
      this.connecting = false
      this.status.textContent = "En vivo"
    }
    this.onJoin = async () => {
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
    }

    this.audio.addEventListener("playing", this.onPlaying)
    this.button.addEventListener("click", this.onJoin)
  },

  destroyed() {
    this.audio.removeEventListener("playing", this.onPlaying)
    this.button.removeEventListener("click", this.onJoin)
    this.hls?.destroy()
  },
}
