# Threat model: e01 continuous live broadcast

## Scope

Story `e01s01`: one local audio source enters Liquidsoap, produces HLS, and a public LiveView lets listeners join the shared live point.

## Overall risk

**MEDIUM** before controls; **LOW** after the required network and process boundaries below. No existing code findings: implementation has not started.

## Trust boundaries

1. Public browser → Phoenix and public HLS origin.
2. Phoenix → private Liquidsoap control boundary.
3. Liquidsoap → local temporary media and HLS directories.
4. Reverse proxy → Phoenix/HLS services.

## Threats and required controls

| ID | Threat | Severity | Confidence | Required control |
|----|--------|----------|------------|------------------|
| T1 | Public access to Liquidsoap control commands could alter the stream or invoke unsafe operations. | HIGH | 9/10 | Keep the control interface disabled or bound to a private container network; never publish its port. |
| T2 | A media path reaching a shell command could become command injection when requests are added later. | HIGH | 8/10 | Invoke processes with argument arrays, never shell interpolation; pass Liquidsoap only validated local paths. |
| T3 | A crafted media path could escape the temporary media directory. | HIGH | 8/10 | Resolve canonical paths and require them to remain under the configured media root. |
| T4 | Untrusted track metadata could become XSS in LiveView or client hooks. | MEDIUM | 8/10 | Render metadata as escaped text; never assign external values through `innerHTML`. |
| T5 | A decoder processes attacker-selected media in later epics. | MEDIUM | 8/10 | Run Liquidsoap/FFmpeg without root, with a read-only application filesystem and a dedicated writable media volume. |

## Security acceptance criteria

- No Liquidsoap control port appears in public container port mappings.
- Phoenix never accepts a client-provided filesystem path.
- Process execution does not invoke a shell.
- Track metadata remains escaped in server templates and JavaScript hooks.
- Media processes run as non-root.

## Deferred surfaces

Slack signatures, remote URL allowlisting and download limits belong to `e02`; chat input belongs to `e06`.

## Verification

```bash
docker compose config | grep -q liquidsoap
! docker compose config | grep -E '0\.0\.0\.0:.*(1234|8080).*liquidsoap'
```
