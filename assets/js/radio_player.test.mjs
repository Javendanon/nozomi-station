import assert from "node:assert/strict"
import test from "node:test"

import {connectToLiveStream, RadioPlayer} from "./radio_player.mjs"

const audio = nativeHls => ({
  canPlayType: () => nativeHls ? "maybe" : "",
  play() {
    this.played = true
    return Promise.resolve()
  },
})

const eventTarget = properties => {
  const listeners = new Map()
  const target = {
    ...properties,
    addEventListener: (event, callback) => listeners.set(event, callback),
    removeEventListener: event => listeners.delete(event),
    listensTo: event => listeners.has(event),
  }
  target.trigger = event => target.disabled ? undefined : listeners.get(event)?.()
  return target
}

test("uses native HLS support when the browser provides it", async () => {
  const element = audio(true)

  const hls = await connectToLiveStream(element, "/hls/live.m3u8")

  assert.equal(element.src, "/hls/live.m3u8")
  assert.equal(element.played, true)
  assert.equal(hls, null)
})

test("uses hls.js at the live edge when native HLS is unavailable", async () => {
  class FakeHls {
    static Events = {MANIFEST_PARSED: "manifest"}
    static isSupported() { return true }

    constructor(config) { this.config = config }
    on(_event, callback) { this.ready = callback }
    loadSource(source) { this.source = source; this.ready() }
    attachMedia(element) { this.element = element }
  }

  const element = audio(false)
  const hls = await connectToLiveStream(element, "/hls/live.m3u8", FakeHls)

  assert.equal(hls.source, "/hls/live.m3u8")
  assert.equal(hls.element, element)
  assert.equal(hls.config.liveSyncDuration, 1)
  assert.equal(hls.config.liveMaxLatencyDuration, 2)
  assert.equal(element.played, true)
})

test("keeps live playback on repeated joins and releases it when unmounting", async () => {
  const button = eventTarget({})
  const streamAudio = eventTarget(audio(true))
  const status = {textContent: "En vivo"}
  const elements = {"#join-live": button, "#live-audio": streamAudio, "#stream-status": status}
  const hook = {
    ...RadioPlayer,
    el: {dataset: {stream: "/hls/live.m3u8"}, querySelector: selector => elements[selector]},
  }
  let destroyed = 0

  hook.mounted()
  hook.hls = {destroy: () => destroyed++}
  await streamAudio.trigger("playing")

  assert.equal(button.disabled, true)
  await button.trigger("click")
  assert.equal(destroyed, 0)
  assert.equal(status.textContent, "En vivo")
  assert.equal(button.listensTo("click"), true)
  hook.destroyed()
  assert.equal(destroyed, 1)
  assert.equal(button.listensTo("click"), false)
  assert.equal(streamAudio.listensTo("playing"), false)
})
