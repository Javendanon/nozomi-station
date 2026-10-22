# NS20 security review

Result: PASS. No high-confidence security findings in the recovery changes.

- Delivery keys come from fixed queue names and positive DB IDs; they cannot select arbitrary journal filenames.
- Media paths are normalized against the configured root and restricted to safe path characters before control I/O. Traversal, newlines, quotes, and annotation injection have deterministic regression tests.
- Liquidsoap separately validates admission arguments and rejects queue/path changes for existing keys. Request resolution checks the queue's audio content type.
- Control remains private to the container network with host publication restricted to loopback. No new public HTTP endpoints are introduced.
- Journal files are mounted outside public HLS storage; JSON is shape-checked rather than evaluated as code.
- SQL uses Ecto bound parameters and a constant row-lock clause. No new dependencies, application secrets, or external-provider calls are introduced.
- Verification uses disposable local services and generated media. Its abrupt exits and fixture database are guarded by an explicit verification environment flag.

Operational trust remains unchanged: host/container operators can issue raw control commands and modify local files. Retained local storage and a single writer are required; see ADR-0005.
