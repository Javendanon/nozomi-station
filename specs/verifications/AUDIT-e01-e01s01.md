# Audit gate: e01s01

## Verdict

**FAIL** — no security blocker, but three quality gates require correction before PR.

## Churn review

The repository is greenfield. Generated Phoenix files dominate line count, so review prioritized authored hotspots: `radio_player.mjs`, both verification scripts, `RadioLive`, `compose.yaml`, and `radio.liq`.

## Checklist

### Supply chain and security — PASS

- ✓ Phoenix, Liquidsoap and hls.js are tagged `[OK]` in the story plan.
- ✓ `npm audit --omit=dev`: zero vulnerabilities.
- ✓ No secrets or unsafe DOM sinks in authored code.
- ✓ No unresolved HIGH findings; `specs/security/REVIEW.md` passes.
- ✓ Liquidsoap has no public ports and runs without root.

### Provenance and metadata — FAIL

- ✗ Story spec lacks explicit `type:` and `context:` metadata.
- ✗ The Liquidsoap implementation step does not reference ADR-0001.

### Correctness and F.I.R.S.T — FAIL

- ✓ Product tests use public interfaces and pass.
- ✗ `scripts/verify-hls-sync.sh` requires the playlist segment count to grow. Once the six-segment window is full, a healthy stream can fail this assertion. Accept either segment-count growth or media-sequence growth.
- ✗ `RadioPlayer.mounted()` and `destroyed()` have no behavioral test for unavailable playback, status changes, listener cleanup, or HLS destruction.

### Scope and clarity — PASS

- ✓ Changes implement only the e01 tracer bullet.
- ✓ No speculative domain abstraction or duplicate audio scheduler.
- ✓ Authored files stay below 300 lines and functions remain focused.
- ✓ No dead or commented-out authored code.
- ✓ No Law of Demeter or SOLID violation detected.

### Refactoring smells

No Mysterious Name, Feature Envy, Data Clump, Primitive Obsession, Message Chain, or Middle Man in authored code. Docker lifecycle setup is duplicated across two independent verification scripts; extracting it now would add more interface than value.

## Rationalizations rejected

- “The synchronization script passed locally” does not make its timing assumption repeatable.
- “The hook worked in manual UAT” does not cover its failure and cleanup branches.
- “The story is greenfield” does not waive required plan metadata.

## Required fixes

1. Add story metadata and ADR provenance.
2. Make continuity verification valid before and after the playlist window fills.
3. Add hook lifecycle tests through fake DOM/audio collaborators.
4. Re-run task checks, `mix precommit`, and this audit gate.
