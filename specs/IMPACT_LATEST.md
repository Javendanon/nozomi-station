---
type: impact
context: NS14 / e06s01 task 2
---

# NS14 — Local listener identity

## Target
New `NozomiStation.Identity` and `NozomiStation.Identity.Alias` modules, a `LocalIdentity` browser hook, and the existing radio LiveView/app hook registry.

## Dependents
- `lib/nozomi_station_web/router.ex`: mounts `RadioLive` at `/`.
- `assets/js/app.js`: registers the existing player hooks; add the identity hook without changing playback.
- `.github/workflows/test-build-release.yml` and `README.md`: run the entire browser suite instead of only player tests.
- `test/nozomi_station_web/live/radio_live_test.exs`: covers the existing radio UI.

## Affected Stories
- e06s01 task 2: generate, display, persist, and regenerate railway aliases.
- e07s01: future voting must key votes by `socket.assigns.identity.id`, never by alias.
- e05s01: preserve radio playback and metadata updates.

## Test Coverage
- Add `test/nozomi/identity/alias_test.exs` for all five alias components and regeneration.
- Add identity boundary tests for malformed local data and stable IDs.
- Add offline Node hook tests for persistence, regeneration, reconnects, corrupt data, blocked reads, and failed writes.
- Extend radio LiveView tests for restoration, regeneration, and unchanged identity IDs.

## Risk: Low
No existing chat, voting, or identity implementation exists. The shared contract is new; existing player behavior remains unchanged.

## Implementation Plan
1. Generate railway aliases on the server and validate browser-local identity data.
2. Restore identity into one socket assign; regenerate only its alias.
3. Register a storage-only hook that stores the identity in `nozomi:identity` and retains an in-memory fallback. LiveView renders the accessible controls; the hook does not manage DOM, so it does not use `phx-update="ignore"`.
4. Run focused tests, all browser tests, and `mix precommit`; commit on the assigned branch.

## Constraints and Local Contract
- `docs/reglas-de-codigo.md` is absent from this worktree and tracked files. Follow `AGENTS.md` and existing project patterns.
- Existing `specs/state.yaml` describes completed e05 work, not this assigned card; do not overwrite unrelated lifecycle state or move the board card.
- Identity is `{id: UUID, alias: railway alias}`. Chat and voting share the ID; aliases are presentation only and are not unique identifiers.
- Browser-local identity is not authentication or strong protection against multiple browsers, storage clearing, or deliberate spoofing.
- Unavailable storage preserves identity only for the current page lifetime, including hook remounts and LiveView reconnects; a full reload can create a new identity.
- No chat history, vote engine, accounts, external requests in automated tests, or new dependencies.
- The stable-ID contract is implemented in commit `0c105ff`.

## Verification
- Baseline: 71 ExUnit tests and 4 browser tests passed before implementation.
- `mix precommit`: 80 tests passed.
- `mix test --cover`: 80 tests passed; 91.33% overall coverage, 100% for both identity modules and RadioLive.
- `npm --prefix assets test`: 15 tests passed, including all hook failure scenarios.
- `mix assets.build`: Tailwind and esbuild completed successfully.
- Workflow YAML parsed successfully; its browser step runs the complete suite.
- `git diff --check`: passed.
- Existing player tests still pass; automated tests use no real external services.
