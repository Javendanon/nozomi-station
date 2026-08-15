# Impact: e02s01 Slack requests

## Target

Add a signed Slack Events endpoint, persistent asynchronous processing, provider-specific media resolution, and a prepared-request queue.

## Existing dependents

- `NozomiStationWeb.Router`: one existing public LiveView route.
- `NozomiStation.Application`: Phoenix endpoint and telemetry supervision.
- `config/runtime.exs`: existing endpoint and DNS runtime settings.
- `compose.yaml`: existing Liquidsoap service and HLS volume.

All request-processing modules are net new.

## Affected stories

- **e01s01**: the live broadcast must remain unaffected; prepared files are not connected to Liquidsoap in this story.
- **e03s01**: will consume the prepared-request boundary and queue state.
- **e05s01**: will later display current request metadata.
- **e08s01**: will own production persistence and recovery operations.

## Existing test coverage

- `radio_live_test.exs` protects the public route.
- HLS verification scripts protect the Liquidsoap service.
- No existing tests cover Slack, provider resolution, persistence, or preparation.

## Risk: Medium (6/10)

The feature adds an unauthenticated webhook and external-process boundary, but existing code has low fan-in and the broadcast path can remain unchanged.

## Recommended action

Proceed with tests at each trust boundary. Keep provider HTTP clients and media preparation behind small function parameters so tests do not require Slack, Spotify, YouTube, or downloads.
