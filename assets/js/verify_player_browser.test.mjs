import assert from "node:assert/strict"
import test from "node:test"
import {boundaryStatus, completionVerdict, lastfmRendered, liveAudioStatus} from "../../scripts/verify-player-browser.mjs"

const card = {
  marker: "kept", live: "true", paused: false, currentTime: 10,
  album: "Substance 1987", tags: ["new wave"], summary: "Track information.",
  cover: "https://lastfm-img.freetls.fastly.net/i/u/300x300/cover.png",
  coverComplete: true, coverWidth: 300, coverHeight: 300,
}

const checks = ["desktop_card", "mobile_card", "two_windows", "audio_live", "natural_boundary",
  "two_windows_after_boundary", "reduced_motion", "lastfm_render", "auditory_boundary"]
  .map(id => ({id, status: "pass"}))

test("mandatory skipped, inconclusive or absent checks cannot close manual verification", () => {
  assert.equal(completionVerdict(checks), "PASS")
  for (const id of ["lastfm_render", "auditory_boundary", "natural_boundary"]) {
    for (const status of ["skip", "inconclusive"]) {
      assert.equal(completionVerdict(checks.map(check => check.id === id ? {...check, status} : check)), "INCOMPLETE")
    }
    assert.equal(completionVerdict(checks.filter(check => check.id !== id)), "INCOMPLETE")
  }
  assert.equal(completionVerdict([{id: "browser_run", status: "fail"}]), "FAIL")
})

test("joining only counts as live audio when both clocks actually advance", () => {
  const playing = {...card, currentTime: 0.018, bufferedEnd: 5.921, readyState: 4}
  const before = [playing, playing]
  const advancing = [
    {...playing, currentTime: 1.4},
    {...playing, currentTime: 2.2},
  ]

  assert.equal(liveAudioStatus([before, [playing, playing]], 1.2), "inconclusive")
  assert.equal(liveAudioStatus([before, [advancing[0], playing]], 1.2), "inconclusive")
  assert.equal(liveAudioStatus([before, advancing], 1.2), "pass")
  assert.equal(liveAudioStatus([before, advancing], 0.2), "inconclusive")
  assert.equal(liveAudioStatus([before], 5), "inconclusive")
  for (const broken of [{live: "false"}, {paused: true}, {bufferedEnd: 0}]) {
    assert.equal(liveAudioStatus([before, [{...advancing[0], ...broken}, advancing[1]]], 1.2), "fail")
  }
})

test("the boundary requires both playback clocks after the transition, not buffer growth", () => {
  const samples = Array.from({length: 16}, (_, second) => [
    {...card, currentTime: 10 + second, bufferedEnd: 30 + second},
    {...card, currentTime: 20 + second, bufferedEnd: 40 + second},
  ])
  assert.equal(boundaryStatus(samples, 15, [0, 0]), "pass")
  const suspended = samples.map(pair => [pair[0], {...pair[1], currentTime: 20}])
  assert.equal(boundaryStatus(suspended, 15, [0, 0]), "inconclusive")
  assert.equal(boundaryStatus(samples.slice(0, 2), 1, [0, 0]), "inconclusive")
  assert.equal(boundaryStatus(samples, 15, [0, 1]), "fail")
  for (const change of [{live: "false"}, {paused: true}, {marker: null}]) {
    const interrupted = samples.map(pair => pair.map(state => ({...state, ...change})))
    assert.equal(boundaryStatus(interrupted, 15, [0, 0]), "fail")
  }
})

test("Last.fm needs an album and an allowlisted image that actually loaded", () => {
  assert.equal(lastfmRendered(card), true)
  for (const missing of [
    {album: null}, {album: " "}, {tags: []}, {summary: ""},
    {cover: null}, {cover: "https://example.com/cover.png"},
    {cover: "http://lastfm-img.freetls.fastly.net/cover.png"},
    {coverComplete: false}, {coverWidth: 0}, {coverHeight: 0},
  ]) assert.equal(lastfmRendered({...card, ...missing}), false)
})
