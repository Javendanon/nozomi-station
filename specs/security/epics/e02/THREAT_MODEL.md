# Threat model: e02 Slack requests

## Scope

Slack Events API ingestion, asynchronous request processing, YouTube and Spotify link resolution, media preparation, deduplication, and threaded Slack confirmation.

## Risk

**HIGH** — an unauthenticated public webhook accepts attacker-controlled bodies and URLs, then reaches external HTTP services and media preparation tools.

## Trust boundaries

1. Internet → Phoenix Slack webhook.
2. Slack event body → background request processor.
3. User URL → media resolver.
4. Resolver metadata → downloader and local filesystem.
5. Application → Slack, Spotify, and YouTube APIs.

## Required controls

### Slack authenticity and replay

- Verify `X-Slack-Signature` as HMAC-SHA256 over the exact raw request body.
- Compare signatures in constant time.
- Reject timestamps older than five minutes.
- Require configured signing secrets; never fail open.
- Process each Slack `event_id` once, including retries delivered concurrently.
- Return Slack's acknowledgement before external resolution or download work.

### URL and network safety

- Accept only HTTPS URLs from explicit Spotify and YouTube host allowlists.
- Parse URLs and extract provider IDs before making network requests.
- Call fixed provider API hosts; never pass the original user URL to a general HTTP client.
- Do not follow user-controlled redirects to arbitrary hosts.
- Do not trust event-provided callback URLs unless their host is independently fixed or validated.

### Process and filesystem safety

- Never interpolate user input into a shell command.
- Pass downloader arguments as an argument vector and construct URLs from validated provider IDs.
- Generate output paths internally; never derive paths from titles or user filenames.
- Validate duration and live-stream status before downloading.
- Keep prepared files outside source and configuration directories.

### Secrets and data exposure

- Load Slack and provider credentials from runtime environment variables.
- Do not log tokens, signing secrets, signatures, or complete request bodies.
- Thread responses may include titles and rejection reasons, but not internal paths or upstream error bodies.

## Abuse and reliability controls

- Bound accepted event and URL counts even though product quotas are out of scope.
- Apply timeouts to all external requests.
- Retry only transient provider failures with bounded backoff.
- Keep acknowledgement independent from downstream availability.

## Verification guidance

- Valid, invalid, stale, and malformed Slack signatures.
- Duplicate and concurrent delivery of one `event_id`.
- Provider-host confusion, non-HTTPS URLs, redirects, and malformed IDs.
- Live streams, tracks over 15 minutes, duplicate tracks, and unsafe titles.
- Missing credentials must stop integration startup or return a controlled error.

## Findings

No implementation exists yet. The controls above are release requirements; unresolved signature, replay, SSRF, command-injection, or path-traversal paths are blocking findings.
