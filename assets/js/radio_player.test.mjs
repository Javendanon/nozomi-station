import assert from "node:assert/strict"
import test from "node:test"

import {connectToLiveStream, RadioPlayer, VolumeControl} from "./radio_player.mjs"

const audio = nativeHls => ({
  canPlayType: () => nativeHls ? "maybe" : "",
  pause() { this.paused = true },
  removeAttribute(name) { delete this[name] },
  load() { this.resetCount = (this.resetCount || 0) + 1 },
  play() {
    this.played = true
    this.playCount = (this.playCount || 0) + 1
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
  target.trigger = event => target.hidden ? undefined : listeners.get(event)?.()
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
    static Events = {MANIFEST_PARSED: "manifest", ERROR: "error"}
    static isSupported() { return true }

    constructor(config) { this.config = config }
    on(event, callback) { this[event] = callback }
    loadSource(source) { this.source = source; this.manifest() }
    attachMedia(element) { this.element = element }
  }

  const element = audio(false)
  let fatalErrors = 0
  const hls = await connectToLiveStream(element, "/hls/live.m3u8", FakeHls, () => fatalErrors++)

  assert.equal(hls.source, "/hls/live.m3u8")
  assert.equal(hls.element, element)
  assert.equal(hls.config.liveSyncDuration, 1)
  assert.equal(hls.config.liveMaxLatencyDuration, 2)
  assert.equal(element.played, true)
  hls.error(null, {fatal: false})
  hls.error(null, {fatal: true})
  assert.equal(fatalErrors, 1)
})

test("keeps live playback across patches and reconnects after the stream ends", async () => {
  const button = eventTarget({dataset: {}})
  const streamAudio = eventTarget(audio(true))
  const elements = {"#join-live": button, "#live-audio": streamAudio}
  const hook = {
    ...RadioPlayer,
    el: {dataset: {stream: "/hls/live.m3u8"}, querySelector: selector => elements[selector]},
  }
  let destroyed = 0

  hook.mounted()
  await button.trigger("click")
  assert.equal(streamAudio.played, true)
  hook.attempt.signal.addEventListener("abort", () => destroyed++)
  await streamAudio.trigger("playing")

  assert.equal(button.hidden, false)
  assert.equal(button.disabled, true)
  assert.equal(button.ariaLabel, "Live broadcast")
  assert.equal(button.dataset.live, "true")

  hook.el.dataset.live = "false"
  assert.equal(button.dataset.live, "true")
  await button.trigger("click")
  assert.equal(destroyed, 0)

  await streamAudio.trigger("ended")
  assert.equal(hook.connected, false)
  assert.equal(button.disabled, false)
  assert.equal(button.dataset.live, "false")
  assert.equal(destroyed, 1)

  await button.trigger("click")
  assert.equal(streamAudio.playCount, 2)
  await streamAudio.trigger("playing")
  assert.equal(button.dataset.live, "true")

  hook.destroyed()
  assert.equal(button.listensTo("click"), false)
  assert.equal(streamAudio.listensTo("playing"), false)
  assert.equal(streamAudio.listensTo("ended"), false)
  assert.equal(streamAudio.listensTo("error"), false)
})

test("restores the join control when a requested stream never starts playing", async () => {
  const button = eventTarget({dataset: {}, disabled: false})
  const streamAudio = eventTarget(audio(true))
  const elements = {"#join-live": button, "#live-audio": streamAudio}
  const hook = {
    ...RadioPlayer,
    joinTimeoutMs: 0,
    el: {dataset: {stream: "/hls/live.m3u8"}, querySelector: selector => elements[selector]},
  }

  hook.mounted()
  await button.trigger("click")
  assert.equal(streamAudio.playCount, 1)
  assert.equal(hook.connecting, true)
  assert.equal(button.disabled, true)

  await new Promise(resolve => setTimeout(resolve, 0))

  assert.equal(hook.connecting, false)
  assert.equal(button.disabled, false)
  assert.equal(button.dataset.live, "false")

  await button.trigger("click")
  assert.equal(streamAudio.playCount, 2)

  hook.destroyed()
})

test("ignores an abandoned native join rejection without clearing the retry timeout", async (t) => {
  t.mock.timers.enable({apis: ["setTimeout"]})
  const pending = []
  const button = eventTarget({dataset: {}})
  const streamAudio = eventTarget({
    ...audio(true),
    play: () => new Promise((resolve, reject) => pending.push({resolve, reject})),
  })
  const elements = {"#join-live": button, "#live-audio": streamAudio}
  const hook = {
    ...RadioPlayer,
    joinTimeoutMs: 100,
    el: {dataset: {stream: "/hls/live.m3u8"}, querySelector: selector => elements[selector]},
  }

  hook.mounted()
  const first = button.trigger("click")
  t.mock.timers.tick(100)
  assert.equal(hook.attempt.signal.aborted, true)
  assert.equal(streamAudio.paused, true)
  assert.equal(streamAudio.src, undefined)
  assert.equal(streamAudio.resetCount, 1)
  streamAudio.trigger("playing")
  assert.equal(button.dataset.live, "false")

  const second = button.trigger("click")
  const retry = hook.attempt
  pending[0].reject(new Error("The old source was replaced"))
  await first
  assert.equal(hook.attempt, retry)
  assert.equal(hook.connecting, true)
  assert.equal(button.disabled, true)
  t.mock.timers.tick(100)
  assert.equal(retry.signal.aborted, true)
  assert.equal(button.disabled, false)
  assert.equal(streamAudio.resetCount, 2)

  const third = button.trigger("click")
  pending[1].resolve()
  await second
  assert.equal(hook.connecting, true)
  pending[2].resolve()
  await third
  streamAudio.trigger("playing")
  assert.equal(button.dataset.live, "true")
  hook.destroyed()
})

test("ignores hls.js callbacks after abandoning a join", async () => {
  class FakeHls {
    static Events = {MANIFEST_PARSED: "manifest", ERROR: "error"}
    static isSupported() { return true }
    on(event, callback) { this[event] = callback }
    attachMedia() {}
    loadSource() {}
    destroy() { this.destroyed = true }
  }
  const controller = new AbortController()
  const element = audio(false)
  let errors = 0
  const hls = await connectToLiveStream(element, "/hls/live.m3u8", FakeHls, () => errors++, controller.signal)
  controller.abort()
  hls.manifest()
  hls.error(null, {fatal: true})
  assert.equal(hls.destroyed, true)
  assert.equal(element.played, undefined)
  assert.equal(errors, 0)
})

test("moves the Shinkansen volume control in one-percent steps without reconnecting", () => {
  const streamAudio = audio(true)
  const volume = eventTarget({value: "0.65"})
  const elements = {"#volume-control": volume}
  const hook = {
    ...VolumeControl,
    el: {querySelector: selector => elements[selector]},
    audio: streamAudio,
  }

  hook.mounted()
  assert.equal(streamAudio.volume, 0.65)
  volume.value = "0.64"
  volume.trigger("input")
  assert.equal(streamAudio.volume, 0.64)
  hook.destroyed()
  assert.equal(volume.listensTo("input"), false)
})
