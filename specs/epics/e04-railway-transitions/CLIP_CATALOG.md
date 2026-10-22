# Railway clip catalog

The broadcastable clips live in `priv/railway/clips/` and are described by
`priv/railway/clips/catalog.json`.

## Availability

No recordings have been contributed or selected yet. All three catalog slots
are registered as `pending` so the interlude policy cannot broadcast an
unverified asset while the story remains blocked on content.

| ID | Classification | Origin | Duration | File | Status |
| --- | --- | --- | --- | --- | --- |
| `boarding-announcement` | announcement | pending contribution | pending | `boarding-announcement.m4a` | pending |
| `departure-melody` | melody | pending contribution | pending | `departure-melody.m4a` | pending |
| `platform-ambience` | ambience | pending contribution | pending | `platform-ambience.m4a` | pending |

Availability log:

- 2026-10-22: catalog created; 0 of 3 clips available, every slot pending a
  contributed recording and its origin/license note.

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

`prepare/3` rejects sources that do not decode. It applies
`loudnorm=I=-16:TP=-1.5:LRA=11`, then verifies the output and deletes it when
the result is not broadcastable.

## Verification

```bash
bash scripts/verify-railway-clips.sh
```

The script generates local fixtures only, so it never uses the network. It
proves four things:

- a source clip is normalized and decodes as AAC 48 kHz stereo;
- the prepared clip stays at or below -1 dB peak;
- an already clipped file is rejected with `{:error, {:peak_too_high, peak}}`;
- a corrupt file is rejected with `{:error, :undecodable}`.

The same script verifies every catalog clip marked `available`, so an
unprepared or overdriven contribution fails before it reaches the broadcast
catalog.
