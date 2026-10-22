---
type: impact-analysis
context: NS20 broadcast recovery, e08s01 task 2
---

# NS20: Durable broadcast recovery

## Target

`Scheduler`, `LiquidsoapClient`, and `config/liquidsoap/radio.liq`.

## Dependents

- `SchedulerWorker` dispatches through the scheduler.
- `NowPlaying` reads current media paths through the control client.
- `RequestFlow`, `ComplementaryQueue`, and `Mood` consume ready/queued/played states.
- HLS and programming-priority verification scripts use the existing raw queue commands.

## Affected stories

- e03s01: requested/complementary dispatch and priority.
- e05s01: current-track display.
- e08s01 task 2: autonomous recovery (this card does not include temporary-media cleanup).

## Risk: High

A missing request is not proof of completion. Retrying a raw push after a lost ACK can duplicate audio. The control protocol needs a durable idempotency receipt, not more path-based heuristics.

## Plan and test coverage

1. Replace scheduler raw pushes/absence reconciliation with stable delivery keys (`requested-ID`, `complementary-ID`). Test ACK-before-DB failure, lost ACK, unavailable control, completion, and repeated reconciliation using injected control I/O, without network.
2. Persist each Liquidsoap delivery's path, queue, state, and position in an atomic journal outside the public HLS directory. ACK only after durable intent and queue insertion. Retain completion receipts; replay unfinished deliveries on Liquidsoap startup, interrupted track first, using cue-in metadata.
3. Checkpoint playback every second. Define near as at most 2 seconds of source-position rewind (1-second checkpoint plus decoder/frame allowance); report measured rewind in the integration check. Downtime is not added to the position.
4. Poll scheduling at startup and every 2 seconds under supervision. Serialize dispatch with database row locks; fail closed on control/journal errors and preserve the sine fallback.
5. Add `scripts/verify-radio-recovery.sh`: isolated local services, generated audio, Phoenix process restart, Liquidsoap SIGKILL/restart, failure after ACK, completion reconciliation, fallback, and measured source-position error. No external providers.
6. Run targeted tests, `mix precommit`, Liquidsoap syntax validation, and recovery integration; commit on the supplied task branch.

Existing scheduler/client tests cover order, path translation, unavailable control, and local protocol framing. They do not cover restart epochs, position restoration, or durable ACK reconciliation. Existing state.yaml describes an older completed player task; the explicit NS20 card and supplied branch govern this work. `docs/reglas-de-codigo.md` is absent from this worktree.
