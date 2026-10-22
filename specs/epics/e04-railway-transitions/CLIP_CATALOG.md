# Railway clip catalog

The broadcastable clips live in `priv/railway/clips/` and are described by
`priv/railway/clips/catalog.json`.

## Availability

No recordings have been contributed or selected yet. All three catalog slots
are registered as `pending` so the interlude policy cannot broadcast an
unverified asset while the story remains blocked on content.

**NS11 remains BLOCKED, not complete.** Tooling and synthetic fixtures do not
satisfy the recording deliverable. Do not close NS11 until all three local
recordings have real origins, measured durations and passing decode/level checks.

| ID | Classification | Origin | Duration | File | Status |
| --- | --- | --- | --- | --- | --- |
| `boarding-announcement` | announcement | pending contribution | pending | `boarding-announcement.m4a` | pending |
| `departure-melody` | melody | pending contribution | pending | `departure-melody.m4a` | pending |
| `platform-ambience` | ambience | pending contribution | pending | `platform-ambience.m4a` | pending |

Availability log:

- 2026-10-22: catalog created; 0 of 3 clips available, every slot pending a
  contributed recording and its origin/license note.
- Review rework: still 0 of 3 recordings available in this worktree. Only
  generated test fixtures are present; none is a railway recording or a catalog
  contribution. Content selection/contribution remains unresolved.

## Adding a clip

1. Put the source recording somewhere outside the catalog directory.
2. Normalize it to local AAC at 48 kHz stereo and 192 kbps:

   ```bash
   MIX_ENV=test mix run --no-start -e '
   {:ok, metadata} =
     NozomiStation.Railway.Clips.prepare("source.wav", "priv/railway/clips/boarding-announcement.m4a")

   IO.inspect(metadata)
   '
   ```

3. Replace the slot's `origin` with the real source and attribution, copy the
   measured `duration_seconds`, and set `status` to `available`.
4. Run the catalog verification.

`prepare/3` rejects source/destination aliases, including symbolic and hard
links. It normalizes to a separate temporary file on the destination filesystem
using `loudnorm=I=-16:TP=-1.5:LRA=11`.

Only verified output replaces the destination, through an atomic rename.
Failure removes temporary output, never the existing destination or source.
Both normalization and verification stop on decoding errors, even recoverable AAC
packet errors.

## Verification

```bash
bash scripts/verify-railway-clips.sh
```

The script generates local fixtures only, so it never uses the network. It
checks:

- a source clip is normalized and decodes as AAC 48 kHz stereo;
- the prepared clip stays at or below -1 dB peak;
- an already clipped file is rejected with `{:error, {:peak_too_high, peak}}`;
- unreadable files and a damaged AAC packet inside a readable container are
  rejected with `{:error, :undecodable}`;
- normalizing damaged AAC fails without replacing an existing destination.

The same script verifies every catalog clip marked `available`, so an
unprepared or overdriven contribution fails before it reaches the broadcast
catalog.

Exit status `0` requires a non-empty, fully available, verified catalog. Status
`2` means fixture checks passed but catalog availability is blocked. With the
current pending entries, expect status `2`, not completion evidence for NS11.
