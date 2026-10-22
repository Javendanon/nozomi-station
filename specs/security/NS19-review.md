# NS19 security self-review

Result: PASS for the reviewed deployment artifacts. No unresolved high-severity
findings in this diff. This is not an independent review or a dependency CVE scan.

- Public input reaches Caddy on TCP 80/443 only. Database, telnet control, Phoenix,
  and the Caddy admin API have no public host bindings.
- Database, control, and web networks are internal and separate. Caddy has no
  database/control network membership. Only Phoenix has provider API egress.
- Phoenix and Liquidsoap run as non-root users with dropped capabilities and
  `no-new-privileges`. The root initializer only owns named volumes, without a network.
- Secrets remain in external, read-only Compose file mounts. Runtime file settings
  take precedence and fail closed on missing/empty files. The protected host parent
  directory is essential because Compose does not remap secret file ownership.
- The Docker build context uses an allowlist. No credentials, local dependencies,
  generated HLS, or host build artifacts enter the image.
- The health route uses a constant SQL query and returns no connection details.
  Database outage behavior was verified through HTTPS with a 503 response.
- HLS publication allows only manifests and segments. The smoke test confirms that
  `state.config` returns 404 and manifests have `Cache-Control: no-store`.
- TLS termination preserves Phoenix SSL enforcement. Smoke TLS verification uses
  the local CA without certificate validation bypasses. All smoke networks are
  internal, with no public DNS, published ports, builds, pulls, or public ACME calls.
- The smoke test uses unique disposable resources and dummy credentials. Its
  cleanup cannot delete production project volumes.

Before deployment: select provider/domain/CDN, pin reviewed image digests, approve
firewall and Docker access, arrange backups/log rotation, and review any CDN trust
or cookie-secret override. These are explicit operator gates in `docs/deployment.md`.
