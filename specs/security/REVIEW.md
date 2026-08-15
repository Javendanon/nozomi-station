# Security review — e03s01 complementary programming

## Verdict

**PASS** — no unresolved HIGH findings.

## Scope

Full `main...HEAD` branch diff: Last.fm recommendations, yt-dlp JSON and cookie handling, complementary persistence, periodic Oban jobs, Liquidsoap control queues, runtime configuration, migrations, scripts, and tests.

## Findings

### External providers — PASS

- Last.fm requests use the constant HTTPS endpoint `https://ws.audioscrobbler.com/2.0/`.
- Last.fm candidate values enter a bounded `ytsearch1:` argument, never a shell or URL host.
- Redirects are disabled for HTTP providers and all external work has explicit timeout bounds.
- yt-dlp receives argument vectors only; YouTube IDs are allowlisted and searches are capped at 500 bytes.
- Missing or malformed yt-dlp JSON is discarded rather than executed or persisted.
- Every candidate passes duration and live-stream validation before preparation.
- No provider response, cookie value, or token is logged.

### Liquidsoap control — PASS

- Docker publishes exactly one control port as `127.0.0.1:1234:1234`.
- Liquidsoap binds inside its container; no host-public interface is exposed.
- Queue names are compile-time atoms restricted to `requested` and `complementary`.
- Metadata commands accept only numeric request IDs returned by Liquidsoap.
- Media paths must be descendants of the configured root and reject traversal, whitespace, and line breaks.
- Control responses must terminate correctly and are parsed without atom creation or code evaluation.
- TCP calls have a one-second timeout and one bounded retry.

### Filesystem and process execution — PASS

- Complementary filenames use integer database IDs (`c<ID>.m4a`).
- Liquidsoap receives the media mount read-only.
- yt-dlp uses one shared runner for metadata and downloads, without a shell, with timeout and size limits.
- Preparation removes any stale target before execution, preventing false success after database resets.
- Temporary cleanup after playback remains assigned to e08 and is not weakened here.

### Persistence and scheduling — PASS

- Unique YouTube IDs prevent repeated complementary selection, including skipped tracks.
- The request partial unique index now includes `queued`, closing the dispatch duplicate window.
- Scheduler state changes occur only after an acknowledged Liquidsoap push.
- Provider or control failures preserve retryable durable state.
- Oban jobs are unique within their one-minute cadence.

### Secrets and dependencies — PASS

- `LASTFM_API_KEY` is required only through runtime environment configuration; no YouTube API key is required.
- `/cookies/` is ignored by Git; the copied jar is mode `0600` and never enters the diff.
- Tests use injected runners and local fixtures with zero network requests.
- No credential values, private keys, package additions, unsafe deserialization, raw SQL interpolation, or dynamic atoms appear in the diff.
- `npm audit --omit=dev`: zero vulnerabilities.
- `mix hex.audit`: no retired packages.

## Residual risks

- Other processes running as the same VPS user can access the loopback control port. Process isolation and firewall hardening belong to e08.
- A crash between control acknowledgement and database update may replay one file. ADR-0003 assigns exact crash reconciliation to e08.
- Session cookies can expire or trigger stricter YouTube behavior; removing the cookie configuration restores anonymous yt-dlp access.
- Music licensing and provider terms remain the accepted product-level risk.

## Evidence

- `specs/security/epics/e03/THREAT_MODEL.md`
- `specs/verifications/e03s01-verify.yaml`
- `specs/verifications/NFR-e03s01.json`
- `scripts/verify-programming-priority.sh`
