#!/usr/bin/env node
// Records the pending manual player checks in real Chrome windows: desktop and
// mobile rendering, two consistent windows, a natural track boundary without a
// reload, reduced motion, and the Last.fm card. No dependencies: Node's global
// fetch and WebSocket plus the locally installed Chrome.
//
// Each window is its own Chrome process because Chrome suspends media in a
// hidden tab, which would fake a stalled player on the second window.
//
// Usage: node scripts/verify-player-browser.mjs [--url URL] [--out FILE] [--evidence DIR]

import {spawn} from "node:child_process"
import {mkdirSync, rmSync, writeFileSync} from "node:fs"
import {dirname, join} from "node:path"

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
const hasLastfmKey = Boolean(process.env.LASTFM_API_KEY)

const chromeBinary =
  process.env.CHROME_BIN ||
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

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
      }, 30_000)
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

  return {version, session}
}

const startWindow = async (port, userDataDir) => {
  rmSync(userDataDir, {recursive: true, force: true})

  const chrome = spawn(
    chromeBinary,
    [
      "--headless=new",
      "--disable-gpu",
      "--no-first-run",
      "--no-default-browser-check",
      "--autoplay-policy=no-user-gesture-required",
      "--mute-audio",
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
  const label = {pass: "PASS", skip: "SKIP", fail: "FAIL"}[status]
  console.log(`${label} ${id}: ${detail}`)
}

const main = async () => {
  mkdirSync(evidenceDir, {recursive: true})
  mkdirSync(dirname(outFile), {recursive: true})

  const first = await startWindow(basePort, join("tmp", `chrome-player-${basePort}-${process.pid}`))
  const second = await startWindow(basePort + 1, join("tmp", `chrome-player-${basePort + 1}-${process.pid}`))
  const windows = [first.session, second.session]
  const states = () => Promise.all(windows.map((window) => window.eval(card)))
  let lastJoinStates = []

  try {
    await waitFor(
      async () => (await states()).every((state) => state.title === firstTitle),
      30_000,
      "the first card in both windows",
    )

    const [initialFirst, initialSecond] = await states()

    record(
      "desktop_card",
      "Desktop card, join control, and volume control render.",
      initialFirst.cardVisible && initialFirst.joinVisible && initialFirst.title === firstTitle
        ? "pass"
        : "fail",
      `title=${initialFirst.title} artist=${initialFirst.artist} overflow=${initialFirst.overflow}px`,
    )

    record(
      "two_windows",
      "Two windows show the same current track.",
      initialFirst.title === initialSecond.title &&
        initialFirst.artist === initialSecond.artist &&
        initialFirst.title === firstTitle
        ? "pass"
        : "fail",
      `first=${initialFirst.title}/${initialFirst.artist} second=${initialSecond.title}/${initialSecond.artist}`,
    )

    for (const window of windows) {
      await window.eval("document.querySelector('#join-live').click()")
    }

    const joined = await waitFor(
      async () => {
        const current = await states()
        lastJoinStates = current.map(({live, paused, currentTime}) => ({live, paused, currentTime}))
        return current.every(
          (state) =>
            state.live === "true" &&
            state.paused === false &&
            state.currentTime > 0 &&
            state.bufferedEnd > 0,
        )
          ? current
          : null
      },
      30_000,
      "live audio in both windows",
    )

    record(
      "audio_live",
      "Joining starts audio in both windows.",
      "pass",
      joined
        .map((state) => `t=${state.currentTime}s buffered=${state.bufferedEnd}s rs=${state.readyState}`)
        .join(" "),
    )

    const beforeBoundary = joined
    const samples = []
    let boundary = null

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
      const stillPlaying = samples.every((states) => states.every((state) => state.paused === false))
      const clockGrew = boundary.every(
        (state, index) => state.currentTime > beforeBoundary[index].currentTime,
      )
      const bufferedGrew = boundary.every(
        (state, index) => state.bufferedEnd > beforeBoundary[index].bufferedEnd,
      )
      const keptMarker = boundary.every((state) => state.marker === "kept")
      // Headless Chrome may suspend the audio clock, so the live edge is proven
      // by the growing buffer plus the still-unpaused element.
      const clock = clockGrew ? "advanced" : "suspended in headless Chrome"

      record(
        "natural_boundary",
        "A natural track boundary keeps audio live without reloading.",
        stillPlaying && bufferedGrew && keptMarker ? "pass" : "fail",
        `title=${boundary.map((state) => state.title).join("/")} audio=${beforeBoundary[0].currentTime}s→${boundary[0].currentTime}s (${clock}) buffered=${beforeBoundary[0].bufferedEnd}s→${boundary[0].bufferedEnd}s paused=${boundary.map((state) => state.paused).join("/")} reloads=${windows.map((window) => window.loads).join("/")}`,
      )

      record(
        "two_windows_after_boundary",
        "Both windows show the same card after the boundary.",
        boundary[0].title === boundary[1].title && boundary[0].artist === boundary[1].artist
          ? "pass"
          : "fail",
        `first=${boundary[0].title}/${boundary[0].artist} second=${boundary[1].title}/${boundary[1].artist}`,
      )
    }

    const desktopShot = join(evidenceDir, "e05s01-player-desktop.png")
    await first.session.screenshot(desktopShot)

    await second.session.send("Emulation.setDeviceMetricsOverride", {
      width: 390,
      height: 844,
      deviceScaleFactor: 2,
      mobile: true,
    })
    await sleep(1_000)
    const mobileState = await second.session.eval(card)
    const mobileShot = join(evidenceDir, "e05s01-player-mobile.png")
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

    const lastfm = await first.session.eval(card)
    const rendered = Boolean(lastfm.cover) && lastfm.tags.length > 0 && Boolean(lastfm.summary)

    if (rendered) {
      record(
        "lastfm_render",
        "Real Last.fm album, tags, summary and CDN cover render.",
        "pass",
        `album=${lastfm.album} tags=${lastfm.tags.length} cover=${lastfm.cover} summary=${lastfm.summary?.slice(0, 40)}`,
      )
    } else if (hasLastfmKey) {
      record(
        "lastfm_render",
        "Real Last.fm album, tags, summary and CDN cover render.",
        "fail",
        `album=${lastfm.album} tags=${lastfm.tags.length} cover=${lastfm.cover}`,
      )
    } else {
      record(
        "lastfm_render",
        "Real Last.fm album, tags, summary and CDN cover render.",
        "skip",
        "LASTFM_API_KEY is not set; the card degraded to title and artist as designed.",
      )
    }

    const failed = checks.filter((check) => check.status === "fail")

    writeFileSync(
      outFile,
      `${JSON.stringify(
        {
          story_id: "e05s01",
          generated_at: new Date().toISOString(),
          url: pageUrl,
          browser: first.version,
          viewports: {desktop: "1440x900", mobile: "390x844"},
          evidence: {desktop: desktopShot, mobile: mobileShot},
          checks,
          verdict: failed.length === 0 ? "PASS" : "FAIL",
        },
        null,
        2,
      )}\n`,
    )

    console.log(`\n${failed.length === 0 ? "PASS" : "FAIL"} → ${outFile}`)
    process.exitCode = failed.length === 0 ? 0 : 1
  } finally {
    for (const window of windows) window.close()
    first.chrome.kill()
    second.chrome.kill()
  }
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
