# ADR-0005: Durable delivery receipts and playback recovery

## Status

Accepted. Implements NS20 and the restart-reconciliation debt in ADR-0003.

## Decision

Liquidsoap remains the audio scheduler. PostgreSQL owns prepared track metadata
and request status. Liquidsoap owns durable admission, playback position, and
completion evidence. No additional service or dependency is required.

Phoenix sends `radio.enqueue <queue>-<database-id> <queue> <media-path>` instead
of raw queue pushes. The key identifies a delivery, not a file: two requests for
the same file remain distinct. A key cannot change its queue or path.

Each delivery has a JSON receipt in `/recovery`, bind-mounted from
`tmp/radio-recovery`, **outside public HLS storage**. It contains the key, queue,
media path, admission sequence, state (`queued`, `playing`, `played`, `failed`),
and absolute source position in seconds. Atomic replacement uses a temporary
file on the same filesystem.

1. Write queued intent before queue insertion and ACK.
2. Resolve and insert at most once per running engine. A failed resolution
   produces an explicit failed receipt, not a false completion.
3. At track start, persist playing state. Checkpoint consumed source position
   once per second of consumed audio, independent of wall-clock adjustments.
   Persist completion at the track boundary.
4. On engine startup, parse receipts and rebuild unfinished queues in admission
   order. Put interrupted audio in a private resume queue above both normal
   queues, using `liq_cue_in` to seek to its saved position. A switch gates the
   normal queues until recovery finishes: asynchronous decoder readiness must
   not let a faster pending track displace the interrupted audio. Requested
   tracks still precede complementary tracks at subsequent boundaries.
5. Return the existing receipt for every retry, including after completion.
   Phoenix maps playing/queued receipts to queued status and only marks played
   on explicit completion. A missing volatile request ID is never completion.

The supervised Phoenix scheduler polls at startup and every 2 seconds. It uses
`FOR UPDATE SKIP LOCKED` inside a transaction to serialize overlapping scheduler
runs for each row. A control error rolls back DB changes, not Liquidsoap intent;
retrying is safe because the delivery key and receipt survive the rollback.
The existing worker remains available for explicit runs; its minute cron entry
is removed. `radio.current` exposes the actual streaming key, media path, live
position, and resume offset, including the private queue. Now-playing display
uses that snapshot rather than guessing from prefetched request IDs.

## Failure behavior

| Failure point | Recovery |
| --- | --- |
| Before durable intent | DB stays ready; next poll admits it. |
| After intent, before queue insertion/ACK | A retry admits it, or engine startup restores it. |
| After ACK, before DB commit | DB may still say ready; the same key returns the existing receipt without another push. |
| ACK lost while audio finishes | Retained played receipt reconciles the ready row without replay. |
| Phoenix restart | Engine continues; startup polling reconciles statuses. |
| Liquidsoap restart, with or without Phoenix | Journal rebuilds queues and resumes the interrupted track. |
| Completion before DB update | Played receipt survives either restart and prevents replay. |
| Control outage | DB remains unchanged; engine continues its queues and sine fallback. |
| Invalid media | Explicit failed receipt; remaining audio and sine fallback remain available. |
| Malformed journal JSON | Fail startup rather than silently discard recovery state. |

## Measurable tolerance

**Near means at most 2.000 seconds of source-position rewind per abrupt engine
restart** on the supported local AAC files. The budget covers the 1-second
checkpoint interval plus decoder/frame and filesystem scheduling allowance.
Downtime is not added to the source position: recovery resumes the interrupted
song, not the wall-clock schedule. A Phoenix-only restart must not reset or
rewind source position. This is a source-position target, not an end-to-end
browser latency guarantee; HLS clients retain their existing live-window delay.

The recovery script samples `radio.current` immediately before SIGKILL and
compares that position with the restored cue-in offset. It fails above 2 seconds
and prints both positions and the measured difference. At a crash exactly at a
track boundary, the last checkpoint may replay up to that same tolerance; no
distributed transaction can make audible samples atomic with filesystem writes.

## Operations and limits

- Create `tmp/radio-recovery` before Compose startup and grant the configured
  Liquidsoap UID write access, just as for the HLS output directory.
- Back up PostgreSQL, receipts, and media together. Never clear receipts while
  their database is in use, reset DB identities against old receipts, or share
  one journal between independent engines/databases.
- Keep local media until its delivery is complete. Temporary-media cleanup is
  outside this card; do not delete unfinished media during cleanup.
- Completion receipts are deliberately retained without a time-based expiry.
  Storage, the in-memory admission list, and startup work grow with delivery
  count; add DB-confirmed receipt
  compaction when needed, not an expiry that can duplicate unacknowledged audio.
- The journal covers process crashes and restarts on retained local storage.
  Atomic rename is not a host-power-loss/fsync guarantee. Disk loss, DB loss,
  arbitrary manual raw pushes/skips, and multiple audio-engine writers are not
  covered by this protocol. Raw pushes remain only for local audio smoke checks.
- On first deployment, restart Liquidsoap with this script before enabling the
  new scheduler. Legacy queued rows without checkpoints replay from the start;
  future deliveries have durable receipts and position checkpoints.

## Verification

`bash scripts/verify-radio-recovery.sh` runs against disposable PostgreSQL and
Liquidsoap containers with loopback-only ephemeral ports. It uses local images
and generated AAC audio, no external music/Slack/Last.fm services. It kills the
Phoenix VM after an ACK before DB commit, reconciles on restart, repeats the
same admission, restarts Phoenix during playback, SIGKILLs Liquidsoap, measures
cue-in recovery, verifies four distinct deliveries (including shared media),
checks persisted completion against DB state, and checks continued HLS fallback.
A final engine restart must not replay any completed item.

Deterministic reconciliation tests inject control I/O and use the SQL sandbox;
new tests do not contact a network service. Existing local TCP framing tests
remain separate from these recovery scenarios.
