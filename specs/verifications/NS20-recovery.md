---
type: verification
context: NS20, card bd4f12b6-596b-4287-87bd-1794952b9ea3
---

# NS20 recovery verification

## Result: PASS

### Rework after review

The review requested changes; this revision addresses all seven findings.

- Per-item control errors no longer abort the batch. Control I/O runs outside the
  transaction and each row's status commits in its own short transaction, so a
  permanently failing delivery cannot block or roll back its siblings.
- Transient resolve failures stay retryable. Only definitively absent media gets
  a `failed` receipt; `enqueue` re-attempts failed receipts, and Phoenix never
  drops the row on a delivery failure.
- The Liquidsoap delivery validator reads `RADIO_MEDIA_DIR` instead of a hardcoded
  `/media`, exported by Compose from `LIQUIDSOAP_MEDIA_DIR`.
- Phoenix validates only the path relative to `MEDIA_DIR`, so a host media root
  containing spaces no longer breaks deliveries.
- Startup resumes only the newest `playing` receipt and demotes older ones to
  `queued`, preventing a boundary crash from stranding audio.
- Re-confirmation no longer holds `FOR UPDATE` locks across control round trips.
- Only `DBConnection.ConnectionError` maps to `:database_unavailable`; genuine
  `Postgrex.Error` failures surface instead of being retried as outages.

### Evidence

- Baseline: 71 tests, zero failures.
- Final `mix precommit`: 80 tests, zero failures; compilation with warnings as errors and formatting passed.
- `mix test --cover`: 80 tests passed; total coverage **91.30%**, Scheduler **96.67%**, LiquidsoapClient **91.49%**.
- Liquidsoap 2.4.5 `--check /etc/liquidsoap/radio.liq`: passed after the rework.
- `bash scripts/verify-radio-recovery.sh`: passed twice after the rework with measured rewind **0.720s** and **0.860s** against the **2.000s** limit.
- Recovery scenarios: VM exit after ACK before DB commit; startup reconciliation; repeated admission without duplication; two distinct DB requests sharing a file; Phoenix-only restart without position reset; combined Phoenix/Liquidsoap crash; interrupted complementary track before pending requests; requested FIFO before complementary audio; completion reconciliation; missing-media failure; transient resolve failure that recovers when valid media appears; boundary crash with two playing receipts; ongoing HLS sine fallback; final restart without completed-track replay.
- `bash -n scripts/verify-radio-recovery.sh`, `docker compose config`, explicit helper formatting, and `git diff --check`: passed.

All new deterministic tests inject control I/O, use the SQL sandbox, and start test processes under supervision. Integration uses local images, disposable containers, loopback-only ephemeral ports, and generated AAC. No external provider requests are made.

The recovery check caught a real asynchronous decoder-readiness race during development. Normal queues are now explicitly gated until interrupted playback completes; merely putting a resume source first in a fallback was insufficient.

## Self-review

- [x] Correctness: durable receipts replace volatile-absence completion and unsafe raw-push retries; per-row transactions isolate failures; transient resolve failures stay retryable; explicit rollback/ACK tests and real SIGKILL verification.
- [x] Security: path/control injection checks, private journal, fixed delivery identities, parameterized SQL; see `specs/security/NS20-review.md`. The allowlist now constrains only the untrusted relative path.
- [x] Performance: control I/O outside transactions and only active DB rows polled; linear admission lookup and retained receipt growth are documented deliberate limits, with a compaction/key-set upgrade path.
- [x] Clarity: existing schemas/statuses reused, obsolete active-path inference removed, no new dependency or generic recovery framework.
- [x] Scope: e08s01 task 2 recovery only; temporary-media cleanup and other operations tasks remain open. The board and task assignment were not changed.
- [x] Rules: AGENTS.md read; `docs/reglas-de-codigo.md` and CONVENTIONS.md are absent in this worktree. New code, comments, documentation, and commit messages are English.

This is a self-review, not an independent reviewer assessment. Hardware/power-loss durability and receipt compaction are explicit limits in ADR-0005, not claims established by these process-restart tests.
