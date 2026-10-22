# NS19 deployment impact

## Target
Production release, runtime configuration, and a separate `compose.production.yaml`.
The existing development Compose stack remains unchanged.

## Dependents
- `config/runtime.exs`: production release and migration commands require the same secrets.
- `NozomiStationWeb.Router`: adds a readiness endpoint for the container and proxy.
- Media preparation and Liquidsoap control: share `/media` through a named volume; control stays private.
- HLS player: the proxy serves the existing `/hls/` URLs without caching live manifests.
- Oban and PostgreSQL: migrations must complete before workers start.

## Affected stories
- e08s01 task 1 (partial): portable, reviewable deployment artifacts, not a live deployment.
- e01s01/e03s01: HLS output, media ownership, and private control connectivity.
- e02s01/e05s01: webhook HTTPS, assets, LiveView proxying, and HLS paths.

## Test coverage
Existing application tests cover requests, programming, and the player. Existing
HLS scripts only cover development containers. Add a readiness route test and an
isolated production smoke script covering migrations, TLS, health, published ports,
non-root execution, and volume persistence across container recreation. Block
external network access in the smoke stack; provision images separately.

## Risk: Medium
Production runtime changes affect every release, but development defaults and
Compose remain intact. Smoke tests use a unique project and disposable volumes.

## Implementation plan
1. Add and run a failing readiness-route test, then implement the route.
2. Build a non-root Phoenix release with assets, FFmpeg, and yt-dlp; add release migrations.
3. Add private production networks, external file secrets, persistent volumes, healthchecks,
   restart policies, and a Caddy TLS/HLS proxy.
4. Create and run offline smoke checks; document setup and pending provider/domain/CDN decisions.
5. Run `mix precommit`, review the diff, and commit on the supplied task branch.

## Scope boundaries
Provider selection, DNS changes, public certificates, actual deployment, recovery of
playback position, media retention, and load testing remain outside NS19. The legacy
`specs/state.yaml` describes the completed e05 branch; this card is the authority for
NS19, and that unrelated lifecycle record is not rewritten.
`docs/reglas-de-codigo.md` is absent from this worktree; `AGENTS.md` was read.
