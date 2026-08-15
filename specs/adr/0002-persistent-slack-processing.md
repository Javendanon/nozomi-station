# ADR-0002: Process Slack requests with PostgreSQL and Oban

## Status

Accepted

## Context

Slack requires webhook acknowledgement within three seconds, may retry deliveries, and cannot wait for provider metadata or media preparation. Request state must survive application restarts.

An in-memory task queue would acknowledge quickly but lose idempotency, retries, and prepared-request state after a crash.

## Decision

Phoenix verifies and records each Slack `event_id` in PostgreSQL before acknowledging it. A unique database constraint makes event acceptance idempotent.

Oban processes accepted events asynchronously and supplies persistent retries. Request metadata and queue state use the same PostgreSQL repository.

External provider and downloader calls remain outside the webhook request. Their boundaries are passed as functions in tests rather than wrapped in speculative service abstractions.

## Consequences

- PostgreSQL becomes a runtime dependency.
- Slack acknowledgements perform one short database transaction.
- Duplicate events cannot create duplicate jobs.
- Provider outages do not block Slack acknowledgements.
- Deployment and CI must provide PostgreSQL and run migrations.
