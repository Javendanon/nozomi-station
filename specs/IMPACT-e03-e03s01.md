---
type: impact
context: infra
story_id: e03s01
---

# Impact — e03s01 complementary programming

## Blast radius

| Area | Change | Risk | Coverage |
|---|---|---:|---|
| `requests` persistence | Add `queued` to active uniqueness and scheduler lifecycle | High | Existing request-flow tests plus scheduler tests |
| Media preparation | Namespace complementary output names without changing request paths | Medium | Preparer behavior through queue tests |
| PostgreSQL | Add `complementary_tracks` and indexes | High | DataCase tests and migration CI |
| Liquidsoap | Replace direct sine source with requested/complementary queues and sine fallback | High | Real config/HLS verification and priority script |
| Docker Compose | Mount prepared media and bind control to host loopback | High | Priority script and compose inspection |
| Oban | Add periodic fill and dispatch workers | Medium | Worker public-interface tests |
| External APIs | Add fixed-host Last.fm requests | High | Deterministic response and host tests |
| Runtime config | Require Last.fm key in production | Medium | config compile and README |

## Dependents

- Slack `RequestFlow` creates records consumed by the new scheduler.
- e04 will decorate the Liquidsoap source created here.
- e07 will write `skipped`; complementary selection must already exclude it.
- e08 will reconcile queues after process restart and remove played files.

## Main failure modes

1. A duplicate request enters after status changes to `queued`.
2. A request interrupts rather than follows a complementary track.
3. Liquidsoap control is reachable beyond loopback.
4. Played complementary rows remain counted forever and prevent refill.
5. Last.fm response data bypasses YouTube duration/live validation.
6. Container media paths differ from Phoenix paths.

## Guardrails

- Partial unique index includes `queued`.
- Liquidsoap owns priority through track-sensitive `fallback`.
- Host publication is explicitly `127.0.0.1` and the app applies command allowlists.
- Scheduler reconciles active Liquidsoap request metadata before dispatch.
- Existing Resolver validates every candidate.
- One configured media-root mapping translates paths and rejects traversal.

## Verdict

Proceed with TDD. This is a high-blast-radius shared-boundary change; HLS integration is mandatory before review.
