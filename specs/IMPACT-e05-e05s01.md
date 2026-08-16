# Impact — e05 / e05s01

## Target

`RadioLive`, `LiquidsoapClient`, `Lastfm`, `Request`, and `RequestProcessor` gain a shared now-playing read path, enriched presentation, and an optional listener message extracted from Slack.

## Purpose, callers, contracts

- `RadioLive` owns the public listener UI; called by the `/` live route and exercised by `RadioLiveTest`. It must keep explicit autoplay consent and same-origin HLS playback.
- `LiquidsoapClient` owns the loopback text protocol; called by `Scheduler`, `SchedulerWorker`, and the new now-playing poller. It must send allowlisted commands, bound timeouts, and translate only paths under configured media roots.
- `Lastfm` owns the fixed-host read-only provider boundary; called by `RefillWorker` and the new now-playing poller. It must use the configured API key, bounded Req options, and tolerate malformed/error responses.

## Dependents

- `lib/nozomi_station/application.ex`: supervises the single poller.
- `lib/nozomi_station/requests/request_flow.ex`: persists the nullable, bounded listener message supplied by `RequestProcessor`.
- `lib/nozomi_station/programming/scheduler.ex`: retains existing `active_paths/0` behavior.
- `lib/nozomi_station/programming/refill_worker.ex`: retains recommendation behavior.
- `assets/js/radio_player.mjs`: retains native HLS/hls.js join and cleanup contracts.
- `config/liquidsoap/radio.liq`: queue command names define current-track detection.

## Affected stories

- e01s01: existing live playback must not regress.
- e03s01: queue reconciliation and Last.fm recommendations must not regress.
- e05s01: owns now-playing metadata and visual presentation.

## Test coverage

- Existing: `liquidsoap_client_test.exs`, `scheduler_test.exs`, `mood_test.exs`, `radio_live_test.exs`, and `radio_player.test.mjs`.
- Add: current request detection, singleton update/failure behavior, Last.fm metadata parsing and image allowlist, LiveView PubSub rendering, reduced-motion visual contract.
- Gap accepted: final background video and real Last.fm smoke require a supplied asset and populated local API key.

## Risk: Medium (7/10)

Fan-in is moderate and the change crosses Liquidsoap and Last.fm, but both boundaries already exist and are mockable without network access.

## Recommended action

Proceed with vertical TDD slices. Keep the audio hook independent, use one supervised poller with existing PubSub, and add no dependencies.
