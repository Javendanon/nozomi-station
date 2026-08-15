# Threat model — e05 live player

## Surface area

- Public LiveView receives now-playing updates over Phoenix PubSub.
- Liquidsoap's loopback-only control socket supplies request IDs and trusted local media paths.
- Last.fm `track.getInfo` supplies untrusted JSON text and optional image URLs.
- Browser renders external metadata and plays the existing same-origin HLS stream.

## Risk: medium

The feature crosses two external-data boundaries but adds no authenticated or mutating public endpoint.

## Threats and controls

| Category | Threat | Control |
|---|---|---|
| XSS (CWE-79) | Last.fm biography, titles, or tags contain markup | Render only HEEx text values; never use `raw`, `innerHTML`, or inline scripts |
| SSRF | Provider data controls a server request destination | Keep Req URL fixed to `https://ws.audioscrobbler.com/2.0/`; provider values are query parameters only |
| Remote resource abuse | Provider returns an arbitrary image URL | Accept only HTTPS images from the Last.fm image CDN allowlist; omit all others |
| Command injection | Metadata reaches Liquidsoap control commands | Current-track polling sends only fixed commands and numeric request IDs; media path translation remains bounded |
| Secret exposure | Last.fm API key reaches logs, browser, or Git | Read `LASTFM_API_KEY` from the ignored `.env`; never serialize or log request options |
| Availability coupling | Last.fm or Liquidsoap failure breaks playback | Keep audio hook independent; retain/omit display data and log bounded failures |

## Verification guidance

- Mock all Last.fm and Liquidsoap responses in automated tests; zero network requests.
- Assert unsafe image hosts are removed and markup is rendered as escaped text.
- Assert only fixed queue/control commands are emitted.
- Confirm missing metadata leaves audio controls present.
