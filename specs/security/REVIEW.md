# Security review: e02s01 Slack requests

## Scope

Diff `main...ae79d51` covering the Slack webhook, signature verification, PostgreSQL event/request persistence, Oban worker, Spotify/YouTube clients, `yt-dlp` preparation, runtime configuration, and CI.

## Verdict

**PASS** — no unresolved HIGH findings with confidence 8 or greater.

## Trust-boundary review

### Slack webhook

- Signature uses HMAC-SHA256 over the exact raw body and Slack timestamp.
- Constant-time comparison is used after a length check.
- Requests older or newer than five minutes are rejected.
- Missing headers or signing secret fail closed.
- A unique PostgreSQL constraint and one transaction prevent duplicate events or orphaned jobs.

### External HTTP

- User URLs are parsed into validated provider identifiers.
- Req calls use fixed Slack, Spotify, and Google API hosts.
- Redirect following is disabled.
- Request timeouts are bounded.
- Provider credentials come from runtime environment variables and are not logged.

### Process and filesystem

- `yt-dlp` receives an argument vector through `System.cmd`; no shell evaluates user input.
- Output paths derive only from database integer IDs.
- A request becomes ready only when the expected file exists.
- Media execution is bounded to 120 seconds and failures release the active duplicate guard.

### Data and persistence

- Ecto queries are parameterized; no raw SQL contains attacker input.
- Event payloads are stored as JSON maps, not deserialized executable terms.
- Active duplicate exclusion is enforced with a partial unique database index.

## Automated evidence

- `npm audit --omit=dev`: zero vulnerabilities.
- `mix hex.audit`: no retired packages.
- Secret-pattern and unsafe-sink scan: clean.
- 31 Elixir tests and 3 JavaScript tests pass.
- Product-module line coverage: 90.91%.
- Signed cold-start UAT: duplicate deliveries produced one event and one Oban job; acknowledgements completed in 0.043 seconds or less.

## Residual risks

- Real Slack, Spotify, YouTube, and `yt-dlp` smoke testing requires credentials and a permitted media source. Tests use deterministic boundary fakes.
- Downloading and retransmitting third-party media retains the licensing and terms-of-service risk accepted in product scope.

Neither residual item is an exploitable code vulnerability. No security exception is required.
