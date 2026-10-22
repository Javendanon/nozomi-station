---
type: verification
context: NS20, card bd4f12b6-596b-4287-87bd-1794952b9ea3
---

# NS20 recovery verification

## Result: PASS

- Baseline: 71 tests, zero failures.
- Final `mix precommit`: 75 tests, zero failures; compilation with warnings as errors and formatting passed.
- `mix test --cover`: 75 tests passed; total coverage **91.36%**, Scheduler **100%**, LiquidsoapClient **91.49%**.
- Liquidsoap 2.4.5 `--check /etc/liquidsoap/radio.liq`: passed.
- `bash scripts/verify-radio-recovery.sh`: three consecutive final runs passed. Measured rewind: **0.120s**, **0.460s**, **0.100s**, all below the **2.000s** limit.
- Recovery scenarios: VM exit after ACK before DB commit; startup reconciliation; repeated admission without duplication; two distinct DB requests sharing a file; Phoenix-only restart without position reset; combined Phoenix/Liquidsoap crash; interrupted complementary track before pending requests; requested FIFO before complementary audio; completion reconciliation; missing-media failure; ongoing HLS sine fallback; final restart without completed-track replay.
- `bash scripts/verify-programming-priority.sh`: passed after the final recovery gate change, with a 6-second boundary wait.
- `bash scripts/verify-liquidsoap-hls.sh`: passed (AAC output and valid HLS manifest).
- `bash -n scripts/verify-radio-recovery.sh`, explicit helper formatting, and `git diff --check`: passed.

All new deterministic tests inject control I/O, use the SQL sandbox, and start test processes under supervision. Integration uses local images, disposable containers, loopback-only ephemeral ports, and generated AAC. No external provider requests are made.

The recovery check caught a real asynchronous decoder-readiness race during development. Normal queues are now explicitly gated until interrupted playback completes; merely putting a resume source first in a fallback was insufficient.

## Self-review

- [x] Correctness: durable receipts replace volatile-absence completion and unsafe raw-push retries; explicit rollback/ACK tests and real SIGKILL verification.
- [x] Security: path/control injection checks, private journal, fixed delivery identities, parameterized SQL; see `specs/security/NS20-review.md`.
- [x] Performance: only active DB rows are polled; row locks skip overlapping work. Linear admission lookup and retained receipt growth are documented deliberate limits, with a compaction/key-set upgrade path.
- [x] Clarity: existing schemas/statuses reused, obsolete active-path inference removed, no new dependency or generic recovery framework.
- [x] Scope: e08s01 task 2 recovery only; temporary-media cleanup and other operations tasks remain open. The board and task assignment were not changed.
- [x] Rules: AGENTS.md read; `docs/reglas-de-codigo.md` and CONVENTIONS.md are absent in this worktree. New code, comments, documentation, and commit messages are English.

This is a self-review, not an independent reviewer assessment. Hardware/power-loss durability and receipt compaction are explicit limits in ADR-0005, not claims established by these process-restart tests.
