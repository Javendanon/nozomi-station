#!/usr/bin/env node
// Collects supporting browser evidence, not human listening, in real Chrome: desktop and
// mobile rendering, two consistent windows, a natural track boundary without a
// reload, reduced motion, and the Last.fm card. No dependencies: Node's global
// fetch and WebSocket plus the locally installed Chrome.
//
// Separate processes avoid hidden-tab throttling. A player that buffers without
// advancing its clock is not playback, so neither check can pass on a frozen clock.
// The live manifest is sampled next to the clocks to tell a stalled encoder from a
// stalled client.
//
// Usage: node scripts/verify-player-browser.mjs [--url URL] [--out FILE] [--evidence DIR]

import {spawn} from "node:child_process"
import {mkdirSync, rmSync, writeFileSync} from "node:fs"
import {dirname, join, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const requiredChecks = [
  "desktop_card", "mobile_card", "two_windows", "audio_live", "natural_boundary",
  "two_windows_after_boundary", "reduced_motion", "lastfm_render", "auditory_boundary",
]

export const completionVerdict = checks => {
  if (checks.some(check => check.status === "fail")) return "FAIL"
  return requiredChecks.every(id => checks.some(check => check.id === id && check.status === "pass"))
    ? "PASS" : "INCOMPLETE"
}

export const lastfmRendered = state => {
  let cover
  try { cover = new URL(state.cover) } catch { return false }
  return Boolean(state.album?.trim() && state.tags?.length && state.summary?.trim() &&
    cover.protocol === "https:" && cover.hostname === "lastfm-img.freetls.fastly.net" &&
    state.coverComplete && state.coverWidth > 0 && state.coverHeight > 0)
}

// A buffered, unpaused element is not playback: both clocks must advance between
// two samples taken at least a second apart.
export const liveAudioStatus = (samples, elapsedSeconds) => {
  if (samples.length < 2) return "inconclusive"
  if (samples.some(pair => pair.some(state =>
    state.live !== "true" || state.paused !== false || !(state.bufferedEnd > 0)))) return "fail"
  const advancing = samples.slice(1).every((pair, index) => pair.every((state, windowIndex) =>
    state.currentTime > samples[index][windowIndex].currentTime))
  return advancing && elapsedSeconds >= 1 ? "pass" : "inconclusive"
}

export const boundaryStatus = (samples, elapsedSeconds, reloads) => {
  if (reloads.some(count => count !== 0) || samples.some(pair => pair.some(state =>
    state.marker !== "kept" || state.live !== "true" || state.paused !== false))) return "fail"
  if (elapsedSeconds < 12 || samples.length < 2) return "inconclusive"
  const advancing = samples.slice(1).every((pair, sampleIndex) => pair.every((state, windowIndex) =>
    state.currentTime > samples[sampleIndex][windowIndex].currentTime))
  const enoughPlayback = samples.at(-1).every((state, index) =>
    state.currentTime - samples[0][index].currentTime >= elapsedSeconds * 0.75)
  return advancing && enoughPlayback ? "pass" : "inconclusive"
}

const matchingCards = (first, second) => ["title", "artist", "album", "cover", "tags", "summary"]
  .every(key => JSON.stringify(first[key]) === JSON.stringify(second[key]))

const args = process.argv.slice(2)
const arg = (name, fallback) => {
  const index = args.indexOf(`--${name}`)
  return index === -1 ? fallback : args[index + 1]
}

const pageUrl = arg("url", "http://127.0.0.1:4103/")
const outFile = arg("out", "specs/verifications/e05s01-manual.json")
const evidenceDir = arg("evidence", "specs/verifications/evidence")
const basePort = Number(arg("debug-port", "9333"))
const firstTitle = arg("first-title", "Manual Train A")
const secondTitle = arg("second-title", "Manual Train B")
const boundaryTimeout = Number(arg("boundary-timeout", "90000"))
const realLastfm = process.env.PLAYER_REAL_LASTFM === "1"
const headed = process.env.PLAYER_HEADED === "1"
const streamUrl = arg("stream-url", null)

const chromeBinary =
  process.env.CHROME_BIN ||
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

// The playlist keeps growing even when a browser stops consuming it, so sampling it
// separates a stalled client from a stalled encoder.
// The in-page fetch keeps the browser cache semantics that hls.js sees, so a stale
// manifest behind correct server-side output becomes visible.
const pagePlaylistState = (session, url) => session.eval(`fetch(${JSON.stringify(url)})
  .then(async (response) => ({
    status: response.status,
    cacheControl: response.headers.get("cache-control"),
    text: await response.text(),
  }))
  .then(({status, cacheControl, text}) => ({
    status,
    cacheControl,
    mediaSequence: Number(text.match(/^#EXT-X-MEDIA-SEQUENCE:(\\d+)/m)?.[1] ?? -1),
    segments: (text.match(/^#EXTINF/gm) ?? []).length,
  }))`)

const playlistState = async (url) => {
  try {
    const master = await (await fetch(url, {cache: "no-store"})).text()
    const variant = master.split(/\r?\n/).find((line) => line && !line.startsWith("#"))
    const mediaUrl = variant ? new URL(variant, url).href : url
    const text = variant ? await (await fetch(mediaUrl, {cache: "no-store"})).text() : master
    return {
      mediaUrl,
      mediaSequence: Number(text.match(/^#EXT-X-MEDIA-SEQUENCE:(\d+)/m)?.[1] ?? -1),
      segments: (text.match(/^#EXTINF/gm) ?? []).length,
    }
  } catch (error) {
    return {error: error.message}
  }
}

const waitFor = async (check, timeout, label) => {
  const started = Date.now()

  while (Date.now() - started < timeout) {
    const value = await check()
    if (value) return value
    await sleep(250)
  }

  throw new Error(`timed out waiting for ${label}`)
}

class Session {
  constructor(socket) {
    this.socket = socket
    this.nextId = 0
    this.pending = new Map()
    this.loads = 0

    socket.onmessage = (event) => {
      const message = JSON.parse(event.data)

      if (message.id) {
        const pending = this.pending.get(message.id)
        this.pending.delete(message.id)
        if (message.error) pending.reject(new Error(message.error.message))
        else pending.resolve(message.result)
        return
      }

      if (message.method === "Page.loadEventFired") this.loads += 1
    }
  }

  send(method, params = {}) {
    const id = ++this.nextId
    this.socket.send(JSON.stringify({id, method, params}))

    return new Promise((resolve, reject) => {
      this.pending.set(id, {resolve, reject})
      setTimeout(() => {
        if (this.pending.delete(id)) reject(new Error(`${method} timed out`))
      }, 30_000).unref()
    })
  }

  async eval(expression) {
    const {result, exceptionDetails} = await this.send("Runtime.evaluate", {
      expression,
      awaitPromise: true,
      returnByValue: true,
      userGesture: true,
    })

    if (exceptionDetails) {
      throw new Error(exceptionDetails.exception?.description || exceptionDetails.text)
    }

    return result.value
  }

  async screenshot(path) {
    const {data} = await this.send("Page.captureScreenshot", {format: "png"})
    writeFileSync(path, Buffer.from(data, "base64"))
  }

  close() {
    this.socket.close()
  }
}

const attach = async (port) => {
  const version = await waitFor(
    async () => {
      try {
        const response = await fetch(`http://127.0.0.1:${port}/json/version`)
        return (await response.json()).Browser
      } catch {
        return null
      }
    },
    20_000,
    `Chrome on port ${port}`,
  )

  const response = await fetch(
    `http://127.0.0.1:${port}/json/new?${encodeURIComponent(pageUrl)}`,
    {method: "PUT"},
  )
  const {webSocketDebuggerUrl} = await response.json()
  const socket = new WebSocket(webSocketDebuggerUrl)

  await new Promise((resolve, reject) => {
    socket.onopen = resolve
    socket.onerror = () => reject(new Error(`cannot attach to ${pageUrl}`))
  })

  const session = new Session(socket)
  await session.send("Page.enable")
  await session.send("Runtime.enable")
  await session.send("Emulation.setDeviceMetricsOverride", {
    width: 1440,
    height: 900,
    deviceScaleFactor: 1,
    mobile: false,
  })
  await session.send("Page.navigate", {url: pageUrl})
  await waitFor(
    async () => (await session.eval("document.readyState")) === "complete",
    30_000,
    "the page to load",
  )
  await session.eval("window.__verifyMarker = 'kept'")
  if (streamUrl) {
    await session.eval(`document.querySelector('#radio-player').dataset.stream = ${JSON.stringify(streamUrl)}`)
  }

  return {version, session}
}

const startWindow = async (port, userDataDir) => {
  rmSync(userDataDir, {recursive: true, force: true})

  const chrome = spawn(
    chromeBinary,
    [
      ...(headed ? [] : ["--headless=new", "--mute-audio"]),
      "--disable-gpu",
      "--no-first-run",
      "--no-default-browser-check",
      // Headed windows get occluded and frozen by the OS without these.
      "--disable-backgrounding-occluded-windows",
      "--disable-renderer-backgrounding",
      "--disable-background-timer-throttling",
      "--autoplay-policy=no-user-gesture-required",
      "--window-size=1440,900",
      `--user-data-dir=${userDataDir}`,
      `--remote-debugging-port=${port}`,
      "about:blank",
    ],
    {stdio: "ignore"},
  )

  try {
    return {chrome, ...(await attach(port))}
  } catch (error) {
    chrome.kill()
    throw error
  }
}

const card = `(() => {
  const text = (selector) => document.querySelector(selector)?.textContent?.trim() ?? null
  const audio = document.querySelector("#live-audio")
  return {
    marker: window.__verifyMarker ?? null,
    title: text("#now-playing-title"),
    artist: text("#now-playing-artist"),
    album: text("#now-playing-album"),
    cover: document.querySelector("#now-playing-cover")?.getAttribute("src") ?? null,
    coverComplete: document.querySelector("#now-playing-cover")?.complete ?? false,
    coverWidth: document.querySelector("#now-playing-cover")?.naturalWidth ?? 0,
    coverHeight: document.querySelector("#now-playing-cover")?.naturalHeight ?? 0,
    tags: [...document.querySelectorAll("#now-playing-tags li")].map((tag) => tag.textContent.trim()),
    summary: text("#now-playing-summary"),
    live: document.querySelector("#join-live")?.dataset.live ?? null,
    paused: audio ? audio.paused : null,
    currentTime: audio ? Number(audio.currentTime.toFixed(3)) : null,
    bufferedEnd: audio?.buffered.length
      ? Number(audio.buffered.end(audio.buffered.length - 1).toFixed(3))
      : 0,
    readyState: audio ? audio.readyState : null,
    overflow: document.documentElement.scrollWidth - window.innerWidth,
    cardBottom: document.querySelector("#now-playing")?.getBoundingClientRect().bottom ?? null,
    volumeTop: document.querySelector("#volume-controller")?.getBoundingClientRect().top ?? null,
    joinVisible: Boolean(document.querySelector("#join-live")?.offsetParent),
    cardVisible: Boolean(document.querySelector("#now-playing")?.offsetParent),
    volumeVisible: Boolean(document.querySelector("#volume-controller")?.offsetParent),
  }
})()`

const animationState = `(() => {
  const style = (selector) => {
    const element = document.querySelector(selector)
    return element ? getComputedStyle(element) : {}
  }
  return {
    rails: style(".neo-rails").animationName,
    wave: style("#signal-wave span").animationName,
    joinTransition: style("#join-live").transitionDuration,
  }
})()`

const checks = []
const record = (id, description, status, detail) => {
  checks.push({id, description, status, detail})
  const label = {pass: "PASS", skip: "SKIP", fail: "FAIL", inconclusive: "INCONCLUSIVE"}[status]
  console.log(`${label} ${id}: ${typeof detail === "string" ? detail : JSON.stringify(detail)}`)
}

const main = async () => {
  mkdirSync(evidenceDir, {recursive: true})
  mkdirSync(dirname(outFile), {recursive: true})

  const startedWindows = []
  let desktopShot
  let mobileShot

  try {
    startedWindows.push(await startWindow(basePort, join("tmp", `chrome-player-${basePort}-${process.pid}`)))
    startedWindows.push(await startWindow(basePort + 1, join("tmp", `chrome-player-${basePort + 1}-${process.pid}`)))
    const [first, second] = startedWindows
    const windows = startedWindows.map(window => window.session)
    const states = () => Promise.all(windows.map(window => window.eval(card)))
    await waitFor(
      async () => (await states()).every((state) => state.title === firstTitle),
      30_000,
      "the first card in both windows",
    )

    const [initialFirst, initialSecond] = await states()

    record(
      "desktop_card",
      "Desktop card, join control, and volume control render.",
      initialFirst.cardVisible && initialFirst.joinVisible && initialFirst.volumeVisible &&
        initialFirst.overflow <= 0 && initialFirst.cardBottom <= initialFirst.volumeTop &&
        initialFirst.title === firstTitle
        ? "pass"
        : "fail",
      `title=${initialFirst.title} artist=${initialFirst.artist} overflow=${initialFirst.overflow}px`,
    )

    record(
      "two_windows",
      "Two windows show the same current track.",
      matchingCards(initialFirst, initialSecond) &&
        initialFirst.title === firstTitle
        ? "pass"
        : "fail",
      `first=${initialFirst.title}/${initialFirst.artist} second=${initialSecond.title}/${initialSecond.artist}`,
    )

    for (const window of windows) {
      await window.eval("document.querySelector('#join-live').click()")
    }

    const audioSamples = []
    let audioStatus = "inconclusive"

    try {
      // Joining is only a precondition; the two samples below decide the check.
      await waitFor(
        async () => (await states()).every((state) =>
          state.live === "true" && state.paused === false &&
          state.currentTime > 0 && state.bufferedEnd > 0),
        30_000,
        "a joined, buffered player in both windows",
      )
      audioSamples.push(await states())
      await sleep(1_200)
      audioSamples.push(await states())
      audioStatus = liveAudioStatus(audioSamples, 1.2)
    } catch { /* The samples below keep the suspended clocks visible. */ }

    record(
      "audio_live",
      "Joining advances the playback clock in both windows.",
      audioStatus,
      audioSamples.length
        ? audioSamples.slice(-2).map((sample, index) =>
            `sample${index}: ` + sample.map((window) =>
              `t=${window.currentTime}s buffered=${window.bufferedEnd}s live=${window.live}`).join(", "),
          ).join(" | ")
        : "no sample pair collected: the player never reported a joined, buffered stream",
    )

    const loadsBefore = windows.map(window => window.loads)
    const samples = []
    let boundary = null
    const playlistUrl = new URL(
      streamUrl ?? await first.session.eval("document.querySelector('#radio-player').dataset.stream"),
      pageUrl,
    ).href

    try {
      boundary = await waitFor(
        async () => {
          const current = await states()
          samples.push(current)
          return current.every((state) => state.title === secondTitle) ? current : null
        },
        boundaryTimeout,
        `the natural boundary to ${secondTitle}`,
      )
    } catch (error) {
      record(
        "natural_boundary",
        "A natural track boundary keeps audio live without reloading.",
        "fail",
        error.message,
      )
    }

    if (boundary) {
      // Observe beyond metadata arrival and the six-segment HLS buffer window.
      const postBoundary = [boundary]
      const mediaUrl = (await playlistState(playlistUrl)).mediaUrl
      const playlists = [await playlistState(playlistUrl)]
      const pagePlaylists = [await pagePlaylistState(first.session, mediaUrl)]
      const observedAt = Date.now()
      for (let sample = 0; sample < 15; sample++) {
        await sleep(1_000)
        postBoundary.push(await states())
        playlists.push(await playlistState(playlistUrl))
        pagePlaylists.push(await pagePlaylistState(first.session, mediaUrl))
      }
      const elapsedSeconds = (Date.now() - observedAt) / 1_000
      const reloads = windows.map((window, index) => window.loads - loadsBefore[index])
      const status = boundaryStatus(postBoundary, elapsedSeconds, reloads)
      const uninterrupted = samples.every(pair => pair.every(state =>
        state.live === "true" && state.paused === false && state.marker === "kept"))
      record(
        "natural_boundary",
        "Both playback clocks advance after a natural boundary without reloading.",
        uninterrupted ? status : "fail",
        {elapsedSeconds, reloads, playlistUrl, mediaUrl, playlists, pagePlaylists, postBoundary},
      )
      boundary = postBoundary.at(-1)

      record(
        "two_windows_after_boundary",
        "Both windows show the same card after the boundary.",
        matchingCards(boundary[0], boundary[1]) && boundary.every(state => state.title === secondTitle)
          ? "pass"
          : "fail",
        `first=${boundary[0].title}/${boundary[0].artist} second=${boundary[1].title}/${boundary[1].artist}`,
      )
    }

    desktopShot = join(evidenceDir, "e05s01-player-desktop.png")
    await first.session.screenshot(desktopShot)

    await second.session.send("Emulation.setDeviceMetricsOverride", {
      width: 390,
      height: 844,
      deviceScaleFactor: 2,
      mobile: true,
    })
    await sleep(1_000)
    const mobileState = await second.session.eval(card)
    mobileShot = join(evidenceDir, "e05s01-player-mobile.png")
    await second.session.screenshot(mobileShot)

    record(
      "mobile_card",
      "Mobile viewport renders the player without overflow or overlapping controls.",
      mobileState.cardVisible &&
        mobileState.joinVisible &&
        mobileState.overflow <= 0 &&
        (mobileState.cardBottom === null ||
          mobileState.volumeTop === null ||
          mobileState.cardBottom <= mobileState.volumeTop + 1)
        ? "pass"
        : "fail",
      `width=390 title=${mobileState.title} overflow=${mobileState.overflow}px card-bottom=${mobileState.cardBottom} volume-top=${mobileState.volumeTop} join=${mobileState.joinVisible}`,
    )

    const motion = await second.session.eval(animationState)
    await second.session.send("Emulation.setEmulatedMedia", {
      features: [{name: "prefers-reduced-motion", value: "reduce"}],
    })
    await sleep(500)
    const reduced = await second.session.eval(animationState)

    record(
      "reduced_motion",
      "Reduced motion stops the scene and the wave.",
      reduced.rails === "none" && reduced.wave === "none" && motion.rails !== "none"
        ? "pass"
        : "fail",
      `rails=${motion.rails}→${reduced.rails} wave=${motion.wave}→${reduced.wave} join-transition=${reduced.joinTransition}`,
    )

    if (realLastfm) {
      try {
        await waitFor(async () => lastfmRendered(await first.session.eval(card)), 10_000, "Last.fm cover loading")
      } catch { /* The failed field assertions below retain the actual card state. */ }
    }
    const lastfm = await first.session.eval(card)

    if (realLastfm && lastfmRendered(lastfm)) {
      record(
        "lastfm_render",
        "Real Last.fm album, tags, summary and CDN cover render.",
        "pass",
        lastfm,
      )
    } else if (realLastfm) {
      record(
        "lastfm_render",
        "Real Last.fm album, tags, summary and CDN cover render.",
        "fail",
        lastfm,
      )
    } else {
      record(
        "lastfm_render",
        "Real Last.fm album, tags, summary and CDN cover render.",
        "skip",
        "Real-provider access was not enabled; rerun with PLAYER_REAL_LASTFM=1 and LASTFM_API_KEY.",
      )
    }
    // Capture the final state after the provider image-load assertion.
    await first.session.screenshot(desktopShot)
    await second.session.screenshot(mobileShot)
  } catch (error) {
    record("browser_run", "Browser evidence collection completes.", "fail", error.message)
  } finally {
    record("auditory_boundary", "A human hears uninterrupted audio across the boundary.", "skip",
      "Record a human listening result separately with browser, date and device. Use PLAYER_HEADED=1 for audible windows.")
    const verdict = completionVerdict(checks)
    writeFileSync(
      outFile,
      `${JSON.stringify(
        {
          story_id: "e05s01",
          generated_at: new Date().toISOString(),
          url: pageUrl,
          browser: startedWindows[0]?.version ?? "unavailable",
          mode: `${headed ? "headed audible" : "headless muted"} Chrome; mobile viewport emulation, not a physical device`,
          real_lastfm_enabled: realLastfm,
          viewports: {desktop: "1440x900", mobile: "390x844"},
          evidence: {desktop: desktopShot, mobile: mobileShot},
          checks,
          verdict,
        },
        null,
        2,
      )}\n`,
    )

    console.log(`\n${verdict} → ${outFile}`)
    process.exitCode = verdict === "PASS" ? 0 : verdict === "FAIL" ? 1 : 2
    for (const window of startedWindows) {
      window.session.close()
      window.chrome.kill()
    }
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error)
    process.exitCode = 1
  })
}
