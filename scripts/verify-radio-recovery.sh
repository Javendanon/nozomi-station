#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Use only local images, generated audio, isolated ports, and a disposable DB.
for command in docker ffmpeg python3 mix; do command -v "$command" >/dev/null; done
mkdir -p tmp
work=$(mktemp -d "$PWD/tmp/recovery-check.XXXXXX")
prefix="ns20-recovery-$$"
cleanup() {
  docker rm -f "$prefix-liquidsoap" "$prefix-postgres" >/dev/null 2>&1 || true
}
trap cleanup EXIT
mkdir -p "$work/media" "$work/hls" "$work/journal"
ffmpeg -loglevel error -y -f lavfi -i 'sine=frequency=660:duration=24' "$work/media/current.m4a"
ffmpeg -loglevel error -y -f lavfi -i 'sine=frequency=220:duration=2' "$work/media/waiting.m4a"

docker run -d --pull=never --name "$prefix-postgres" \
  -e POSTGRES_PASSWORD=postgres -p 127.0.0.1::5432 postgres:17-alpine >/dev/null

docker run -d --pull=never --name "$prefix-liquidsoap" --user "$(id -u):$(id -g)" \
  -p 127.0.0.1::1234 \
  -v "$PWD/config/liquidsoap:/etc/liquidsoap:ro" \
  -v "$work/media:/media:ro" -v "$work/hls:/hls" -v "$work/journal:/recovery" \
  savonet/liquidsoap:v2.4.5 /etc/liquidsoap/radio.liq >/dev/null

export RADIO_RECOVERY_VERIFY=1 MIX_ENV=test
export RECOVERY_POSTGRES_PORT
RECOVERY_POSTGRES_PORT=$(docker port "$prefix-postgres" 5432 | cut -d: -f2)
export RECOVERY_CONTROL_PORT
RECOVERY_CONTROL_PORT=$(docker port "$prefix-liquidsoap" 1234 | cut -d: -f2)
export RECOVERY_MEDIA_DIR="$work/media" RECOVERY_WORK="$work" RECOVERY_PREFIX="$prefix"

python3 - <<'PY'
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import time

work = Path(os.environ['RECOVERY_WORK'])
prefix = os.environ['RECOVERY_PREFIX']
port = int(os.environ['RECOVERY_CONTROL_PORT'])
phoenix = None


def wait_for(check, timeout=30):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            value = check()
            if value:
                return value
        except (OSError, ValueError, AssertionError):
            pass
        time.sleep(0.05)
    raise AssertionError(f'Timed out: {check.__name__}; logs: {work}')


def control(command):
    with socket.create_connection(('127.0.0.1', port), timeout=2) as connection:
        connection.sendall((command + '\nquit\n').encode())
        response = b''
        while b'\r\nEND\r\n' not in response:
            data = connection.recv(65536)
            assert data, 'Control socket closed before END'
            response += data
        return response.decode().split('\r\nEND')[0].strip()


def current():
    return json.loads(control('radio.current'))


def receipts():
    return [json.loads(path.read_text()) for path in (work / 'journal').glob('*.json')]


def run(mode, expected=0):
    result = subprocess.run(['mix', 'run', '--no-start', 'scripts/verify-radio-recovery.exs', mode],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (work / f'{mode}.log').write_text(result.stdout)
    assert result.returncode == expected, result.stdout


def start_phoenix():
    global phoenix
    log = work / f'phoenix-{time.monotonic_ns()}.log'
    with log.open('w') as output:
        phoenix = subprocess.Popen(
            ['mix', 'run', '--no-start', 'scripts/verify-radio-recovery.exs', 'serve'],
            stdout=output, stderr=subprocess.STDOUT)
    wait_for(lambda: phoenix.poll() is None and 'RECOVERY_PHOENIX_READY' in log.read_text())


def kill_phoenix():
    global phoenix
    if phoenix:
        phoenix.kill()
        phoenix.wait(timeout=10)
        phoenix = None


def restart_liquidsoap():
    global port
    subprocess.run(['docker', 'kill', '--signal', 'KILL', f'{prefix}-liquidsoap'], check=True,
                   stdout=subprocess.DEVNULL)
    subprocess.run(['docker', 'start', f'{prefix}-liquidsoap'], check=True,
                   stdout=subprocess.DEVNULL)
    # Docker can reassign an ephemeral published port after container restart.
    address = subprocess.check_output(
        ['docker', 'port', f'{prefix}-liquidsoap', '1234'], text=True).strip()
    port = int(address.rsplit(':', 1)[1])
    os.environ['RECOVERY_CONTROL_PORT'] = str(port)
    wait_for(lambda: control('version'))


try:
    wait_for(lambda: subprocess.run(
        ['docker', 'exec', f'{prefix}-postgres', 'pg_isready', '-U', 'postgres'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0)
    wait_for(lambda: control('version'))
    run('seed')
    run('fail-after-ack', expected=71)
    run('assert-ready')
    wait_for(lambda: current()['key'] == 'complementary-1' and current()['position'] >= 3)
    start_phoenix()
    run('seed-waiting')
    wait_for(lambda: len(receipts()) == 4)
    run('assert-queued')

    # Even different DB requests using the same media path must remain distinct.
    before_ids = control('request.all').split()
    assert len(before_ids) == 4, before_ids
    for _ in range(2):
        receipt = json.loads(control('radio.enqueue complementary-1 complementary /media/current.m4a'))
        assert receipt['state'] == 'playing'
    assert control('request.all').split() == before_ids, 'Duplicate delivery after ACK retry'

    before_phoenix = current()['position']
    kill_phoenix()
    start_phoenix()
    assert current()['position'] >= before_phoenix, 'Phoenix restart reset the track'

    before_crash = current()
    assert before_crash['key'] == 'complementary-1', before_crash
    kill_phoenix()
    restart_liquidsoap()
    restored = wait_for(lambda: current() if current()['key'] else None)
    assert restored['key'] == 'complementary-1', 'Pending requests displaced interrupted audio'
    rewind = before_crash['position'] - restored['offset']
    # A few frames may have played between the sample and SIGKILL.
    assert -0.25 <= rewind <= 2.0, f'Rewind outside tolerance: {rewind:.3f}s'
    print(f'recovery position: before={before_crash["position"]:.3f}s '
          f'restored={restored["offset"]:.3f}s rewind={rewind:.3f}s tolerance=2.000s', flush=True)
    start_phoenix()

    wait_for(lambda: len(receipts()) == 4 and all(r['state'] == 'played' for r in receipts()), timeout=60)
    run('assert-played')
    assert current()['key'] == '', 'Fallback did not resume'
    assert control('request.all') == '', 'Finished requests remain active'
    manifest = work / 'hls' / 'aac.m3u8'
    original_manifest = manifest.read_text()
    wait_for(lambda: manifest.read_text() != original_manifest, timeout=8)

    failed = json.loads(control('radio.enqueue requested-999 requested /media/missing.m4a'))
    assert failed['state'] == 'failed', failed
    assert current()['key'] == '', 'Unresolvable media interrupted fallback'

    # Durable completion, not an empty volatile queue, prevents replay on restart.
    restart_liquidsoap()
    assert control('request.all') == ''
    assert current()['key'] == ''
    run('assert-played')
    engine_log = subprocess.check_output(
        ['docker', 'logs', f'{prefix}-liquidsoap'], stderr=subprocess.STDOUT, text=True)
    starts = re.findall(r'radio_track_started key=([^ ]+)', engine_log)
    assert starts == ['complementary-1', 'complementary-1', 'requested-1',
                      'requested-2', 'complementary-2'], starts
    print(f'radio-recovery: OK (Phoenix restart, Liquidsoap SIGKILL, ACK failure, '
          f'4 distinct deliveries, completion receipts, fallback); logs: {work}', flush=True)
finally:
    kill_phoenix()
    logs = subprocess.run(['docker', 'logs', f'{prefix}-liquidsoap'],
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (work / 'liquidsoap.log').write_text(logs.stdout)
PY
