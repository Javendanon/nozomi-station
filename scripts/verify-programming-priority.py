#!/usr/bin/env python3
"""Verify real Liquidsoap output using only generated tones and loopback control."""

import array
import itertools
import json
import math
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parent.parent
ARTIFACTS = ROOT / "tmp/priority-verification"
HLS = ROOT / "priv/static/hls"
# Allocate complementary requests first, so playback must return to older IDs.
TONES = {"c1": 220, "c2": 330, "c3": 880, "r1": 660, "r2": 990}
EXPECTED = ["c1", "r1", "r2", "c2", "c3"]
DURATION = 12


def control(command):
    with socket.create_connection(("127.0.0.1", 1234), timeout=1) as connection:
        connection.sendall((command + "\nquit\n").encode())
        response = b""
        while b"\r\nEND\r\n" not in response:
            chunk = connection.recv(65536)
            assert chunk, f"Closed control connection: {command}"
            response += chunk
    lines = response.decode().split("\r\nEND\r\n")[0].strip().splitlines()
    assert not any(line.startswith("ERROR") for line in lines), (command, lines)
    return lines


def capture_playlist(segments, snapshots):
    playlist = HLS / "aac.m3u8"
    if not playlist.exists():
        return
    text = playlist.read_text()
    lines = text.splitlines()
    if not any(line.startswith("#EXTINF:") for line in lines):
        return
    sequence = int(next(line.split(":")[1] for line in lines if line.startswith("#EXT-X-MEDIA-SEQUENCE:")))
    assert not snapshots or sequence >= snapshots[-1]["sequence"], "HLS sequence went backwards"
    assert not any(line == "#EXT-X-DISCONTINUITY" for line in lines), "Unexpected HLS discontinuity"
    names = [line for line in lines if line and not line.startswith("#")]
    for index, name in enumerate(names, sequence):
        if index in segments:
            assert segments[index] == name, "HLS segment identity changed"
        else:
            assert not segments or index == max(segments) + 1, "HLS skipped a segment"
            shutil.copyfile(HLS / name, ARTIFACTS / name)
            segments[index] = name
    snapshots.append({"time": time.monotonic(), "sequence": sequence, "segments": names})


def observe():
    segments, snapshots, changes, queues = {}, [], [], []
    for name in ("c1", "c2", "c3"):
        control(f"complementary.push /media/priority-{name}.wav")
    deadline = time.monotonic() + 65
    requested = False
    while time.monotonic() < deadline:
        now = time.monotonic()
        lines = control("radio.current_path")
        current = Path(lines[0]).stem.removeprefix("priority-") if lines else None
        if not changes or current != changes[-1]["track"]:
            changes.append({"time": now, "track": current})
            print(f"output track: {current}", flush=True)
        first = next((change["time"] for change in changes if change["track"] == "c1"), None)
        # Deliberately arrive late, but before the audible fade starts at eight seconds.
        if first is not None and now - first >= 6 and not requested:
            for name in ("r1", "r2"):
                control(f"requested.push /media/priority-{name}.wav")
            requested = True
        queues.append({"time": now, "requested": control("requested.queue"),
                       "complementary": control("complementary.queue")})
        capture_playlist(segments, snapshots)
        played = [change["track"] for change in changes if change["track"] is not None]
        if played and changes[-1]["track"] is None and requested:
            # Wait for the final music samples to reach complete HLS segments.
            if now - changes[-1]["time"] >= 3:
                break
        time.sleep(0.1)
    else:
        raise AssertionError("Timed out waiting for all tracks and the emergency source")
    (ARTIFACTS / "observations.json").write_text(json.dumps({"changes": changes, "queues": queues,
                                                           "playlists": snapshots}, indent=2))
    observed = [change["track"] for change in changes]
    if observed[0] is None:
        observed = observed[1:]
    assert observed == EXPECTED + [None], f"FIFO/priority or extra track change failure: {observed}"
    assert len(snapshots) > 200 and len(segments) >= 20, "Insufficient HLS coverage"
    return segments, [change for change in changes if change["track"] is not None]


def analyze(segments, changes):
    transport = ARTIFACTS / "captured.ts"
    with transport.open("wb") as output:
        for _, name in sorted(segments.items()):
            with (ARTIFACTS / name).open("rb") as segment:
                shutil.copyfileobj(segment, output)
    packets = json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "a:0", "-show_packets",
        "-show_entries", "packet=pts_time,duration_time", "-of", "json", str(transport)
    ]))["packets"]
    for previous, current in zip(packets, packets[1:]):
        gap = float(current["pts_time"]) - float(previous["pts_time"]) - float(previous["duration_time"])
        assert abs(gap) < 0.002, f"HLS audio timestamp gap or duplicate: {gap:.4f}s"
    raw = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", str(transport), "-ac", "1", "-ar", "8000", "-f", "f32le", "-"
    ])
    samples = array.array("f", raw)
    if sys.byteorder != "little":
        samples.byteswap()
    window = 800  # 100 ms, with integer cycles for each generated tone.
    levels = {name: [] for name in TONES}
    rms = []
    for offset in range(0, len(samples) - window, window):
        block = samples[offset:offset + window]
        rms.append(math.sqrt(sum(value * value for value in block) / window))
        for name, frequency in TONES.items():
            coefficient = 2 * math.cos(2 * math.pi * frequency / 8000)
            first = second = 0.0
            for value in block:
                state = value + coefficient * first - second
                second, first = first, state
            levels[name].append(math.sqrt(max(0, first * first + second * second - coefficient * first * second)) * 2 / window)
    active = {}
    for name, values in levels.items():
        indices = [index for index, level in enumerate(values) if level > max(values) * 0.002]
        # AAC attack transients leak into other frequencies for isolated windows.
        runs = [list(group) for _, group in itertools.groupby(
            indices, key=lambda index, counter=itertools.count(): index - next(counter))]
        sustained = [run for run in runs if len(run) >= 3]
        assert len(sustained) == 1, f"Missing, interrupted or repeated tone {name}: {sustained}"
        active[name] = sustained[0]
    starts = {name: min(indices) / 10 for name, indices in active.items()}
    ends = {name: (max(indices) + 1) / 10 for name, indices in active.items()}
    assert sorted(starts, key=starts.get) == EXPECTED, f"Wrong audible order: {starts}"
    for outgoing, incoming in zip(EXPECTED, EXPECTED[1:]):
        overlap = ends[outgoing] - starts[incoming]
        assert 3.5 <= overlap <= 4.3, f"{outgoing} -> {incoming}: overlap {overlap:.2f}s"
        early = int((starts[incoming] + 0.5) * 10)
        late = int((ends[outgoing] - 0.5) * 10)
        assert levels[outgoing][early] > levels[outgoing][late] * 3, "Outgoing tone did not fade out"
        assert levels[incoming][late] > levels[incoming][early] * 3, "Incoming tone did not fade in"
        print(f"audible overlap {outgoing} -> {incoming}: {overlap:.2f}s")
    for name in EXPECTED:
        length = ends[name] - starts[name]
        assert DURATION - 0.5 <= length <= DURATION + 0.4, f"Truncated or repeated track {name}: {length:.2f}s"
        observed = next(change["time"] for change in changes if change["track"] == name) - changes[0]["time"]
        audible = starts[name] - starts["c1"]
        assert abs(observed - audible) < 0.6, f"{name}: metadata changed {observed - audible:.2f}s away from audible onset"
    music = rms[int(starts["c1"] * 10) + 1:int(ends["c3"] * 10) - 1]
    assert min(music) > max(music) * 0.15, "Audible gap during music"
    (ARTIFACTS / "audio-analysis.json").write_text(json.dumps({"starts": starts, "ends": ends,
                                                             "minimum_rms": min(music)}, indent=2))


if __name__ == "__main__":
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    segments, changes = observe()
    analyze(segments, changes)
    print("programming-priority: OK (FIFO, late priority, output boundaries, mixed HLS audio and continuity)")
