## Target
NS02 review rework: player join lifecycle and manual-verification scripts/reports.

## Dependents
- `assets/js/app.js` registers `RadioPlayer`; `VolumeControl` is unchanged.
- `assets/js/radio_player.test.mjs` exercises native HLS, hls.js and hook cleanup.
- `scripts/verify-player-manual.sh` invokes the browser recorder.
- `README.md` documents that recorder; verification YAML and JSON consume its results.

## Affected stories
- e01s01: joining and maintaining live HLS playback.
- e05s01: current-track card, two-window consistency, reduced motion and Last.fm.

## Test coverage
- Add deferred native-play timeout/retry/rejection coverage to existing Node tests.
- Add offline recorder checks for suspended clocks, mandatory skips and broken cover images.
- Run existing LiveView regression and `mix precommit` without external network.
- Browser integration uses only isolated local services unless real Last.fm is explicitly enabled.

## Risk: Medium
Join cleanup is shared by native HLS and hls.js; recorder failures must never imply manual completion. Existing development services, queue state and HLS output must remain untouched.

## Recommended action
Fix all six review findings; retain an incomplete closure verdict until real-provider rendering and human auditory evidence exist. `docs/reglas-de-codigo.md` is absent from this worktree. Existing session state describes PR #4; the explicit NS02 rework request supersedes that stale handoff.
