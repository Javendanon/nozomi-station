# Security review — e03s01 complementary programming

## Verdict

**PASS** — no unresolved HIGH findings.

## Scope

Full `main...HEAD` branch diff: Last.fm recommendations, complementary persistence, periodic Oban jobs, Liquidsoap control client and queues, Docker publication, runtime configuration, migrations, scripts, and tests.

## Findings

### External providers — PASS

- Last.fm requests use the constant HTTPS endpoint `https://ws.audioscrobbler.com/2.0/`.
- Candidate artist and title values are query parameters, never URL hosts.
- Redirects are disabled and receive timeout is ten seconds.
- Malformed candidate entries are discarded rather than executed or persisted.
- Every candidate passes existing YouTube duration and live-stream validation before yt-dlp.
- No provider response body or token is logged.

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
- yt-dlp still receives an argument vector without a shell and retains its timeout and size limit.
- Temporary cleanup after playback remains assigned to e08 and is not weakened here.

### Persistence and scheduling — PASS

- Unique YouTube IDs prevent repeated complementary selection, including skipped tracks.
- The request partial unique index now includes `queued`, closing the dispatch duplicate window.
- Scheduler state changes occur only after an acknowledged Liquidsoap push.
- Provider or control failures preserve retryable durable state.
- Oban jobs are unique within their one-minute cadence.

### Secrets and dependencies — PASS

- `LASTFM_API_KEY` is required only through runtime environment configuration.
- No credential values, private keys, package additions, unsafe deserialization, raw SQL interpolation, or dynamic atoms appear in the diff.
- `npm audit --omit=dev`: zero vulnerabilities.
- `mix hex.audit`: no retired packages.

## Residual risks

- Other processes running as the same VPS user can access the loopback control port. Process isolation and firewall hardening belong to e08.
- A crash between control acknowledgement and database update may replay one file. ADR-0003 assigns exact crash reconciliation to e08.
- Music licensing and provider terms remain the accepted product-level risk.

## Evidence

- `specs/security/epics/e03/THREAT_MODEL.md`
- `specs/verifications/e03s01-verify.yaml`
- `specs/verifications/NFR-e03s01.json`
- `scripts/verify-programming-priority.sh`
