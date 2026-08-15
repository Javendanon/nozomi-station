# Threat model — e03 complementary programming

## Assets and boundaries

- Last.fm credentials and optional YouTube session cookies.
- Prepared media files and local filesystem paths.
- PostgreSQL queue state.
- Unauthenticated Liquidsoap control server.
- External Last.fm response data.

## Threats and controls

| Threat | Severity | Control |
|---|---:|---|
| Remote caller controls Liquidsoap | HIGH | Publish control only as `127.0.0.1:1234`; no public/container-wide host binding. |
| Command injection through path or queue name | HIGH | Fixed command names, integer-derived file names, media-root validation, no shell. |
| SSRF through Last.fm candidate data | HIGH | Req URL is a constant HTTPS Last.fm endpoint; candidate values are query parameters only. |
| Malicious or malformed media candidate | HIGH | Parse mocked yt-dlp JSON and apply duration/live checks before preparation. |
| Session cookies leak through Git or logs | HIGH | Ignore `/cookies/`, use local mode `0600`, and never log cookie paths or content. |
| Path traversal escapes media mount | HIGH | Translate only descendants of configured media root and reject `..` paths. |
| Provider hangs periodic worker | MEDIUM | Ten-second HTTP timeout, bounded yt-dlp, Oban retry. |
| Duplicate periodic work downloads indefinitely | MEDIUM | Unique YouTube IDs and unique Oban jobs; margin counts durable active states. |
| Played/skipped track influences future mood | MEDIUM | Mood queries only requests and excludes `skipped`/`failed`; complementary history never feeds mood. |
| Liquidsoap outage loses queue state | MEDIUM | Mark `queued` only after acknowledged push; leave failures `ready`. Full crash recovery is e08. |
| Logs expose credentials or provider bodies | MEDIUM | Log IDs, counts and reason atoms only. |

## Residual risks

- Any local process owned by the host user can access the loopback control port. VPS process isolation and firewall hardening belong to e08.
- Downloading and rebroadcasting public music retains the licensing and provider-ToS risk accepted in product scope.
- A crash between Liquidsoap acknowledgement and PostgreSQL update can duplicate one playback after retry; e08 reconciliation will harden this recovery window.

## Gate

No HIGH risk may remain without an implemented control and executable evidence.
