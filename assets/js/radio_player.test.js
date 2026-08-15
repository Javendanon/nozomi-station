import assert from "node:assert/strict"
import test from "node:test"

import {connectToLiveStream} from "./radio_player.js"

const audio = nativeHls => ({
  canPlayType: () => nativeHls ? "maybe" : "",
  play() {
    this.played = true
    return Promise.resolve()
  },
})

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
  assert.equal(hls.config.liveSyncDurationCount, 1)
  assert.equal(element.played, true)
})
