"""Exercise a real CLI lock with an explicit test-only owner release barrier."""

import json
import selectors
import subprocess
import sys
import time
from pathlib import Path

# Wrap only the owner's acquisition boundary, not the lock implementation or
# contender. No production hook or finite lock-holding window is needed.
OWNER = '''
import importlib.util
import json
import sys
spec = importlib.util.spec_from_file_location("lock_runtime", sys.argv[1])
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)
original = getattr(runtime, sys.argv[2])
def acquire(*args):
    result = original(*args)
    print(json.dumps({"acquired": str(args[0])}), flush=True)
    if sys.stdin.readline() != "RELEASE\\n":
        raise RuntimeError("test owner release barrier aborted")
    return result
setattr(runtime, sys.argv[2], acquire)
sys.argv = [sys.argv[1], *sys.argv[3:]]
raise SystemExit(runtime.main())
'''


def main():
    runtime, acquisition, diagnostic, *arguments = sys.argv[1:]
    owner = subprocess.Popen(
        [sys.executable, "-c", OWNER, runtime, acquisition, *arguments],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True,
    )
    try:
        # Timeouts bound broken fixtures; only the explicit barrier releases
        # ownership, even when the parent is descheduled for longer than 2 s.
        with selectors.DefaultSelector() as selector:
            selector.register(owner.stdout, selectors.EVENT_READ)
            assert selector.select(30), "owner acquisition timed out"
            ready = owner.stdout.readline()
        assert ready, "owner exited without acknowledging acquisition"
        lock = Path(json.loads(ready)["acquired"])
        before = (lock.stat().st_ino, lock.read_bytes())
        assert json.loads(before[1])["pid"] == owner.pid, "wrong lock owner"
        assert owner.poll() is None, "owner exited before contender"
        time.sleep(2.3)  # Regression: exceed the former 2-second holding window.
        contender = subprocess.run(
            [sys.executable, runtime, *arguments],
            capture_output=True, text=True, timeout=30, check=False,
        )
        assert contender.returncode != 0, "contender incorrectly acquired lock"
        assert diagnostic in contender.stderr, contender.stdout + contender.stderr
        assert owner.poll() is None, "owner exited before explicit release"
        assert (lock.stat().st_ino, lock.read_bytes()) == before, "lock ownership changed"
        stdout, stderr = owner.communicate("RELEASE\n", timeout=30)
        assert owner.returncode == 0, stdout + stderr
        assert not lock.exists(), "owner did not release lock"
    finally:
        if owner.poll() is None:
            owner.kill()
        owner.communicate()


if __name__ == "__main__":
    main()
