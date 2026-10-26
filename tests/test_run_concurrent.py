"""Exercise real competing shell processes with explicitly released commands."""

import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time
import unittest

from helpers import SHELLS, SOURCE_CORE, ShellTestCase


# Homebrew Bash must not hide macOS's supported system Bash 3.2.
if Path("/bin/bash").is_file() and Path(shutil.which("bash") or "/bin/bash").resolve() != Path("/bin/bash").resolve():
    SHELLS = [*SHELLS, "/bin/bash"]

SOURCE_CONCURRENT = '. "$ENVMANAGER_DIR/lib/run-concurrent.sh"\n'


class RunConcurrentTests(ShellTestCase):
    def setUp(self):
        super().setUp()
        self.state = self.root / "concurrency state"
        self.environment["ENVMANAGER_CONCURRENCY_DIR"] = str(self.state)
        self.environment["TEST_PYTHON"] = sys.executable
        self.environment["TEST_ROOT"] = str(self.root)
        self.worker = self.root / "worker.py"
        self.worker.write_text('''
import json
import os
from pathlib import Path
import time

root = Path(os.environ["TEST_ROOT"])
identity = os.environ["TEST_ID"]
def record(event):
    fd = os.open(root / "events", os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    os.write(fd, (json.dumps([event, identity]) + "\\n").encode())
    os.close(fd)

record("start")
(root / (identity + ".started")).touch()
deadline = time.monotonic() + 12
while not (root / (identity + ".release")).exists():
    if time.monotonic() > deadline:
        raise RuntimeError("test did not release command")
    time.sleep(0.01)
record("end")
''')
        self.environment["TEST_WORKER"] = str(self.worker)
        self.processes = []
        self.addCleanup(self.stop_processes)

    def stop_processes(self):
        for process in self.processes:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
            process.communicate(timeout=3)

    def start(self, shell, identity, prefix='--key shared 2', arguments='', setup=''):
        flags = ["-f"] if Path(shell).name == "zsh" else ["--noprofile", "--norc"]
        process = subprocess.Popen(
            [shutil.which(shell), *flags, "-c", SOURCE_CONCURRENT + setup +
             f'em_run_concurrent {prefix} -- "$TEST_PYTHON" "$TEST_WORKER" {arguments}'],
            env=self.environment | {"TEST_ID": identity, "TMPDIR": str(self.root / identity)},
            cwd=self.root, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, start_new_session=True,
        )
        self.processes.append(process)
        return process

    def until(self, predicate):
        deadline = time.monotonic() + 6
        while not predicate():
            if time.monotonic() > deadline:
                self.fail("Timed out waiting for concurrent commands")
            time.sleep(0.01)

    def started(self):
        return {path.stem for path in self.root.glob("*.started")}

    def release(self, *identities):
        for identity in identities:
            (self.root / f"{identity}.release").touch()

    def finish(self, process, expected=0):
        stdout, stderr = process.communicate(timeout=6)
        self.assertEqual(process.returncode, expected, stderr)
        self.assertEqual(stdout, "")
        self.assertEqual(stderr, "")

    def requests(self):
        return [path for path in self.state.glob("*/*") if path.is_dir()]

    def owner(self, request):
        return int(request.name.split(".")[0])

    def test_limit_across_shells_refills_one_slot_and_survives_contention(self):
        processes = [self.start(SHELLS[i % len(SHELLS)], str(i)) for i in range(12)]
        self.until(lambda: len(self.started()) >= 2)
        self.until(lambda: len(self.requests()) == 12)
        self.assertEqual(len(self.started()), 2)
        first, held = sorted(self.started())
        self.release(first)
        self.until(lambda: len(self.started()) >= 3)
        self.assertEqual(len(self.started()), 3)
        self.assertFalse((self.root / f"{held}.release").exists())
        self.release(*(str(i) for i in range(12)))
        for process in processes:
            self.finish(process)
        active = set()
        peak = 0
        for event, identity in map(json.loads, (self.root / "events").read_text().splitlines()):
            if event == "start":
                active.add(identity)
                peak = max(peak, len(active))
            else:
                active.remove(identity)
        self.assertEqual(peak, 2)
        self.assertFalse(active)
        self.assertEqual(self.requests(), [])

    def test_full_argv_identity_and_argument_boundaries(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                first = self.start(shell, "first", '1', '"a b" "c"')
                self.until(lambda: "first" in self.started())
                same = self.start(shell, "same", '1', '"a b" "c"')
                split = self.start(shell, "split", '1', '"a" "b c"')
                empty = self.start(shell, "empty", '1', '"a b" "c" ""')
                newline = self.start(shell, "newline", '1', '"a b" "c\n"')
                self.until(lambda: {"first", "split", "empty", "newline"} <= self.started())
                self.until(lambda: len(self.requests()) == 5)
                self.assertNotIn("same", self.started())
                self.release("first")
                self.until(lambda: "same" in self.started())
                self.release("same", "split", "empty", "newline")
                for process in (first, same, split, empty, newline):
                    self.finish(process)
                for path in self.root.glob("*.started"):
                    path.unlink()
                for path in self.root.glob("*.release"):
                    path.unlink()

    def test_explicit_keys_group_different_arguments_and_separate_keys(self):
        first = self.start(SHELLS[0], "first", '--key "shared / key" 1', 'one')
        self.until(lambda: "first" in self.started())
        same = self.start(SHELLS[-1], "same", '--key "shared / key" 1', 'two')
        other = self.start(SHELLS[-1], "other", '--key other 1', 'one')
        self.until(lambda: "other" in self.started() and len(self.requests()) == 3)
        self.assertNotIn("same", self.started())
        self.release("first", "other")
        self.until(lambda: "same" in self.started())
        self.release("same")
        for process in (first, same, other):
            self.finish(process)

    def test_failure_io_functions_and_caller_traps(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_CORE + '''
set -eu
trap 'printf "caller trap\\n"' EXIT
record() { IFS= read -r line; printf '<%s>\\n' "$line" "$@"; return 23; }
printf 'input data\\n' | em_run_concurrent 1 record 'a b' '' 'c*d' '$(literal)' && exit 90
[ "$?" -eq 23 ] || exit 91
em_run_concurrent 1 true
''')
                self.assertEqual(result.stdout, "<input data>\n<a b>\n<>\n<c*d>\n<$(literal)>\ncaller trap\n")
                self.assertEqual(self.requests(), [])

    def test_caller_glob_options_cannot_hide_competitors(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                setup = 'set -f\nGLOBIGNORE="*"\n'
                first = self.start(shell, "first", '--key glob-options 1', setup=setup)
                self.until(lambda: "first" in self.started())
                second = self.start(shell, "second", '--key glob-options 1', setup=setup)
                self.until(lambda: len(self.requests()) == 2)
                time.sleep(0.15)
                self.assertNotIn("second", self.started())
                self.release("first")
                self.until(lambda: "second" in self.started())
                self.release("second")
                self.finish(first)
                self.finish(second)
                result = self.shell(shell, SOURCE_CONCURRENT + setup + '''
check_options() { case "$-" in *f*) ;; *) return 91 ;; esac; [ "$GLOBIGNORE" = '*' ]; }
em_run_concurrent 1 check_options
''')
                self.assertEqual(result.stdout, "")
                for path in self.root.glob("*.started"):
                    path.unlink()
                for path in self.root.glob("*.release"):
                    path.unlink()

    def test_invalid_calls_do_not_create_state(self):
        for shell in SHELLS:
            for arguments in ('', '0 true', '-1 true', '01 true', '1.5 true',
                              '1000000000 true', '1', '1 --', '--key', '--key x 0 true'):
                with self.subTest(shell=shell, arguments=arguments):
                    result = self.shell(shell, SOURCE_CONCURRENT +
                                        f'em_run_concurrent {arguments}', check=False)
                    self.assertEqual(result.returncode, 2)
                    self.assertNotEqual(result.stderr, "")
                    self.assertFalse(self.state.exists())

    def test_killed_waiter_is_reaped_without_blocking_followers(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                first = self.start(shell, "first", '--key kill-waiter 1')
                self.until(lambda: "first" in self.started())
                active = set(self.requests())
                waiter = self.start(shell, "waiter", '--key kill-waiter 1')
                self.until(lambda: len(self.requests()) == 2)
                waiting = (set(self.requests()) - active).pop()
                os.kill(self.owner(waiting), signal.SIGKILL)
                waiter.communicate(timeout=3)
                follower = self.start(shell, "follower", '--key kill-waiter 1')
                self.release("first")
                self.until(lambda: "follower" in self.started())
                self.assertNotIn("waiter", self.started())
                self.release("follower")
                self.finish(first)
                self.finish(follower)
                self.assertEqual(self.requests(), [])
                for path in self.root.glob("*.started"):
                    path.unlink()
                for path in self.root.glob("*.release"):
                    path.unlink()

    def test_interrupted_caller_keeps_slot_until_its_command_returns(self):
        for shell in SHELLS:
            for sig in (signal.SIGTERM, signal.SIGKILL):
                with self.subTest(shell=shell, signal=sig):
                    first = self.start(shell, "first", '--key killed-caller 1')
                    self.until(lambda: "first" in self.started())
                    active = self.requests()[0]
                    os.kill(self.owner(active), sig)
                    follower = self.start(shell, "follower", '--key killed-caller 1')
                    self.until(lambda: len(self.requests()) == 2)
                    time.sleep(0.15)
                    self.assertNotIn("follower", self.started())
                    self.release("first")
                    self.until(lambda: "follower" in self.started())
                    self.release("follower")
                    first.communicate(timeout=3)
                    self.finish(follower)
                    self.assertEqual(self.requests(), [])
                    for path in self.root.glob("*.started"):
                        path.unlink()
                    for path in self.root.glob("*.release"):
                        path.unlink()


if __name__ == "__main__":
    unittest.main()
