# Security review: e01s01

## Scope

Diff `main...feat/e01-live-broadcast`: Phoenix LiveView entry page, hls.js hook, Liquidsoap HLS container, and verification scripts.

## Result

**PASS — no findings with confidence ≥ 8/10.**

## Data-flow checks

- Browser input does not control the HLS URL, filesystem paths, or process arguments.
- LiveView renders no unescaped external content.
- The player does not use `innerHTML`, `eval`, or dynamic script construction.
- Liquidsoap publishes no ports and runs as UID 100, not root.
- Liquidsoap writes only to the dedicated `priv/static/hls` volume.
- Shell scripts use fixed project-owned commands and do not interpolate untrusted input.
- npm audit reports zero production vulnerabilities.

## Threat-model controls

| Threat | Evidence | Status |
|--------|----------|--------|
| T1 public Liquidsoap controls | `docker compose config` contains no published ports | PASS |
| T2 command injection | No shell invocation from application or media configuration | PASS |
| T3 path traversal | No client-supplied media paths exist in this story | PASS |
| T4 metadata XSS | No external metadata or unsafe DOM sink exists | PASS |
| T5 decoder isolation | Container runs as `100:101` with one writable HLS mount | PASS |

## Verification

```bash
docker compose config --format json | python3 -c 'import json,sys; s=json.load(sys.stdin)["services"]["liquidsoap"]; assert not s.get("ports") and s["user"] != "0"'
! rg -n 'innerHTML|eval\(|sh -c|system\(' assets/js/radio_player.mjs config/liquidsoap compose.yaml
npm audit --prefix assets --omit=dev
```
