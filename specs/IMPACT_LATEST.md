---
type: impact
context: NS14 / e06s01 task 2
---

# NS14 — Local listener identity

## Target
New `NozomiStation.Identity` and `NozomiStation.Identity.Alias` modules, a `LocalIdentity` browser hook, and the existing radio LiveView/app hook registry.

## Dependents
- `lib/nozomi_station_web/router.ex`: mounts `RadioLive` at `/` and runs the new `ListenerSession` plug.
- `assets/js/app.js`: registers the existing player hooks; add the identity hook without changing playback.
- `README.md`: documents the complete browser suite for local runs. The CI workflow is untouched.
- `test/nozomi_station_web/live/radio_live_test.exs`: covers the existing radio UI.

## Affected Stories
- e06s01 task 2: generate, display, persist, and regenerate railway aliases.
- e07s01: future voting must key votes by the server-owned session ID, never by alias or a client-sent ID.
- e05s01: preserve radio playback and metadata updates.

## Test Coverage
- Add `test/nozomi/identity/alias_test.exs` for all five alias components and regeneration.
- Add identity boundary tests for malformed local data, ignored client IDs, and stable session IDs.
- Add `test/nozomi_station_web/plugs/listener_session_test.exs` for session-owned ID persistence and tamper repair.
- Add offline Node hook tests for persistence, regeneration, reconnects, stale tabs, corrupt data, blocked reads, and failed writes.
- Extend radio LiveView tests for restoration, regeneration, shared IDs across views, and unchanged identity IDs.

## Risk: Low
No existing chat, voting, or identity implementation exists. The shared contract is new; existing player behavior remains unchanged.

## Implementation Plan
1. Generate the listener ID server-side in `NozomiStationWeb.Plugs.ListenerSession` and keep it in the Phoenix session, so clients cannot mint or adopt IDs.
2. Generate railway aliases on the server and accept only alias vocabulary from the browser.
3. Restore identity into one socket assign; regenerate only its alias. A client-sent ID is ignored.
4. Register a storage-only hook that stores the identity in `nozomi:identity`, stamps `updatedAt`, prefers the newest copy on reconnect, and retains an in-memory fallback. LiveView renders the accessible controls; the hook does not manage DOM, so it does not use `phx-update="ignore"`.
5. Run focused tests, all browser tests, and `mix precommit`; commit on the assigned branch.

## Constraints and Local Contract
- `docs/reglas-de-codigo.md` is absent from this worktree and tracked files. Follow `AGENTS.md` and existing project patterns.
- Existing `specs/state.yaml` describes completed e05 work, not this assigned card; do not overwrite unrelated lifecycle state or move the board card.
- Identity is `{id: UUID, alias: railway alias}`. Chat and voting share the ID; aliases are presentation only and are not unique identifiers.
- The session owns `id`; browser storage keeps a copy for display and alias restoration only. Clearing storage keeps the ID, extra tabs share it, and a new browser session creates a new one.
- Rate limits must key on the session-owned ID. A client-sent `id` is never trusted, so payload UUIDs cannot bypass limits.
- Browser-local identity is not authentication and does not stop deliberate spoofing from another browser session.
- Unavailable storage preserves identity only for the current page lifetime, including hook remounts and LiveView reconnects; the session ID still survives a reload.
- Anonymous alias collisions are possible by design; chat must render aliases as display names, not identifiers.
- No chat history, vote engine, accounts, external requests in automated tests, or new dependencies.
- The CI workflow is a `merge-policy.json` never-path, so the browser-suite coverage change stays out of this PR and needs separate human approval.

## Verification
- Baseline: 71 ExUnit tests and 4 browser tests passed before implementation.
- `mix precommit`: 87 tests, 0 failures, formatting and warnings clean.
- `mix test --cover`: 87 tests, 0 failures; 91.44% overall coverage, 100% for `Identity`, `Identity.Alias`, `Plugs.ListenerSession`, and `RadioLive`.
- `npm --prefix assets test`: 16 tests, 0 failures, including all hook failure and stale-tab scenarios.
- `git diff --check`: passed.
- Existing player tests still pass; automated tests use no real external services.
